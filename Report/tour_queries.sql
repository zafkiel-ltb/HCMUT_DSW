-- ============================================================
-- tour_queries.sql --- bo truy van sinh ra cac khoi console
-- trong Phu luc B, muc "Kho du lieu co gi ben trong".
-- Chay: sqlcmd -S localhost -U sa -P <pwd> -C -f 65001 -d CompanyX
--              -i tour_queries.sql
-- ============================================================
SET NOCOUNT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
USE CompanyX;

-- ------------------------------------------------------------
-- [t1_schema]
-- ------------------------------------------------------------
SELECT CAST(s.name AS varchar(16)) AS nhom,
       COUNT(t.object_id) AS so_bang,
       (SELECT COUNT(*) FROM sys.views v WHERE v.schema_id = s.schema_id) AS so_view
FROM sys.schemas s LEFT JOIN sys.tables t ON t.schema_id = s.schema_id
GROUP BY s.name, s.schema_id HAVING COUNT(t.object_id) > 0
ORDER BY so_bang DESC;

-- ------------------------------------------------------------
-- [t2_rows]
-- ------------------------------------------------------------
SELECT TOP 12 CAST(s.name+'.'+t.name AS varchar(36)) AS bang,
       CAST(SUM(p.rows) AS int) AS so_dong,
       (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id=t.object_id) AS so_cot
FROM sys.tables t
JOIN sys.schemas s    ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
GROUP BY s.name, t.name, t.object_id ORDER BY so_dong DESC;

-- ------------------------------------------------------------
-- [t3_cols]
-- ------------------------------------------------------------
SELECT CAST(c.name AS varchar(16)) AS cot,
       CAST(ty.name AS varchar(10)) AS kieu,
       CAST(CASE WHEN c.is_nullable=1 THEN 'co' ELSE 'khong' END AS varchar(6)) AS nullable,
       CAST(ISNULL(fk.ref,'') AS varchar(22)) AS khoa_ngoai_toi
FROM sys.columns c
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
OUTER APPLY (SELECT TOP 1 OBJECT_NAME(f.referenced_object_id) AS ref
             FROM sys.foreign_key_columns f
             WHERE f.parent_object_id=c.object_id AND f.parent_column_id=c.column_id) fk
WHERE c.object_id = OBJECT_ID('Sales.Customer') ORDER BY c.column_id;

-- ------------------------------------------------------------
-- [t4_cust]
-- ------------------------------------------------------------
-- Ba nhom ban ghi khac nhau trong Sales.Customer
SELECT TOP 3 CustomerID, PersonID, StoreID, TerritoryID,
       CAST(AccountNumber AS varchar(12)) AS AccountNumber
FROM Sales.Customer WHERE PersonID IS NOT NULL AND StoreID IS NULL ORDER BY CustomerID;
SELECT TOP 3 CustomerID, PersonID, StoreID, TerritoryID,
       CAST(AccountNumber AS varchar(12)) AS AccountNumber
FROM Sales.Customer WHERE StoreID IS NOT NULL AND PersonID IS NOT NULL ORDER BY CustomerID;
SELECT TOP 2 CustomerID, PersonID, StoreID, TerritoryID,
       CAST(AccountNumber AS varchar(12)) AS AccountNumber
FROM Sales.Customer WHERE PersonID IS NULL ORDER BY CustomerID;

-- ------------------------------------------------------------
-- [t10_fk]
-- ------------------------------------------------------------
-- Chuoi khoa ngoai noi bang khach hang voi bang dong san pham
SELECT CAST(OBJECT_NAME(f.parent_object_id) AS varchar(26)) AS bang_con,
       CAST(COL_NAME(fc.parent_object_id, fc.parent_column_id) AS varchar(16)) AS qua_cot,
       CAST(OBJECT_NAME(f.referenced_object_id) AS varchar(20)) AS toi_bang
FROM sys.foreign_keys f
JOIN sys.foreign_key_columns fc ON fc.constraint_object_id = f.object_id
WHERE OBJECT_NAME(f.parent_object_id) IN
      ('Customer','SalesOrderHeader','SalesOrderDetail','Store')
ORDER BY bang_con, qua_cot;

-- ------------------------------------------------------------
-- [t5_order]
-- ------------------------------------------------------------
-- Mot don hang cu the: phan dau don
SELECT SalesOrderID, CONVERT(varchar(10),OrderDate,120) AS OrderDate,
       CustomerID, OnlineOrderFlag AS Online, Status,
       CAST(SubTotal AS decimal(10,2)) AS SubTotal,
       CAST(TotalDue AS decimal(10,2)) AS TotalDue
FROM Sales.SalesOrderHeader WHERE SalesOrderID = 43659;
-- ... va cac dong hang cua chinh don do
SELECT d.SalesOrderDetailID AS LineID, d.ProductID, d.OrderQty AS Qty,
       CAST(d.LineTotal AS decimal(10,2)) AS LineTotal,
       CAST(p.Name AS varchar(30)) AS SanPham
FROM Sales.SalesOrderDetail d
JOIN Production.Product p ON p.ProductID = d.ProductID
WHERE d.SalesOrderID = 43659 ORDER BY d.SalesOrderDetailID;

-- ------------------------------------------------------------
-- [t6_xml]
-- ------------------------------------------------------------
-- Khao sat nhan khau hoc KHONG duoc luu thanh cot, ma goi trong mot khoi XML
SELECT LEN(CAST(Demographics AS varchar(max))) AS do_dai_xml
FROM Person.Person WHERE BusinessEntityID = 13531;
-- Noi dung khoi XML do (da bo khai bao namespace o dau cho gon)
WITH x AS (SELECT CAST(Demographics AS varchar(max)) AS s
           FROM Person.Person WHERE BusinessEntityID = 13531)
SELECT CAST(SUBSTRING(s, 105 + (n-1)*72, 72) AS varchar(72)) AS noi_dung_xml
FROM x CROSS JOIN (VALUES(1),(2),(3),(4),(5),(6),(7)) v(n) ORDER BY n;
-- View Sales.vPersonDemographics tach khoi XML tren thanh cac cot dung duoc
SELECT CAST(Gender AS varchar(6)) AS GioiTinh,
       CONVERT(varchar(10), BirthDate, 120) AS NgaySinh,
       CAST(MaritalStatus AS varchar(7)) AS HonNhan,
       CAST(YearlyIncome AS varchar(13)) AS ThuNhap,
       CAST(RTRIM(Occupation) AS varchar(13)) AS NgheNghiep,
       CAST(TotalChildren AS varchar(5)) AS SoCon,
       CAST(NumberCarsOwned AS varchar(4)) AS SoXe
FROM Sales.vPersonDemographics WHERE BusinessEntityID = 13531;

-- ------------------------------------------------------------
-- [t7_terr]
-- ------------------------------------------------------------
SELECT TerritoryID AS ID, CAST(Name AS varchar(15)) AS LanhTho,
       CAST(CountryRegionCode AS varchar(4)) AS Ma,
       CAST([Group] AS varchar(14)) AS KhuVuc,
       CAST(SalesYTD AS decimal(12,2)) AS DoanhSoNam
FROM Sales.SalesTerritory ORDER BY TerritoryID;

-- ------------------------------------------------------------
-- [t8_cat]
-- ------------------------------------------------------------
-- Cay phan loai san pham: 4 danh muc lon -> 37 danh muc con -> 504 san pham
SELECT CAST(pc.Name AS varchar(12)) AS DanhMucLon,
       COUNT(DISTINCT ps.ProductSubcategoryID) AS SoDanhMucCon,
       COUNT(p.ProductID) AS SoSanPham,
       CAST(MIN(p.ListPrice) AS decimal(9,2)) AS GiaThapNhat,
       CAST(MAX(p.ListPrice) AS decimal(9,2)) AS GiaCaoNhat
FROM Production.ProductCategory pc
JOIN Production.ProductSubcategory ps ON ps.ProductCategoryID = pc.ProductCategoryID
JOIN Production.Product p             ON p.ProductSubcategoryID = ps.ProductSubcategoryID
GROUP BY pc.Name ORDER BY SoSanPham DESC;

-- ------------------------------------------------------------
-- [t9_reason]
-- ------------------------------------------------------------
-- Toan bo bang ly do mua
SELECT SalesReasonID AS ID, CAST(Name AS varchar(26)) AS LyDo,
       CAST(ReasonType AS varchar(12)) AS Nhom
FROM Sales.SalesReason ORDER BY SalesReasonID;
-- Quan he nhieu-nhieu: mot don co the gan nhieu ly do
SELECT hr.SalesOrderID AS DonHang, CAST(r.Name AS varchar(26)) AS LyDo
FROM Sales.SalesOrderHeaderSalesReason hr
JOIN Sales.SalesReason r ON r.SalesReasonID = hr.SalesReasonID
WHERE hr.SalesOrderID IN (
  SELECT TOP 2 SalesOrderID FROM Sales.SalesOrderHeaderSalesReason
  GROUP BY SalesOrderID HAVING COUNT(*) = 3)
ORDER BY hr.SalesOrderID, r.Name;
