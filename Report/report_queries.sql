-- =============================================================
-- CHUẨN BỊ: khôi phục CompanyX và chuyển sang database này
-- (Mục 2.1 trong báo cáo, phải chạy trước mọi truy vấn bên dưới)
-- =============================================================
-- [2.1] Khôi phục CompanyX từ file .bak (chạy trên master, một lần)
-- Xem tên logic của các file bên trong file .bak
RESTORE FILELISTONLY FROM DISK = '/var/opt/mssql/data/CompanyX.bak';

-- Khôi phục database, giữ tên logic gốc AdventureWorks2022
RESTORE DATABASE CompanyX
FROM DISK = '/var/opt/mssql/data/CompanyX.bak'
WITH
    MOVE 'AdventureWorks2022'     TO '/var/opt/mssql/data/CompanyX.mdf',
    MOVE 'AdventureWorks2022_log' TO '/var/opt/mssql/data/CompanyX_log.ldf',
    REPLACE, RECOVERY;

-- Chuyển sang database CompanyX cho toàn bộ truy vấn phía dưới
USE CompanyX;


-- =============================================================
-- MỤC 1.5. PHÂN TÍCH TẬP DỮ LIỆU KHÁCH HÀNG VÀ HÀNH VI RỜI BỎ
-- =============================================================

-- [1.5.1] Tổng quan về khách hàng và đơn hàng
SELECT
    COUNT(DISTINCT c.CustomerID) AS TotalCustomers,
    COUNT(DISTINCT soh.SalesOrderID) AS TotalOrders,
    CAST(MIN(soh.OrderDate) AS date) AS StartDate,
    CAST(MAX(soh.OrderDate) AS date) AS EndDate,
    DATEDIFF(month, MIN(soh.OrderDate), MAX(soh.OrderDate))
        AS TotalMonths,
    SUM(soh.TotalDue) AS TotalRevenue
FROM Sales.Customer c
LEFT JOIN Sales.SalesOrderHeader soh ON c.CustomerID = soh.CustomerID;

-- [1.5.2] Phân loại khách hàng dựa vào hai cột PersonID và StoreID
SELECT
    CASE
        WHEN c.StoreID IS NULL THEN 'Individual Customer'
        WHEN c.PersonID IS NOT NULL THEN 'Store Customer'
        ELSE 'Store Only (No Orders)'
    END AS CustomerType,
    COUNT(DISTINCT c.CustomerID) AS NumberOfCustomers,
    COUNT(DISTINCT soh.CustomerID) AS WithOrders
FROM Sales.Customer c
LEFT JOIN Sales.SalesOrderHeader soh ON soh.CustomerID = c.CustomerID
GROUP BY
    CASE
        WHEN c.StoreID IS NULL THEN 'Individual Customer'
        WHEN c.PersonID IS NOT NULL THEN 'Store Customer'
        ELSE 'Store Only (No Orders)'
    END
ORDER BY NumberOfCustomers DESC;

-- [1.5.3] Số người theo từng nhóm đối tượng trong bảng Person.Person
SELECT PersonType,
       COUNT(*) AS NumberOfPeople
FROM Person.Person
GROUP BY PersonType
ORDER BY NumberOfPeople DESC;

-- [1.5.4] Số khách hàng cá nhân theo quốc gia
SELECT cr.Name AS Country,
       COUNT(DISTINCT c.CustomerID) AS NumberOfCustomers
FROM Sales.Customer c
JOIN Person.BusinessEntityAddress bea
    ON bea.BusinessEntityID = c.PersonID
JOIN Person.Address a ON a.AddressID = bea.AddressID
JOIN Person.StateProvince sp ON sp.StateProvinceID = a.StateProvinceID
JOIN Person.CountryRegion cr
    ON cr.CountryRegionCode = sp.CountryRegionCode
WHERE c.StoreID IS NULL
GROUP BY cr.Name
ORDER BY NumberOfCustomers DESC;

-- [1.5.5] Monetary: 10 khách hàng có doanh thu cao nhất và giá trị mỗi đơn
SELECT TOP 10
    CAST(CustomerID AS varchar) AS CustomerID,
    COUNT(*) AS TotalOrders,
    CAST(SUM(TotalDue) AS decimal(18,2)) AS TotalRevenue,
    CAST(AVG(TotalDue) AS decimal(18,2)) AS AverageOrderValue
FROM Sales.SalesOrderHeader
GROUP BY CustomerID
ORDER BY TotalRevenue DESC;

-- [1.5.5] Frequency: 10 khách hàng mua nhiều lần nhất
SELECT TOP 10
    CAST(CustomerID AS varchar) AS CustomerID,
    COUNT(*) AS TotalOrders
FROM Sales.SalesOrderHeader
GROUP BY CustomerID
ORDER BY TotalOrders DESC, CustomerID;


-- =============================================================
-- MỤC 2. PHÂN TÍCH CƠ SỞ DỮ LIỆU
-- =============================================================

-- [2.2] Thống kê và phân tích kiến trúc tổng thể
-- Danh sách bảng theo schema (tham khảo, không đưa vào báo cáo)
SELECT
    [s].[name] AS [SchemaName],
    [t].[name] AS [TableName],
    [t].[create_date] AS [CreatedDate],
    [t].[modify_date] AS [ModifiedDate]
FROM [sys].[tables] AS [t]
INNER JOIN [sys].[schemas] AS [s]
    ON [s].[schema_id] = [t].[schema_id]
ORDER BY
    [s].[name],
    [t].[name];

-- [2.2] Số bảng và số cột của từng schema
SELECT
    s.name AS Schema_Name,
    COUNT(DISTINCT t.object_id) AS So_Bang,
    COUNT(c.column_id) AS So_Cot
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
JOIN sys.columns c ON t.object_id = c.object_id
GROUP BY s.name
ORDER BY So_Cot DESC;

-- [2.2] Số bảng dùng khóa đơn và khóa phức hợp
WITH PK_Stat AS (
    SELECT
        kc.parent_object_id,
        COUNT(ic.column_id) AS So_Cot_PK
    FROM sys.key_constraints kc
    JOIN sys.indexes i
        ON kc.parent_object_id = i.object_id
        AND kc.unique_index_id = i.index_id
    JOIN sys.index_columns ic
        ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    WHERE kc.type = 'PK'
    GROUP BY kc.parent_object_id, kc.name
)
SELECT
    CASE
        WHEN So_Cot_PK = 1 THEN N'Khóa đơn'
        ELSE N'Khóa phức hợp'
    END AS Loai_Khoa,
    COUNT(*) AS So_Bang
FROM PK_Stat
GROUP BY CASE WHEN So_Cot_PK = 1 THEN N'Khóa đơn' ELSE N'Khóa phức hợp' END;

-- [2.2] Danh sách khóa chính
SELECT OBJECT_SCHEMA_NAME(parent_object_id) AS SchemaName,
       OBJECT_NAME(parent_object_id)        AS TableName,
       name                                 AS PKName
FROM sys.key_constraints
WHERE type = 'PK'
ORDER BY 1, 2;

-- [2.2] Danh sách khóa ngoại và bảng được tham chiếu
SELECT OBJECT_SCHEMA_NAME(parent_object_id)     AS SchemaName,
       OBJECT_NAME(parent_object_id)            AS TableName,
       name                                     AS FKName,
       OBJECT_NAME(referenced_object_id)        AS RefTable
FROM sys.foreign_keys
ORDER BY 1, 2;

-- [2.2] Số khóa ngoại của từng schema
SELECT OBJECT_SCHEMA_NAME(parent_object_id) AS SchemaName,
       COUNT(*) AS So_Khoa_Ngoai
FROM sys.foreign_keys
GROUP BY OBJECT_SCHEMA_NAME(parent_object_id)
ORDER BY So_Khoa_Ngoai DESC;

-- [2.2] Những bảng được các bảng khác trỏ tới nhiều nhất
SELECT TOP 5
       OBJECT_SCHEMA_NAME(referenced_object_id) AS SchemaName,
       OBJECT_NAME(referenced_object_id) AS TableName,
       COUNT(*) AS So_Lan_Duoc_Tham_Chieu
FROM sys.foreign_keys
GROUP BY referenced_object_id
ORDER BY So_Lan_Duoc_Tham_Chieu DESC, TableName;

-- [2.2] Bảng con tham chiếu cùng một bảng cha từ 2 lần trở lên (tham khảo, không đưa vào báo cáo)
SELECT
    OBJECT_SCHEMA_NAME(parent_object_id)     AS Bang_Con_Schema,
    OBJECT_NAME(parent_object_id)            AS Bang_Con,
    OBJECT_SCHEMA_NAME(referenced_object_id) AS Bang_Cha_Schema,
    OBJECT_NAME(referenced_object_id)        AS Bang_Cha,
    COUNT(*)                                 AS So_Lan_Tham_Chieu
FROM sys.foreign_keys
GROUP BY parent_object_id, referenced_object_id
HAVING COUNT(*) > 1;


-- [2.3] Quy mô dữ liệu: số dòng mỗi bảng
SELECT OBJECT_SCHEMA_NAME(object_id) AS SchemaName,
       OBJECT_NAME(object_id)        AS TableName,
       row_count                     AS [RowCount]
FROM sys.dm_db_partition_stats
WHERE index_id IN (0, 1)
  AND OBJECTPROPERTY(object_id, 'IsUserTable') = 1
ORDER BY row_count DESC;

-- [2.3] Chia các bảng thành ba nhóm theo số dòng
WITH table_rows AS (
    SELECT OBJECT_NAME(object_id) AS TableName, row_count
    FROM sys.dm_db_partition_stats
    WHERE index_id IN (0, 1)
      AND OBJECTPROPERTY(object_id, 'IsUserTable') = 1
)
SELECT CASE WHEN row_count >= 10000 THEN '1. From 10,000 rows'
            WHEN row_count >= 1000 THEN '2. 1,000 - 9,999 rows'
            ELSE '3. Under 1,000 rows' END AS Nhom_Bang,
       COUNT(*) AS So_Bang,
       SUM(row_count) AS Tong_So_Dong,
       ROUND(100.0 * SUM(row_count)
             / (SELECT SUM(row_count) FROM table_rows), 2) AS Ty_Le_Dong
FROM table_rows
GROUP BY CASE WHEN row_count >= 10000 THEN '1. From 10,000 rows'
              WHEN row_count >= 1000 THEN '2. 1,000 - 9,999 rows'
              ELSE '3. Under 1,000 rows' END
ORDER BY Nhom_Bang;

-- [2.3] Kiểm tra BusinessEntity có bằng Person + Store + Vendor không
SELECT (SELECT COUNT(*) FROM Person.BusinessEntity) AS BusinessEntity,
       (SELECT COUNT(*) FROM Person.Person) AS Person,
       (SELECT COUNT(*) FROM Sales.Store) AS Store,
       (SELECT COUNT(*) FROM Purchasing.Vendor) AS Vendor;


-- =============================================================
-- MỤC 2.4. KHÁCH HÀNG TƯƠNG TÁC VỚI CÔNG TY NHƯ THẾ NÀO?
-- =============================================================

-- [2.4.1] Số khách hàng theo số lần mua
WITH orders_per_customer AS (
    SELECT CustomerID, COUNT(*) AS OrderCount
    FROM Sales.SalesOrderHeader
    GROUP BY CustomerID
)
SELECT OrderCount,
       COUNT(*) AS NumberOfCustomers,
       ROUND(100.0 * COUNT(*)
             / (SELECT COUNT(*) FROM orders_per_customer), 2) AS Percentage
FROM orders_per_customer
GROUP BY OrderCount
ORDER BY OrderCount;

-- [2.4.2] Những khách hàng lâu nhất chưa quay lại mua (tính đến 30/06/2014)
SELECT TOP 10
    CAST(CustomerID AS varchar) AS CustomerID,
    MAX(OrderDate) AS LastPurchaseDate,
    DATEDIFF(day, MAX(OrderDate), '2014-06-30') AS DaysSinceLastPurchase
FROM Sales.SalesOrderHeader
GROUP BY CustomerID
ORDER BY DaysSinceLastPurchase DESC, CustomerID;

-- [2.4.3] Khoảng cách trung bình giữa hai lần mua của từng khách
WITH gaps AS (
    SELECT CustomerID,
           DATEDIFF(day,
                    LAG(OrderDate) OVER (PARTITION BY CustomerID
                                         ORDER BY OrderDate),
                    OrderDate) AS GapDays
    FROM Sales.SalesOrderHeader
)
SELECT TOP 10
    CAST(CustomerID AS varchar) AS CustomerID,
    AVG(GapDays) AS AvgDaysBetweenOrders
FROM gaps
WHERE GapDays IS NOT NULL
GROUP BY CustomerID
ORDER BY AvgDaysBetweenOrders DESC, CustomerID;

-- [2.4.4] Số đơn và doanh thu theo từng năm của hai khách hàng mẫu
SELECT
    CAST(CustomerID AS varchar) AS CustomerID,
    DATENAME(year, OrderDate) AS OrderYear,
    COUNT(*) AS TotalOrders,
    CAST(SUM(TotalDue) AS decimal(18,2)) AS TotalRevenue
FROM Sales.SalesOrderHeader
WHERE CustomerID IN (11000, 11001)
GROUP BY CustomerID, DATENAME(year, OrderDate)
ORDER BY CustomerID, OrderYear;

-- [2.4.4] Số đơn, số khách có mua và doanh thu theo từng tháng
SELECT
    DATENAME(year, OrderDate) AS OrderYear,
    MONTH(OrderDate) AS OrderMonth,
    COUNT(*) AS TotalOrders,
    COUNT(DISTINCT CustomerID) AS ActiveCustomers,
    CAST(SUM(TotalDue) AS decimal(18,2)) AS Revenue
FROM Sales.SalesOrderHeader
GROUP BY DATENAME(year, OrderDate), MONTH(OrderDate)
ORDER BY OrderYear, OrderMonth;

