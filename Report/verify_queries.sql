-- ============================================================
-- Bộ truy vấn kiểm chứng báo cáo Dataset Analysis - CompanyX
-- Chạy trên bản sao restore từ CompanyX.bak (chỉ đọc).
-- Mốc gắn nhãn churn: 2013-06-30. Kỳ kiểm tra: 2013-07-01 .. 2014-06-30.
-- ============================================================
SET NOCOUNT ON;
-- Bat buoc cho cac truy van doc view nhan khau hoc (Sales.vPersonDemographics dung
-- phuong thuc XML). Thieu hai dong nay, script chay duoc trong DBeaver nhung loi
-- "Msg 1934 ... QUOTED_IDENTIFIER" khi chay bang sqlcmd.
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
USE CompanyX;

PRINT N'--- V01a: Thành phần doanh thu cấp đơn (Sales.SalesOrderHeader, toàn bộ 31.465 đơn) ---';
SELECT COUNT(*) AS orders,
       CAST(SUM(SubTotal) AS decimal(18,2)) AS subtotal,
       CAST(SUM(TaxAmt)   AS decimal(18,2)) AS tax,
       CAST(SUM(Freight)  AS decimal(18,2)) AS freight,
       CAST(SUM(TotalDue) AS decimal(18,2)) AS totaldue
FROM Sales.SalesOrderHeader;

PRINT N'--- V01b: Doanh thu cấp dòng hàng (Sales.SalesOrderDetail.LineTotal) ---';
SELECT COUNT(*) AS lines, CAST(SUM(LineTotal) AS decimal(18,2)) AS sum_linetotal FROM Sales.SalesOrderDetail;

PRINT N'--- V01c: Số đơn có SubTotal khác tổng LineTotal (kiểm tra nhất quán) ---';
SELECT COUNT(*) AS mismatched_orders FROM (
  SELECT h.SalesOrderID FROM Sales.SalesOrderHeader h JOIN Sales.SalesOrderDetail d ON d.SalesOrderID=h.SalesOrderID
  GROUP BY h.SalesOrderID, h.SubTotal HAVING ABS(h.SubTotal - SUM(d.LineTotal)) > 0.01) x;

PRINT N'--- V01d: Doanh thu dòng hàng theo danh mục lớn; dòng không có danh mục ---';
SELECT ISNULL(pc.Name,'(khong co danh muc)') AS category,
       COUNT(DISTINCT h.CustomerID) AS customers, COUNT(*) AS lines,
       SUM(d.OrderQty) AS qty, CAST(SUM(d.LineTotal) AS decimal(18,2)) AS linetotal
FROM Sales.SalesOrderDetail d
JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID
JOIN Production.Product p ON p.ProductID=d.ProductID
LEFT JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID
LEFT JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID
GROUP BY pc.Name ORDER BY linetotal DESC;

PRINT N'--- V02a: Mã trạng thái đơn ---';
SELECT Status, COUNT(*) AS orders, CAST(SUM(TotalDue) AS decimal(18,2)) AS totaldue FROM Sales.SalesOrderHeader GROUP BY Status ORDER BY Status;

PRINT N'--- V02b: Đơn có TotalDue < 0 hoặc SubTotal < 0 ---';
SELECT SalesOrderID, CustomerID, OrderDate, Status, OnlineOrderFlag,
       CAST(SubTotal AS decimal(18,2)) AS subtotal, CAST(TaxAmt AS decimal(18,2)) AS tax, CAST(Freight AS decimal(18,2)) AS freight, CAST(TotalDue AS decimal(18,2)) AS totaldue,
       (SELECT COUNT(*) FROM Sales.SalesOrderDetail d WHERE d.SalesOrderID=h.SalesOrderID) AS n_lines,
       (SELECT CAST(SUM(LineTotal) AS decimal(18,2)) FROM Sales.SalesOrderDetail d WHERE d.SalesOrderID=h.SalesOrderID) AS sum_lines
FROM Sales.SalesOrderHeader h WHERE TotalDue<0 OR SubTotal<0;

PRINT N'--- V02c: Ba nhóm bản ghi trong Sales.Customer ---';
SELECT grp, COUNT(*) AS customers, SUM(has_order) AS with_orders FROM (
  SELECT CASE WHEN PersonID IS NULL THEN 'PersonID NULL' WHEN StoreID IS NULL THEN 'Individual' ELSE 'Store contact' END AS grp,
         CASE WHEN EXISTS (SELECT 1 FROM Sales.SalesOrderHeader h WHERE h.CustomerID=c.CustomerID) THEN 1 ELSE 0 END AS has_order
  FROM Sales.Customer c) x GROUP BY grp;

PRINT N'--- V02d: Trùng khóa? ---';
SELECT (SELECT COUNT(*) - COUNT(DISTINCT CustomerID) FROM Sales.Customer) AS dup_customer,
       (SELECT COUNT(*) - COUNT(DISTINCT SalesOrderID) FROM Sales.SalesOrderHeader) AS dup_order,
       (SELECT COUNT(*) - COUNT(DISTINCT SalesOrderDetailID) FROM Sales.SalesOrderDetail) AS dup_line,
       (SELECT COUNT(*) FROM sys.foreign_keys) AS fk_count,
       (SELECT COUNT(*) FROM sys.foreign_keys WHERE is_not_trusted=1) AS fk_untrusted;

PRINT N'--- V02e: Trước / sau khi loại 315 đơn hủy và 6 đơn hỏng (xem V18) ---';
-- Don bi loai: trang thai 6 (da huy), hoac vi pham mot trong cac rang buoc
-- dang bi tat o V17 (tien am/bang 0, so luong am/bang 0/rong, ngay nguoc).
WITH bad AS (
  SELECT SalesOrderID FROM Sales.SalesOrderHeader
   WHERE Status = 6 OR SubTotal <= 0 OR TotalDue < 0
      OR ShipDate < OrderDate OR DueDate < OrderDate
  UNION
  SELECT SalesOrderID FROM Sales.SalesOrderDetail
   WHERE OrderQty IS NULL OR OrderQty <= 0 OR UnitPrice IS NULL OR UnitPrice < 0),
ok AS (SELECT h.* FROM Sales.SalesOrderHeader h
       WHERE NOT EXISTS (SELECT 1 FROM bad WHERE bad.SalesOrderID = h.SalesOrderID))
SELECT 'Truoc' AS stage, COUNT(DISTINCT h.CustomerID) AS customers,
       COUNT(DISTINCT h.SalesOrderID) AS orders,
       (SELECT COUNT(*) FROM Sales.SalesOrderDetail) AS lines,
       CAST(SUM(h.SubTotal) AS decimal(18,2)) AS subtotal,
       CAST(SUM(h.TotalDue) AS decimal(18,2)) AS totaldue
FROM Sales.SalesOrderHeader h
UNION ALL
SELECT 'Sau', COUNT(DISTINCT o.CustomerID), COUNT(DISTINCT o.SalesOrderID),
       (SELECT COUNT(*) FROM Sales.SalesOrderDetail d JOIN ok o2 ON o2.SalesOrderID = d.SalesOrderID),
       CAST(SUM(o.SubTotal) AS decimal(18,2)), CAST(SUM(o.TotalDue) AS decimal(18,2))
FROM ok o;
SELECT 'So don bi loai' AS chi_tieu, COUNT(*) AS n FROM (
  SELECT SalesOrderID FROM Sales.SalesOrderHeader
   WHERE Status = 6 OR SubTotal <= 0 OR TotalDue < 0
      OR ShipDate < OrderDate OR DueDate < OrderDate
  UNION
  SELECT SalesOrderID FROM Sales.SalesOrderDetail
   WHERE OrderQty IS NULL OR OrderQty <= 0 OR UnitPrice IS NULL OR UnitPrice < 0) x;

PRINT N'--- V03: Kênh / loại khách: số khách, số đơn, doanh thu, TB mỗi đơn, TB mỗi khách ---';
SELECT CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END AS ctype,
       COUNT(DISTINCT h.CustomerID) AS customers, COUNT(*) AS orders,
       CAST(SUM(h.SubTotal) AS decimal(18,2)) AS subtotal, CAST(SUM(h.TotalDue) AS decimal(18,2)) AS totaldue,
       CAST(AVG(h.TotalDue) AS decimal(18,2)) AS avg_per_order,
       CAST(SUM(h.TotalDue)/COUNT(DISTINCT h.CustomerID) AS decimal(18,2)) AS avg_per_customer,
       CAST(COUNT(*)*1.0/COUNT(DISTINCT h.CustomerID) AS decimal(10,2)) AS orders_per_customer
FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID
GROUP BY CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END;

PRINT N'--- V03b: OnlineOrderFlag trùng với loại khách? ---';
SELECT CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END AS ctype, h.OnlineOrderFlag, COUNT(*) AS orders
FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID
GROUP BY CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END, h.OnlineOrderFlag;

PRINT N'--- V03c: Pareto 20/80 (ngũ phân vị theo tổng TotalDue mỗi khách) ---';
WITH s AS (SELECT CustomerID, SUM(TotalDue) AS spend FROM Sales.SalesOrderHeader GROUP BY CustomerID),
r AS (SELECT spend, NTILE(5) OVER (ORDER BY spend DESC) AS q FROM s)
SELECT q, COUNT(*) AS customers, CAST(SUM(spend) AS decimal(18,2)) AS revenue, CAST(100.0*SUM(spend)/(SELECT SUM(spend) FROM s) AS decimal(5,1)) AS pct FROM r GROUP BY q ORDER BY q;

PRINT N'--- V04a: Có cột nhãn churn nào trong DB? (tìm tên cột chứa churn/active/status ở nhóm Sales.Customer) ---';
SELECT OBJECT_SCHEMA_NAME(c.object_id)+'.'+OBJECT_NAME(c.object_id) AS tbl, c.name FROM sys.columns c WHERE c.name LIKE '%churn%' OR c.name LIKE '%active%';

PRINT N'--- V04b: Nhãn churn theo quy ước: đủ điều kiện = đơn đầu <= 2013-06-30; churn = không có đơn 2013-07-01..2014-06-30 ---';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>='2013-07-01' AND OrderDate<='2014-06-30')
SELECT COUNT(*) AS eligible,
       SUM(CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END) AS churn,
       SUM(CASE WHEN post.CustomerID IS NOT NULL THEN 1 ELSE 0 END) AS active
FROM agg LEFT JOIN post ON post.CustomerID=agg.CustomerID WHERE agg.first_dt<='2013-06-30';

PRINT N'--- V04c: Cùng nhãn, chỉ tính đơn Status=5 và TotalDue>=0 ---';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt FROM Sales.SalesOrderHeader WHERE Status=5 AND TotalDue>=0 GROUP BY CustomerID),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE Status=5 AND TotalDue>=0 AND OrderDate>='2013-07-01' AND OrderDate<='2014-06-30')
SELECT COUNT(*) AS eligible, SUM(CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END) AS churn
FROM agg LEFT JOIN post ON post.CustomerID=agg.CustomerID WHERE agg.first_dt<='2013-06-30';

PRINT N'--- V04d: So sánh ngưỡng 6 tháng với điều kiện đủ thời gian quan sát nhất quán (mốc 2013-12-31, kỳ kiểm tra 2014-01-01..2014-06-30) ---';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>='2014-01-01' AND OrderDate<='2014-06-30')
SELECT COUNT(*) AS eligible, SUM(CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END) AS churn_6m
FROM agg LEFT JOIN post ON post.CustomerID=agg.CustomerID WHERE agg.first_dt<='2013-12-31';

PRINT N'--- V04e: Nhãn theo cửa sổ im lặng tính từ cuối dữ liệu (không có điều kiện đủ thời gian) ---';
WITH lastord AS (SELECT CustomerID, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID)
SELECT SUM(CASE WHEN DATEDIFF(day,last_dt,'2014-06-30')>180 THEN 1 ELSE 0 END) AS silent_6m,
       SUM(CASE WHEN DATEDIFF(day,last_dt,'2014-06-30')>365 THEN 1 ELSE 0 END) AS silent_12m, COUNT(*) AS total FROM lastord;

PRINT N'--- V04f: Churn theo loại khách và theo lãnh thổ (nhãn V04b) ---';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>='2013-07-01' AND OrderDate<='2014-06-30'),
lab AS (SELECT agg.CustomerID, CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END AS churn FROM agg LEFT JOIN post ON post.CustomerID=agg.CustomerID WHERE first_dt<='2013-06-30')
SELECT 'type' AS dim, CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END AS val, SUM(churn) AS churn, COUNT(*) AS total FROM lab JOIN Sales.Customer c ON c.CustomerID=lab.CustomerID GROUP BY CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END
UNION ALL
SELECT 'territory', t.Name, SUM(churn), COUNT(*) FROM lab JOIN Sales.Customer c ON c.CustomerID=lab.CustomerID JOIN Sales.SalesTerritory t ON t.TerritoryID=c.TerritoryID GROUP BY t.Name
ORDER BY dim, total DESC;

PRINT N'--- V04g: Tenure & số đơn trung bình theo nhãn (tính trên toàn bộ dữ liệu, chỉ để mô tả hồi cứu) ---';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt, MAX(OrderDate) AS last_dt, COUNT(*) AS n FROM Sales.SalesOrderHeader GROUP BY CustomerID),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>='2013-07-01' AND OrderDate<='2014-06-30')
SELECT CASE WHEN post.CustomerID IS NULL THEN 'Churn' ELSE 'Active' END AS label, COUNT(*) AS n, CAST(AVG(agg.n*1.0) AS decimal(6,2)) AS avg_orders_all, CAST(AVG(DATEDIFF(day,first_dt,last_dt)*1.0) AS decimal(8,1)) AS avg_span_days
FROM agg LEFT JOIN post ON post.CustomerID=agg.CustomerID WHERE first_dt<='2013-06-30' GROUP BY CASE WHEN post.CustomerID IS NULL THEN 'Churn' ELSE 'Active' END;

PRINT N'--- V05a: Số lần mua TRƯỚC MỐC và churn (không rò rỉ) ---';
WITH pre AS (SELECT h.CustomerID, COUNT(*) AS n_pre, CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END AS ctype FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID WHERE OrderDate<='2013-06-30' GROUP BY h.CustomerID, CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>='2013-07-01' AND OrderDate<='2014-06-30')
SELECT ctype, CASE WHEN n_pre=1 THEN '1' WHEN n_pre=2 THEN '2' WHEN n_pre<=5 THEN '3-5' ELSE '6+' END AS bucket,
       SUM(CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM pre LEFT JOIN post ON post.CustomerID=pre.CustomerID
GROUP BY ctype, CASE WHEN n_pre=1 THEN '1' WHEN n_pre=2 THEN '2' WHEN n_pre<=5 THEN '3-5' ELSE '6+' END ORDER BY ctype, bucket;

PRINT N'--- V05b: Số lần mua TOÀN BỘ DỮ LIỆU và churn (cách tính cũ, bị rò rỉ) - để đối chiếu 740/4004 ---';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt, COUNT(*) AS n FROM Sales.SalesOrderHeader GROUP BY CustomerID),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>='2013-07-01' AND OrderDate<='2014-06-30')
SELECT CASE WHEN n=1 THEN '1' WHEN n=2 THEN '2' WHEN n<=5 THEN '3-5' ELSE '6+' END AS bucket, SUM(CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM agg LEFT JOIN post ON post.CustomerID=agg.CustomerID WHERE first_dt<='2013-06-30' GROUP BY CASE WHEN n=1 THEN '1' WHEN n=2 THEN '2' WHEN n<=5 THEN '3-5' ELSE '6+' END ORDER BY bucket;

PRINT N'--- V05c: Cohort (năm đơn đầu) x số lần mua trước mốc, khách cá nhân ---';
WITH pre AS (SELECT h.CustomerID, COUNT(*) AS n_pre, MIN(OrderDate) AS first_dt FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID WHERE OrderDate<='2013-06-30' AND c.StoreID IS NULL GROUP BY h.CustomerID),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>='2013-07-01' AND OrderDate<='2014-06-30')
SELECT CASE WHEN first_dt<'2012-01-01' THEN '2011' WHEN first_dt<'2013-01-01' THEN '2012' ELSE '2013H1' END AS cohort, CASE WHEN n_pre=1 THEN '1' ELSE '2+' END AS npre,
       SUM(CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM pre LEFT JOIN post ON post.CustomerID=pre.CustomerID GROUP BY CASE WHEN first_dt<'2012-01-01' THEN '2011' WHEN first_dt<'2013-01-01' THEN '2012' ELSE '2013H1' END, CASE WHEN n_pre=1 THEN '1' ELSE '2+' END ORDER BY 1,2;

PRINT N'--- V06a: Danh mục đã mua TRƯỚC MỐC (khách cá nhân, một khách có thể thuộc nhiều danh mục) ---';
WITH pre AS (SELECT DISTINCT h.CustomerID FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID WHERE OrderDate<='2013-06-30' AND c.StoreID IS NULL),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>='2013-07-01' AND OrderDate<='2014-06-30'),
cat AS (SELECT h.CustomerID, pc.Name AS category FROM Sales.SalesOrderDetail d JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID JOIN Production.Product p ON p.ProductID=d.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID WHERE h.OrderDate<='2013-06-30' GROUP BY h.CustomerID, pc.Name)
SELECT cat.category, SUM(CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM pre JOIN cat ON cat.CustomerID=pre.CustomerID LEFT JOIN post ON post.CustomerID=pre.CustomerID GROUP BY cat.category ORDER BY total DESC;

PRINT N'--- V06b: Hai nhóm loại trừ nhau: chỉ mua xe trước mốc vs có mua phụ kiện/quần áo trước mốc (khách cá nhân) ---';
WITH pre AS (SELECT DISTINCT h.CustomerID FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID WHERE OrderDate<='2013-06-30' AND c.StoreID IS NULL),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>='2013-07-01' AND OrderDate<='2014-06-30'),
cat AS (SELECT h.CustomerID, MAX(CASE WHEN pc.Name IN ('Accessories','Clothing') THEN 1 ELSE 0 END) AS has_acc FROM Sales.SalesOrderDetail d JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID JOIN Production.Product p ON p.ProductID=d.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID WHERE h.OrderDate<='2013-06-30' GROUP BY h.CustomerID)
SELECT CASE WHEN has_acc=1 THEN 'Co mua phu kien/quan ao truoc moc' ELSE 'Chi mua xe (hoac linh kien) truoc moc' END AS grp,
       SUM(CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM pre JOIN cat ON cat.CustomerID=pre.CustomerID LEFT JOIN post ON post.CustomerID=pre.CustomerID GROUP BY has_acc;

PRINT N'--- V06c: Trùng lắp giữa nhóm "2 lần trước mốc" và nhóm "có phụ kiện trước mốc" (khách cá nhân) ---';
WITH pre AS (SELECT h.CustomerID, COUNT(*) AS n_pre FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID WHERE OrderDate<='2013-06-30' AND c.StoreID IS NULL GROUP BY h.CustomerID),
cat AS (SELECT h.CustomerID, MAX(CASE WHEN pc.Name IN ('Accessories','Clothing') THEN 1 ELSE 0 END) AS has_acc FROM Sales.SalesOrderDetail d JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID JOIN Production.Product p ON p.ProductID=d.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID WHERE h.OrderDate<='2013-06-30' GROUP BY h.CustomerID)
SELECT CASE WHEN n_pre>=2 THEN '2+' ELSE '1' END AS npre, has_acc, COUNT(*) AS n FROM pre JOIN cat ON cat.CustomerID=pre.CustomerID GROUP BY CASE WHEN n_pre>=2 THEN '2+' ELSE '1' END, has_acc ORDER BY 1,2;

PRINT N'--- V06d: Danh mục toàn bộ dữ liệu: số khách và số khách thuộc >1 danh mục (online) ---';
WITH cat AS (SELECT h.CustomerID, pc.Name AS category FROM Sales.SalesOrderDetail d JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID JOIN Production.Product p ON p.ProductID=d.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID WHERE h.OnlineOrderFlag=1 GROUP BY h.CustomerID, pc.Name)
SELECT n_cat, COUNT(*) AS customers FROM (SELECT CustomerID, COUNT(*) AS n_cat FROM cat GROUP BY CustomerID) x GROUP BY n_cat ORDER BY n_cat;

PRINT N'--- V07a: Nhân khẩu học x churn (khách cá nhân đủ điều kiện). Tuổi tính tại 2013-06-30 (mốc) ---';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>='2013-07-01' AND OrderDate<='2014-06-30'),
lab AS (SELECT c.PersonID, CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END AS churn FROM agg JOIN Sales.Customer c ON c.CustomerID=agg.CustomerID LEFT JOIN post ON post.CustomerID=agg.CustomerID WHERE first_dt<='2013-06-30' AND c.StoreID IS NULL)
SELECT 'Income' AS dim, d.YearlyIncome AS val, SUM(churn) AS churn, COUNT(*) AS total, CAST(100.0*SUM(churn)/COUNT(*) AS decimal(5,1)) AS pct FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.YearlyIncome
UNION ALL SELECT 'Occupation', d.Occupation, SUM(churn), COUNT(*), CAST(100.0*SUM(churn)/COUNT(*) AS decimal(5,1)) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.Occupation
UNION ALL SELECT 'Cars', CAST(d.NumberCarsOwned AS varchar), SUM(churn), COUNT(*), CAST(100.0*SUM(churn)/COUNT(*) AS decimal(5,1)) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.NumberCarsOwned
UNION ALL SELECT 'Children', CAST(d.TotalChildren AS varchar), SUM(churn), COUNT(*), CAST(100.0*SUM(churn)/COUNT(*) AS decimal(5,1)) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.TotalChildren
UNION ALL SELECT 'HomeOwner', CAST(d.HomeOwnerFlag AS varchar), SUM(churn), COUNT(*), CAST(100.0*SUM(churn)/COUNT(*) AS decimal(5,1)) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.HomeOwnerFlag
UNION ALL SELECT 'Education', RTRIM(d.Education), SUM(churn), COUNT(*), CAST(100.0*SUM(churn)/COUNT(*) AS decimal(5,1)) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY RTRIM(d.Education)
UNION ALL SELECT 'Age@2013-06-30', CASE WHEN DATEDIFF(year,d.BirthDate,'2013-06-30')<40 THEN '<40' WHEN DATEDIFF(year,d.BirthDate,'2013-06-30')<50 THEN '40-49' WHEN DATEDIFF(year,d.BirthDate,'2013-06-30')<60 THEN '50-59' ELSE '60+' END, SUM(churn), COUNT(*), CAST(100.0*SUM(churn)/COUNT(*) AS decimal(5,1)) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY CASE WHEN DATEDIFF(year,d.BirthDate,'2013-06-30')<40 THEN '<40' WHEN DATEDIFF(year,d.BirthDate,'2013-06-30')<50 THEN '40-49' WHEN DATEDIFF(year,d.BirthDate,'2013-06-30')<60 THEN '50-59' ELSE '60+' END
UNION ALL SELECT 'Gender', d.Gender, SUM(churn), COUNT(*), CAST(100.0*SUM(churn)/COUNT(*) AS decimal(5,1)) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.Gender
UNION ALL SELECT 'Marital', d.MaritalStatus, SUM(churn), COUNT(*), CAST(100.0*SUM(churn)/COUNT(*) AS decimal(5,1)) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.MaritalStatus
UNION ALL SELECT 'EmailPromotion', CAST(p.EmailPromotion AS varchar), SUM(churn), COUNT(*), CAST(100.0*SUM(churn)/COUNT(*) AS decimal(5,1)) FROM lab JOIN Person.Person p ON p.BusinessEntityID=lab.PersonID GROUP BY p.EmailPromotion
ORDER BY dim, val;

PRINT N'--- V07b: Phân bố nhân khẩu học toàn bộ khách cá nhân (18.484), tuổi tại 2014-06-30 ---';
SELECT CASE WHEN DATEDIFF(year,BirthDate,'2014-06-30')<40 THEN '<40' WHEN DATEDIFF(year,BirthDate,'2014-06-30')<50 THEN '40-49' WHEN DATEDIFF(year,BirthDate,'2014-06-30')<60 THEN '50-59' ELSE '60+' END AS age, COUNT(*) AS n
FROM Sales.vPersonDemographics d JOIN Sales.Customer c ON c.PersonID=d.BusinessEntityID AND c.StoreID IS NULL WHERE BirthDate IS NOT NULL GROUP BY CASE WHEN DATEDIFF(year,BirthDate,'2014-06-30')<40 THEN '<40' WHEN DATEDIFF(year,BirthDate,'2014-06-30')<50 THEN '40-49' WHEN DATEDIFF(year,BirthDate,'2014-06-30')<60 THEN '50-59' ELSE '60+' END ORDER BY age;
SELECT MIN(BirthDate) AS min_birth, MAX(BirthDate) AS max_birth FROM Sales.vPersonDemographics;

PRINT N'--- V08a: Lý do mua: độ bao phủ (đơn có >=1 lý do) và số lý do mỗi đơn ---';
SELECT (SELECT COUNT(*) FROM Sales.SalesOrderHeader) AS orders,
       (SELECT COUNT(DISTINCT SalesOrderID) FROM Sales.SalesOrderHeaderSalesReason) AS orders_with_reason,
       (SELECT COUNT(*) FROM Sales.SalesOrderHeaderSalesReason) AS reason_rows;
SELECT n_reasons, COUNT(*) AS orders FROM (SELECT SalesOrderID, COUNT(*) AS n_reasons FROM Sales.SalesOrderHeaderSalesReason GROUP BY SalesOrderID) x GROUP BY n_reasons ORDER BY n_reasons;

PRINT N'--- V08b: Lý do mua theo kênh: số dòng lý do, số đơn, số khách ---';
SELECT r.Name, r.ReasonType, h.OnlineOrderFlag, COUNT(*) AS reason_rows, COUNT(DISTINCT hr.SalesOrderID) AS orders, COUNT(DISTINCT h.CustomerID) AS customers
FROM Sales.SalesOrderHeaderSalesReason hr JOIN Sales.SalesReason r ON r.SalesReasonID=hr.SalesReasonID JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=hr.SalesOrderID
GROUP BY r.Name, r.ReasonType, h.OnlineOrderFlag ORDER BY h.OnlineOrderFlag, reason_rows DESC;

PRINT N'--- V08c: Khuyến mãi: dòng hàng theo SpecialOffer.Category và kênh ---';
SELECT so.Category, h.OnlineOrderFlag, COUNT(*) AS lines, COUNT(DISTINCT h.SalesOrderID) AS orders
FROM Sales.SalesOrderDetail d JOIN Sales.SpecialOffer so ON so.SpecialOfferID=d.SpecialOfferID JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID
GROUP BY so.Category, h.OnlineOrderFlag ORDER BY 2,1;

PRINT N'--- V09a: Đơn theo quý, tách kênh ---';
SELECT YEAR(OrderDate) AS yr, DATEPART(QUARTER,OrderDate) AS q, SUM(CASE WHEN OnlineOrderFlag=1 THEN 1 ELSE 0 END) AS online_orders, SUM(CASE WHEN OnlineOrderFlag=0 THEN 1 ELSE 0 END) AS reseller_orders, COUNT(*) AS all_orders
FROM Sales.SalesOrderHeader GROUP BY YEAR(OrderDate), DATEPART(QUARTER,OrderDate) ORDER BY yr,q;

PRINT N'--- V09b: Đơn online theo tháng x năm (mùa vụ có bị tăng trưởng che lấp?) ---';
SELECT MONTH(OrderDate) AS m,
  SUM(CASE WHEN YEAR(OrderDate)=2011 THEN 1 ELSE 0 END) AS y2011, SUM(CASE WHEN YEAR(OrderDate)=2012 THEN 1 ELSE 0 END) AS y2012,
  SUM(CASE WHEN YEAR(OrderDate)=2013 THEN 1 ELSE 0 END) AS y2013, SUM(CASE WHEN YEAR(OrderDate)=2014 THEN 1 ELSE 0 END) AS y2014
FROM Sales.SalesOrderHeader WHERE OnlineOrderFlag=1 GROUP BY MONTH(OrderDate) ORDER BY m;

PRINT N'--- V10a: Bảng vs view; số cột; cardinality bảng cầu lý do mua ---';
SELECT 'tables' AS kind, COUNT(*) AS n FROM sys.tables UNION ALL SELECT 'views', COUNT(*) FROM sys.views;
SELECT i.name AS index_name, i.is_primary_key, STRING_AGG(c.name, ',') AS cols
FROM sys.indexes i JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
WHERE i.object_id=OBJECT_ID('Sales.SalesOrderHeaderSalesReason') GROUP BY i.name, i.is_primary_key;

PRINT N'--- V11: Khoảng cách giữa hai lần mua liên tiếp (khách cá nhân online) ---';
WITH o AS (SELECT CustomerID, OrderDate, LAG(OrderDate) OVER (PARTITION BY CustomerID ORDER BY OrderDate, SalesOrderID) AS prev FROM Sales.SalesOrderHeader WHERE OnlineOrderFlag=1)
SELECT COUNT(*) AS gaps, SUM(CASE WHEN DATEDIFF(day,prev,OrderDate)>365 THEN 1 ELSE 0 END) AS gaps_over_365,
       CAST(AVG(DATEDIFF(day,prev,OrderDate)*1.0) AS decimal(8,1)) AS avg_gap, COUNT(DISTINCT CustomerID) AS customers_with_gap
FROM o WHERE prev IS NOT NULL;
WITH o AS (SELECT CustomerID, OrderDate, LAG(OrderDate) OVER (PARTITION BY CustomerID ORDER BY OrderDate, SalesOrderID) AS prev FROM Sales.SalesOrderHeader WHERE OnlineOrderFlag=0)
SELECT CAST(AVG(DATEDIFF(day,prev,OrderDate)*1.0) AS decimal(8,1)) AS avg_gap_reseller, COUNT(*) AS gaps FROM o WHERE prev IS NOT NULL;

PRINT N'--- V12: Số đơn mỗi khách (toàn bộ) ---';
SELECT CASE WHEN n=1 THEN '1' WHEN n=2 THEN '2' WHEN n=3 THEN '3' WHEN n<=5 THEN '4-5' WHEN n<=12 THEN '6-12' ELSE '13+' END AS bucket, COUNT(*) AS customers
FROM (SELECT CustomerID, COUNT(*) AS n FROM Sales.SalesOrderHeader GROUP BY CustomerID) x GROUP BY CASE WHEN n=1 THEN '1' WHEN n=2 THEN '2' WHEN n=3 THEN '3' WHEN n<=5 THEN '4-5' WHEN n<=12 THEN '6-12' ELSE '13+' END ORDER BY MIN(n);

PRINT N'--- V13: So khach tung quay lai sau khoang nghi > 365 ngay (moi kenh) ---';
WITH o AS (SELECT CustomerID, OrderDate,
                  LAG(OrderDate) OVER (PARTITION BY CustomerID ORDER BY OrderDate, SalesOrderID) AS prev
           FROM Sales.SalesOrderHeader)
SELECT COUNT(DISTINCT CustomerID) AS customers_returned_after_365
FROM o WHERE prev IS NOT NULL AND DATEDIFF(day, prev, OrderDate) > 365;

PRINT N'--- V14: So khach CO DON theo lanh tho (mau so 19.119, khong tinh 701 ban ghi khong co don) ---';
SELECT t.Name AS territory,
       COUNT(DISTINCT c.CustomerID) AS customers_with_orders,
       COUNT(h.SalesOrderID)        AS orders,
       CAST(SUM(h.TotalDue) AS decimal(18,0)) AS revenue
FROM Sales.SalesTerritory t
JOIN Sales.Customer c          ON c.TerritoryID = t.TerritoryID
JOIN Sales.SalesOrderHeader h  ON h.CustomerID  = c.CustomerID
GROUP BY t.Name ORDER BY customers_with_orders DESC;

PRINT N'--- V15: Ty le don trong 12 thang cuoi (kiem chung con so 73,7%) ---';
SELECT 'tat ca'  AS kenh, COUNT(*) AS orders,
       CAST(100.0*SUM(CASE WHEN OrderDate > '2013-06-30' THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS pct_last12m
FROM Sales.SalesOrderHeader
UNION ALL
SELECT 'online', COUNT(*),
       CAST(100.0*SUM(CASE WHEN OrderDate > '2013-06-30' THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1))
FROM Sales.SalesOrderHeader WHERE OnlineOrderFlag = 1;

PRINT N'--- V16: Ty le so huu xe hoi / nha / con cua 18.484 khach ca nhan (kiem chung 77%) ---';
WITH ic AS (SELECT c.PersonID FROM Sales.Customer c WHERE c.StoreID IS NULL AND c.PersonID IS NOT NULL)
SELECT 'co it nhat 1 xe hoi' AS chi_tieu,
       SUM(CASE WHEN d.NumberCarsOwned > 0 THEN 1 ELSE 0 END) AS n,
       CAST(100.0*SUM(CASE WHEN d.NumberCarsOwned > 0 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS pct
FROM ic JOIN Sales.vPersonDemographics d ON d.BusinessEntityID = ic.PersonID
UNION ALL
SELECT 'co nha rieng', SUM(CAST(d.HomeOwnerFlag AS int)),
       CAST(100.0*SUM(CAST(d.HomeOwnerFlag AS int))/COUNT(*) AS decimal(5,1))
FROM ic JOIN Sales.vPersonDemographics d ON d.BusinessEntityID = ic.PersonID
UNION ALL
SELECT 'co con', SUM(CASE WHEN d.TotalChildren > 0 THEN 1 ELSE 0 END),
       CAST(100.0*SUM(CASE WHEN d.TotalChildren > 0 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1))
FROM ic JOIN Sales.vPersonDemographics d ON d.BusinessEntityID = ic.PersonID;

PRINT N'--- V17: Rang buoc CHECK dang bi TAT (dau hieu du lieu da bi can thiep) ---';
SELECT COUNT(*) AS tong_check,
       SUM(CASE WHEN is_disabled = 1 THEN 1 ELSE 0 END) AS bi_tat
FROM sys.check_constraints;
SELECT OBJECT_NAME(parent_object_id) AS bang, name AS rang_buoc, definition AS dieu_kien
FROM sys.check_constraints WHERE is_disabled = 1 ORDER BY bang, name;

PRINT N'--- V17b: Cot bi noi thanh cho phep rong so voi AdventureWorks goc ---';
SELECT c.name AS cot, t.name AS kieu, c.is_nullable
FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('Sales.SalesOrderDetail')
  AND c.name IN ('OrderQty','UnitPrice');

PRINT N'--- V18: Sau don hong 43677-43682, moi don mot kieu loi ---';
SELECT h.SalesOrderID AS don, COUNT(*) AS so_dong_hong,
  CASE
    WHEN SUM(CASE WHEN d.OrderQty  IS NULL THEN 1 ELSE 0 END)>0 THEN 'OrderQty = NULL'
    WHEN SUM(CASE WHEN d.OrderQty  = 0     THEN 1 ELSE 0 END)>0 THEN 'OrderQty = 0'
    WHEN SUM(CASE WHEN d.OrderQty  < 0     THEN 1 ELSE 0 END)>0 THEN 'OrderQty am'
    WHEN SUM(CASE WHEN d.UnitPrice IS NULL THEN 1 ELSE 0 END)>0 THEN 'UnitPrice = NULL'
    WHEN SUM(CASE WHEN d.UnitPrice = 0     THEN 1 ELSE 0 END)>0 THEN 'UnitPrice = 0'
    WHEN SUM(CASE WHEN d.UnitPrice < 0     THEN 1 ELSE 0 END)>0 THEN 'UnitPrice am'
  END AS kieu_hong,
  MAX(CASE WHEN h.ShipDate < h.OrderDate THEN 1 ELSE 0 END) AS ngay_giao_truoc_ngay_dat
FROM Sales.SalesOrderHeader h
JOIN Sales.SalesOrderDetail d ON d.SalesOrderID = h.SalesOrderID
WHERE d.OrderQty IS NULL OR d.OrderQty <= 0 OR d.UnitPrice IS NULL OR d.UnitPrice <= 0
GROUP BY h.SalesOrderID ORDER BY h.SalesOrderID;

PRINT N'--- V18b: Vi sao phep cong van khop du don 43677 vo nghia ---';
SELECT h.SalesOrderID, CAST(h.SubTotal AS decimal(10,2)) AS truoc_thue,
       CAST(h.TaxAmt AS decimal(10,2)) AS thue, CAST(h.Freight AS decimal(10,2)) AS van_chuyen,
       CAST(h.TotalDue AS decimal(10,2)) AS tong_phai_tra,
       COUNT(d.SalesOrderDetailID) AS so_dong, SUM(d.OrderQty) AS tong_so_luong,
       CAST(SUM(d.LineTotal) AS decimal(12,2)) AS tong_dong_hang
FROM Sales.SalesOrderHeader h LEFT JOIN Sales.SalesOrderDetail d ON d.SalesOrderID = h.SalesOrderID
WHERE h.SubTotal = 0
GROUP BY h.SalesOrderID, h.SubTotal, h.TaxAmt, h.Freight, h.TotalDue ORDER BY h.SalesOrderID;

PRINT N'--- V19: Dong hong trong bang khuyen mai va hau qua lan sang don hang ---';
SELECT SpecialOfferID, Description, StartDate, EndDate, MinQty, MaxQty
FROM Sales.SpecialOffer WHERE EndDate < StartDate OR MaxQty < 0 ORDER BY SpecialOfferID;
SELECT so.SpecialOfferID, COUNT(*) AS so_dong_ap_ngoai_han,
       CAST(SUM(d.LineTotal) AS decimal(12,2)) AS thanh_tien
FROM Sales.SalesOrderDetail d
JOIN Sales.SalesOrderHeader h ON h.SalesOrderID = d.SalesOrderID
JOIN Sales.SpecialOffer so    ON so.SpecialOfferID = d.SpecialOfferID
WHERE h.OrderDate < so.StartDate OR h.OrderDate > so.EndDate
GROUP BY so.SpecialOfferID;

PRINT N'--- V20: Ba truong khong dung duoc ---';
SELECT 'Status' AS truong, COUNT(DISTINCT Status) AS so_gia_tri_thuc_te, 6 AS so_gia_tri_tai_lieu
FROM Sales.SalesOrderHeader;
SELECT 'ShipDate' AS truong, DATEDIFF(day, OrderDate, ShipDate) AS so_ngay_giao, COUNT(*) AS so_don
FROM Sales.SalesOrderHeader GROUP BY DATEDIFF(day, OrderDate, ShipDate) ORDER BY so_don DESC;
SELECT 'CreditCard het han' AS truong, COUNT(*) AS so_don
FROM Sales.SalesOrderHeader h JOIN Sales.CreditCard cc ON cc.CreditCardID = h.CreditCardID
WHERE DATEFROMPARTS(cc.ExpYear, cc.ExpMonth, 1) < CAST(h.OrderDate AS date);

PRINT N'--- V21: Xuat xu tep sao luu va bang chung ten goc AdventureWorks2022 ---';
-- Doi ten CSDL khong doi ten logic cua tep du lieu ben trong.
SELECT name AS ten_logic_tep, type_desc AS loai, size*8/1024 AS mb
FROM sys.database_files;
-- Doc phan dau tep sao luu (chay ngoai ngu canh CompanyX):
--   RESTORE HEADERONLY   FROM DISK = '/var/opt/mssql/data/CompanyX.bak';
--   RESTORE FILELISTONLY FROM DISK = '/var/opt/mssql/data/CompanyX.bak';
SELECT name AS csdl, create_date, compatibility_level, collation_name
FROM sys.databases WHERE name = 'CompanyX';

PRINT N'--- V22: Dau vet can thiep vao cau truc bang ---';
SELECT CONVERT(varchar(10), create_date, 120) AS ngay_tao_bang, COUNT(*) AS so_bang
FROM sys.tables GROUP BY CONVERT(varchar(10), create_date, 120) ORDER BY ngay_tao_bang;
SELECT OBJECT_NAME(t.object_id) AS bang, t.create_date AS tao_luc, t.modify_date AS sua_luc,
       (SELECT COUNT(*) FROM sys.check_constraints c
        WHERE c.parent_object_id = t.object_id AND c.is_disabled = 1) AS check_bi_tat
FROM sys.tables t
WHERE t.create_date > '2023-06-01' OR t.modify_date > '2023-06-01'
ORDER BY t.modify_date;
SELECT s.name + '.' + v.name AS view_name, v.create_date
FROM sys.views v JOIN sys.schemas s ON s.schema_id = v.schema_id ORDER BY v.create_date DESC;

PRINT N'--- V23: Hat du lieu thoi gian va don vi tien te ---';
SELECT COUNT(*) AS don_co_gio_phut FROM Sales.SalesOrderHeader WHERE CAST(OrderDate AS time) <> '00:00:00';
SELECT COUNT(DISTINCT CAST(OrderDate AS date)) AS so_ngay_co_don,
       DATEDIFF(day, MIN(OrderDate), MAX(OrderDate)) + 1 AS so_ngay_trong_ky
FROM Sales.SalesOrderHeader;
-- Cot tien luu bang USD hay bang dong tien cua khach? So UnitPrice voi ListPrice.
SELECT cr.ToCurrencyCode AS ccy, COUNT(*) AS so_dong,
       SUM(CASE WHEN ABS(d.UnitPrice - p.ListPrice) < 0.01 THEN 1 ELSE 0 END) AS bang_gia_usd,
       SUM(CASE WHEN ABS(d.UnitPrice - p.ListPrice*cr.AverageRate) < 0.01 THEN 1 ELSE 0 END) AS bang_gia_quy_doi
FROM Sales.SalesOrderDetail d
JOIN Sales.SalesOrderHeader h ON h.SalesOrderID = d.SalesOrderID
JOIN Sales.CurrencyRate cr    ON cr.CurrencyRateID = h.CurrencyRateID
JOIN Production.Product p     ON p.ProductID = d.ProductID
WHERE d.UnitPriceDiscount = 0 AND h.OnlineOrderFlag = 1
GROUP BY cr.ToCurrencyCode ORDER BY so_dong DESC;

PRINT N'--- V24: Person.Person gom nhung loai nguoi nao ---';
SELECT PersonType, COUNT(*) AS n FROM Person.Person GROUP BY PersonType ORDER BY n DESC;
