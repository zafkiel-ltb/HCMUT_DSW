SET NOCOUNT ON;
USE CompanyX;

PRINT '=== DB INFO ===';
SELECT name, create_date, compatibility_level FROM sys.databases WHERE name='CompanyX';

PRINT '=== SCHEMAS & TABLE COUNTS ===';
SELECT s.name AS schema_name, COUNT(*) AS table_count
FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id
GROUP BY s.name ORDER BY s.name;

PRINT '=== ALL TABLES WITH ROW COUNTS ===';
SELECT s.name AS schema_name, t.name AS table_name, SUM(p.rows) AS row_count
FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id
JOIN sys.partitions p ON t.object_id=p.object_id AND p.index_id IN (0,1)
GROUP BY s.name, t.name ORDER BY s.name, t.name;

PRINT '=== VIEWS ===';
SELECT s.name, v.name FROM sys.views v JOIN sys.schemas s ON v.schema_id=s.schema_id ORDER BY 1,2;

PRINT '=== COLUMNS: Sales.Customer ===';
SELECT c.name, ty.name AS type, c.max_length, c.is_nullable FROM sys.columns c JOIN sys.types ty ON c.user_type_id=ty.user_type_id WHERE c.object_id=OBJECT_ID('Sales.Customer') ORDER BY c.column_id;
PRINT '=== COLUMNS: Sales.SalesOrderHeader ===';
SELECT c.name, ty.name AS type, c.max_length, c.is_nullable FROM sys.columns c JOIN sys.types ty ON c.user_type_id=ty.user_type_id WHERE c.object_id=OBJECT_ID('Sales.SalesOrderHeader') ORDER BY c.column_id;
PRINT '=== COLUMNS: Sales.SalesOrderDetail ===';
SELECT c.name, ty.name AS type, c.max_length, c.is_nullable FROM sys.columns c JOIN sys.types ty ON c.user_type_id=ty.user_type_id WHERE c.object_id=OBJECT_ID('Sales.SalesOrderDetail') ORDER BY c.column_id;
PRINT '=== COLUMNS: Person.Person ===';
SELECT c.name, ty.name AS type, c.max_length, c.is_nullable FROM sys.columns c JOIN sys.types ty ON c.user_type_id=ty.user_type_id WHERE c.object_id=OBJECT_ID('Person.Person') ORDER BY c.column_id;
PRINT '=== COLUMNS: Sales.vPersonDemographics ===';
SELECT c.name, ty.name AS type FROM sys.columns c JOIN sys.types ty ON c.user_type_id=ty.user_type_id WHERE c.object_id=OBJECT_ID('Sales.vPersonDemographics') ORDER BY c.column_id;
PRINT '=== COLUMNS: Sales.SalesTerritory ===';
SELECT c.name, ty.name AS type FROM sys.columns c JOIN sys.types ty ON c.user_type_id=ty.user_type_id WHERE c.object_id=OBJECT_ID('Sales.SalesTerritory') ORDER BY c.column_id;

PRINT '=== CUSTOMER TYPE ===';
SELECT CASE WHEN PersonID IS NOT NULL THEN 'Individual' ELSE 'Store' END AS ctype, COUNT(*) AS n FROM Sales.Customer GROUP BY CASE WHEN PersonID IS NOT NULL THEN 'Individual' ELSE 'Store' END;

PRINT '=== ORDER DATE RANGE ===';
SELECT MIN(OrderDate) AS min_date, MAX(OrderDate) AS max_date, COUNT(*) AS orders, COUNT(DISTINCT CustomerID) AS customers, SUM(TotalDue) AS revenue FROM Sales.SalesOrderHeader;

PRINT '=== ORDERS BY YEAR ===';
SELECT YEAR(OrderDate) AS yr, COUNT(*) AS orders, COUNT(DISTINCT CustomerID) AS customers, CAST(SUM(TotalDue) AS decimal(18,2)) AS revenue FROM Sales.SalesOrderHeader GROUP BY YEAR(OrderDate) ORDER BY yr;

PRINT '=== ORDERS BY YEAR-QUARTER ===';
SELECT YEAR(OrderDate) AS yr, DATEPART(QUARTER,OrderDate) AS q, COUNT(*) AS orders, COUNT(DISTINCT CustomerID) AS customers FROM Sales.SalesOrderHeader GROUP BY YEAR(OrderDate), DATEPART(QUARTER,OrderDate) ORDER BY yr,q;

PRINT '=== ONLINE vs OFFLINE ===';
SELECT OnlineOrderFlag, COUNT(*) AS orders, COUNT(DISTINCT CustomerID) AS customers, CAST(SUM(TotalDue) AS decimal(18,2)) AS revenue FROM Sales.SalesOrderHeader GROUP BY OnlineOrderFlag;

PRINT '=== TERRITORY ===';
SELECT t.Name, t.CountryRegionCode, t.[Group], COUNT(DISTINCT c.CustomerID) AS customers, COUNT(h.SalesOrderID) AS orders, CAST(SUM(h.TotalDue) AS decimal(18,2)) AS revenue
FROM Sales.SalesTerritory t LEFT JOIN Sales.Customer c ON c.TerritoryID=t.TerritoryID LEFT JOIN Sales.SalesOrderHeader h ON h.CustomerID=c.CustomerID
GROUP BY t.Name, t.CountryRegionCode, t.[Group] ORDER BY customers DESC;

PRINT '=== ORDERS PER CUSTOMER DISTRIBUTION ===';
SELECT n_orders, COUNT(*) AS customers FROM (SELECT CustomerID, COUNT(*) AS n_orders FROM Sales.SalesOrderHeader GROUP BY CustomerID) x GROUP BY n_orders ORDER BY n_orders;

PRINT '=== ORDERS PER CUSTOMER STATS ===';
SELECT AVG(n*1.0) AS avg_orders, MIN(n) AS min_o, MAX(n) AS max_o FROM (SELECT CustomerID, COUNT(*) AS n FROM Sales.SalesOrderHeader GROUP BY CustomerID) x;

PRINT '=== CUSTOMERS WITHOUT ORDERS ===';
SELECT COUNT(*) AS n FROM Sales.Customer c WHERE NOT EXISTS (SELECT 1 FROM Sales.SalesOrderHeader h WHERE h.CustomerID=c.CustomerID);

PRINT '=== RECENCY (days since last order, relative to max date) ===';
WITH mx AS (SELECT MAX(OrderDate) AS d FROM Sales.SalesOrderHeader),
lastord AS (SELECT CustomerID, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID)
SELECT bucket, COUNT(*) AS customers FROM (
 SELECT CASE WHEN DATEDIFF(day,last_dt,d)<=90 THEN '0-90' WHEN DATEDIFF(day,last_dt,d)<=180 THEN '91-180' WHEN DATEDIFF(day,last_dt,d)<=365 THEN '181-365' WHEN DATEDIFF(day,last_dt,d)<=730 THEN '366-730' ELSE '>730' END AS bucket
 FROM lastord CROSS JOIN mx) y GROUP BY bucket ORDER BY MIN(CASE bucket WHEN '0-90' THEN 1 WHEN '91-180' THEN 2 WHEN '181-365' THEN 3 WHEN '366-730' THEN 4 ELSE 5 END);

PRINT '=== CHURN LABEL: no order in last 12 months of data ===';
WITH mx AS (SELECT MAX(OrderDate) AS d FROM Sales.SalesOrderHeader),
lastord AS (SELECT CustomerID, MAX(OrderDate) AS last_dt, COUNT(*) AS n FROM Sales.SalesOrderHeader GROUP BY CustomerID)
SELECT CASE WHEN DATEDIFF(day,last_dt,d)>365 THEN 'Churn' ELSE 'Active' END AS label, COUNT(*) AS customers FROM lastord CROSS JOIN mx GROUP BY CASE WHEN DATEDIFF(day,last_dt,d)>365 THEN 'Churn' ELSE 'Active' END;

PRINT '=== CHURN LABEL (6 months) ===';
WITH mx AS (SELECT MAX(OrderDate) AS d FROM Sales.SalesOrderHeader),
lastord AS (SELECT CustomerID, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID)
SELECT CASE WHEN DATEDIFF(day,last_dt,d)>180 THEN 'Churn' ELSE 'Active' END AS label, COUNT(*) AS customers FROM lastord CROSS JOIN mx GROUP BY CASE WHEN DATEDIFF(day,last_dt,d)>180 THEN 'Churn' ELSE 'Active' END;

PRINT '=== CHURN by customer type (12m) ===';
WITH mx AS (SELECT MAX(OrderDate) AS d FROM Sales.SalesOrderHeader),
lastord AS (SELECT CustomerID, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID)
SELECT CASE WHEN c.PersonID IS NOT NULL AND c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END AS ctype,
 SUM(CASE WHEN DATEDIFF(day,l.last_dt,d)>365 THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM lastord l JOIN Sales.Customer c ON c.CustomerID=l.CustomerID CROSS JOIN mx
GROUP BY CASE WHEN c.PersonID IS NOT NULL AND c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END;

PRINT '=== CHURN by territory (12m) ===';
WITH mx AS (SELECT MAX(OrderDate) AS d FROM Sales.SalesOrderHeader),
lastord AS (SELECT CustomerID, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID)
SELECT t.Name, SUM(CASE WHEN DATEDIFF(day,l.last_dt,d)>365 THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM lastord l JOIN Sales.Customer c ON c.CustomerID=l.CustomerID JOIN Sales.SalesTerritory t ON t.TerritoryID=c.TerritoryID CROSS JOIN mx
GROUP BY t.Name ORDER BY total DESC;

PRINT '=== CHURN by online flag (12m) ===';
WITH mx AS (SELECT MAX(OrderDate) AS d FROM Sales.SalesOrderHeader),
lastord AS (SELECT CustomerID, MAX(OrderDate) AS last_dt, MAX(CAST(OnlineOrderFlag AS int)) AS online FROM Sales.SalesOrderHeader GROUP BY CustomerID)
SELECT online, SUM(CASE WHEN DATEDIFF(day,last_dt,d)>365 THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total FROM lastord CROSS JOIN mx GROUP BY online;

PRINT '=== DEMOGRAPHICS (individuals) ===';
SELECT TotalChildren, COUNT(*) AS n FROM Sales.vPersonDemographics GROUP BY TotalChildren ORDER BY 1;
SELECT Education, COUNT(*) AS n FROM Sales.vPersonDemographics GROUP BY Education ORDER BY n DESC;
SELECT Occupation, COUNT(*) AS n FROM Sales.vPersonDemographics GROUP BY Occupation ORDER BY n DESC;
SELECT Gender, COUNT(*) AS n FROM Sales.vPersonDemographics GROUP BY Gender;
SELECT MaritalStatus, COUNT(*) AS n FROM Sales.vPersonDemographics GROUP BY MaritalStatus;
SELECT YearlyIncome, COUNT(*) AS n FROM Sales.vPersonDemographics GROUP BY YearlyIncome ORDER BY n DESC;
SELECT HomeOwnerFlag, COUNT(*) AS n FROM Sales.vPersonDemographics GROUP BY HomeOwnerFlag;
SELECT NumberCarsOwned, COUNT(*) AS n FROM Sales.vPersonDemographics GROUP BY NumberCarsOwned ORDER BY 1;

PRINT '=== AGE ===';
SELECT bucket, COUNT(*) AS n FROM (SELECT CASE WHEN DATEDIFF(year,BirthDate,'2014-06-30')<30 THEN '<30' WHEN DATEDIFF(year,BirthDate,'2014-06-30')<40 THEN '30-39' WHEN DATEDIFF(year,BirthDate,'2014-06-30')<50 THEN '40-49' WHEN DATEDIFF(year,BirthDate,'2014-06-30')<60 THEN '50-59' ELSE '60+' END AS bucket FROM Sales.vPersonDemographics WHERE BirthDate IS NOT NULL) x GROUP BY bucket ORDER BY bucket;

PRINT '=== CHURN by demographics (12m) ===';
WITH mx AS (SELECT MAX(OrderDate) AS d FROM Sales.SalesOrderHeader),
lastord AS (SELECT CustomerID, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID),
lab AS (SELECT c.PersonID, CASE WHEN DATEDIFF(day,l.last_dt,d)>365 THEN 1 ELSE 0 END AS churn FROM lastord l JOIN Sales.Customer c ON c.CustomerID=l.CustomerID CROSS JOIN mx WHERE c.PersonID IS NOT NULL)
SELECT 'Gender' AS dim, d.Gender AS val, SUM(churn) AS churn, COUNT(*) AS total FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.Gender
UNION ALL SELECT 'Marital', d.MaritalStatus, SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.MaritalStatus
UNION ALL SELECT 'Education', d.Education, SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.Education
UNION ALL SELECT 'Occupation', d.Occupation, SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.Occupation
UNION ALL SELECT 'Income', d.YearlyIncome, SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.YearlyIncome
UNION ALL SELECT 'HomeOwner', CAST(d.HomeOwnerFlag AS varchar), SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.HomeOwnerFlag
UNION ALL SELECT 'Cars', CAST(d.NumberCarsOwned AS varchar), SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.NumberCarsOwned
UNION ALL SELECT 'Children', CAST(d.TotalChildren AS varchar), SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.TotalChildren
ORDER BY dim, val;

PRINT '=== PRODUCT CATEGORY SALES ===';
SELECT pc.Name AS category, COUNT(DISTINCT h.CustomerID) AS customers, SUM(d.OrderQty) AS qty, CAST(SUM(d.LineTotal) AS decimal(18,2)) AS revenue
FROM Sales.SalesOrderDetail d JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID
JOIN Production.Product p ON p.ProductID=d.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID
JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID
GROUP BY pc.Name ORDER BY revenue DESC;

PRINT '=== CHURN by first-purchase category (12m) ===';
WITH mx AS (SELECT MAX(OrderDate) AS d FROM Sales.SalesOrderHeader),
lastord AS (SELECT CustomerID, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID),
cat AS (SELECT h.CustomerID, pc.Name AS category FROM Sales.SalesOrderDetail d JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID JOIN Production.Product p ON p.ProductID=d.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID GROUP BY h.CustomerID, pc.Name)
SELECT category, SUM(CASE WHEN DATEDIFF(day,last_dt,d)>365 THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total FROM cat JOIN lastord ON lastord.CustomerID=cat.CustomerID CROSS JOIN mx GROUP BY category ORDER BY total DESC;

PRINT '=== SPECIAL OFFER usage ===';
SELECT so.Type, so.Category, COUNT(DISTINCT h.CustomerID) AS customers, COUNT(*) AS lines FROM Sales.SalesOrderDetail d JOIN Sales.SpecialOffer so ON so.SpecialOfferID=d.SpecialOfferID JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID GROUP BY so.Type, so.Category ORDER BY lines DESC;

PRINT '=== ORDER VALUE STATS ===';
SELECT CAST(AVG(TotalDue) AS decimal(18,2)) AS avg_due, CAST(MIN(TotalDue) AS decimal(18,2)) AS min_due, CAST(MAX(TotalDue) AS decimal(18,2)) AS max_due FROM Sales.SalesOrderHeader;
SELECT OnlineOrderFlag, CAST(AVG(TotalDue) AS decimal(18,2)) AS avg_due FROM Sales.SalesOrderHeader GROUP BY OnlineOrderFlag;

PRINT '=== DATA QUALITY: NULLs ===';
SELECT SUM(CASE WHEN PersonID IS NULL THEN 1 ELSE 0 END) AS null_person, SUM(CASE WHEN StoreID IS NULL THEN 1 ELSE 0 END) AS null_store, SUM(CASE WHEN TerritoryID IS NULL THEN 1 ELSE 0 END) AS null_terr, COUNT(*) AS total FROM Sales.Customer;
SELECT SUM(CASE WHEN BirthDate IS NULL THEN 1 ELSE 0 END) AS null_birth, SUM(CASE WHEN Gender IS NULL THEN 1 ELSE 0 END) AS null_gender, SUM(CASE WHEN YearlyIncome IS NULL THEN 1 ELSE 0 END) AS null_income, COUNT(*) AS total FROM Sales.vPersonDemographics;
SELECT COUNT(*) AS persons_with_demographics FROM Person.Person WHERE Demographics IS NOT NULL;
SELECT PersonType, COUNT(*) AS n FROM Person.Person GROUP BY PersonType ORDER BY n DESC;
SELECT SUM(CASE WHEN CurrencyRateID IS NULL THEN 1 ELSE 0 END) AS null_currency, SUM(CASE WHEN SalesPersonID IS NULL THEN 1 ELSE 0 END) AS null_salesperson, SUM(CASE WHEN CreditCardID IS NULL THEN 1 ELSE 0 END) AS null_cc, COUNT(*) AS total FROM Sales.SalesOrderHeader;
SELECT Status, COUNT(*) AS n FROM Sales.SalesOrderHeader GROUP BY Status;

PRINT '=== STORE ===';
SELECT COUNT(*) AS stores FROM Sales.Store;
SELECT CASE WHEN SalesPersonID IS NULL THEN 1 ELSE 0 END AS no_rep, COUNT(*) AS n FROM Sales.Store GROUP BY CASE WHEN SalesPersonID IS NULL THEN 1 ELSE 0 END;
