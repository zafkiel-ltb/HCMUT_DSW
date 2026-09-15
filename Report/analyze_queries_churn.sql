SET NOCOUNT ON;
USE CompanyX;

PRINT '=== dbo VIEW DEFINITIONS ===';
SELECT v.name, OBJECT_DEFINITION(v.object_id) AS def FROM sys.views v JOIN sys.schemas s ON v.schema_id=s.schema_id WHERE s.name='dbo';

PRINT '=== NEGATIVE / ZERO TotalDue ===';
SELECT COUNT(*) AS n_neg FROM Sales.SalesOrderHeader WHERE TotalDue<0;
SELECT COUNT(*) AS n_zero FROM Sales.SalesOrderHeader WHERE TotalDue=0;
SELECT TOP 5 SalesOrderID, CustomerID, OrderDate, SubTotal, TaxAmt, Freight, TotalDue, OnlineOrderFlag FROM Sales.SalesOrderHeader WHERE TotalDue<0;

PRINT '=== SALES REASON ===';
SELECT r.Name, r.ReasonType, COUNT(*) AS n FROM Sales.SalesOrderHeaderSalesReason hr JOIN Sales.SalesReason r ON r.SalesReasonID=hr.SalesReasonID GROUP BY r.Name, r.ReasonType ORDER BY n DESC;

PRINT '=== ELIGIBLE CHURN: first order <= 2013-06-30, churn if no order after 2013-06-30 ===';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt, MAX(OrderDate) AS last_dt, COUNT(*) AS n, SUM(TotalDue) AS spend FROM Sales.SalesOrderHeader GROUP BY CustomerID)
SELECT CASE WHEN last_dt<='2013-06-30' THEN 'Churn' ELSE 'Active' END AS label, COUNT(*) AS customers, CAST(AVG(n*1.0) AS decimal(10,2)) AS avg_orders, CAST(AVG(spend) AS decimal(18,2)) AS avg_spend
FROM agg WHERE first_dt<='2013-06-30' GROUP BY CASE WHEN last_dt<='2013-06-30' THEN 'Churn' ELSE 'Active' END;

PRINT '=== ELIGIBLE CHURN by type ===';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID)
SELECT CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END AS ctype, SUM(CASE WHEN last_dt<='2013-06-30' THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM agg JOIN Sales.Customer c ON c.CustomerID=agg.CustomerID WHERE first_dt<='2013-06-30' GROUP BY CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END;

PRINT '=== ELIGIBLE CHURN by territory ===';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID)
SELECT t.Name, SUM(CASE WHEN last_dt<='2013-06-30' THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM agg JOIN Sales.Customer c ON c.CustomerID=agg.CustomerID JOIN Sales.SalesTerritory t ON t.TerritoryID=c.TerritoryID WHERE first_dt<='2013-06-30' GROUP BY t.Name ORDER BY total DESC;

PRINT '=== ELIGIBLE CHURN by orders count bucket ===';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt, MAX(OrderDate) AS last_dt, COUNT(*) AS n FROM Sales.SalesOrderHeader GROUP BY CustomerID)
SELECT CASE WHEN n=1 THEN '1' WHEN n=2 THEN '2' WHEN n<=5 THEN '3-5' ELSE '6+' END AS bucket, SUM(CASE WHEN last_dt<='2013-06-30' THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM agg WHERE first_dt<='2013-06-30' GROUP BY CASE WHEN n=1 THEN '1' WHEN n=2 THEN '2' WHEN n<=5 THEN '3-5' ELSE '6+' END ORDER BY bucket;

PRINT '=== ELIGIBLE CHURN by demographics ===';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID),
lab AS (SELECT c.PersonID, CASE WHEN last_dt<='2013-06-30' THEN 1 ELSE 0 END AS churn FROM agg JOIN Sales.Customer c ON c.CustomerID=agg.CustomerID WHERE first_dt<='2013-06-30' AND c.StoreID IS NULL)
SELECT 'Gender' AS dim, d.Gender AS val, SUM(churn) AS churn, COUNT(*) AS total FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.Gender
UNION ALL SELECT 'Marital', d.MaritalStatus, SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.MaritalStatus
UNION ALL SELECT 'Education', d.Education, SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.Education
UNION ALL SELECT 'Occupation', d.Occupation, SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.Occupation
UNION ALL SELECT 'Income', d.YearlyIncome, SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.YearlyIncome
UNION ALL SELECT 'HomeOwner', CAST(d.HomeOwnerFlag AS varchar), SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.HomeOwnerFlag
UNION ALL SELECT 'Cars', CAST(d.NumberCarsOwned AS varchar), SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.NumberCarsOwned
UNION ALL SELECT 'Children', CAST(d.TotalChildren AS varchar), SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY d.TotalChildren
UNION ALL SELECT 'Age', CASE WHEN DATEDIFF(year,d.BirthDate,'2014-06-30')<40 THEN '<40' WHEN DATEDIFF(year,d.BirthDate,'2014-06-30')<50 THEN '40-49' WHEN DATEDIFF(year,d.BirthDate,'2014-06-30')<60 THEN '50-59' ELSE '60+' END, SUM(churn), COUNT(*) FROM lab JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=lab.PersonID GROUP BY CASE WHEN DATEDIFF(year,d.BirthDate,'2014-06-30')<40 THEN '<40' WHEN DATEDIFF(year,d.BirthDate,'2014-06-30')<50 THEN '40-49' WHEN DATEDIFF(year,d.BirthDate,'2014-06-30')<60 THEN '50-59' ELSE '60+' END
ORDER BY dim, val;

PRINT '=== ELIGIBLE CHURN by category bought ===';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID),
cat AS (SELECT h.CustomerID, pc.Name AS category FROM Sales.SalesOrderDetail d JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID JOIN Production.Product p ON p.ProductID=d.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID GROUP BY h.CustomerID, pc.Name)
SELECT category, SUM(CASE WHEN last_dt<='2013-06-30' THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total FROM cat JOIN agg ON agg.CustomerID=cat.CustomerID WHERE first_dt<='2013-06-30' GROUP BY category ORDER BY total DESC;

PRINT '=== ELIGIBLE CHURN by EmailPromotion ===';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID)
SELECT p.EmailPromotion, SUM(CASE WHEN last_dt<='2013-06-30' THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM agg JOIN Sales.Customer c ON c.CustomerID=agg.CustomerID JOIN Person.Person p ON p.BusinessEntityID=c.PersonID WHERE first_dt<='2013-06-30' AND c.StoreID IS NULL GROUP BY p.EmailPromotion ORDER BY 1;

PRINT '=== TENURE (months first->last) for eligible ===';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID)
SELECT CASE WHEN last_dt<='2013-06-30' THEN 'Churn' ELSE 'Active' END AS label, CAST(AVG(DATEDIFF(day,first_dt,last_dt)*1.0) AS decimal(10,1)) AS avg_days_span FROM agg WHERE first_dt<='2013-06-30' GROUP BY CASE WHEN last_dt<='2013-06-30' THEN 'Churn' ELSE 'Active' END;

PRINT '=== STORE DEMOGRAPHICS ===';
SELECT BusinessType, COUNT(*) AS n FROM Sales.vStoreWithDemographics GROUP BY BusinessType;
SELECT Specialty, COUNT(*) AS n FROM Sales.vStoreWithDemographics GROUP BY Specialty;
SELECT AnnualSales, COUNT(*) AS n FROM Sales.vStoreWithDemographics GROUP BY AnnualSales ORDER BY 1;
SELECT MIN(YearOpened) AS min_y, MAX(YearOpened) AS max_y, AVG(NumberEmployees) AS avg_emp, AVG(SquareFeet) AS avg_sqft FROM Sales.vStoreWithDemographics;

PRINT '=== ADDRESS / COUNTRY of individual customers ===';
SELECT CountryRegionName, COUNT(*) AS n FROM Sales.vIndividualCustomer GROUP BY CountryRegionName ORDER BY n DESC;

PRINT '=== FK COUNT ===';
SELECT COUNT(*) AS fks FROM sys.foreign_keys;
SELECT COUNT(*) AS total_columns FROM sys.columns c JOIN sys.tables t ON c.object_id=t.object_id;

PRINT '=== SalesOrderHeader Sample ===';
SELECT TOP 3 SalesOrderID, OrderDate, CustomerID, TerritoryID, OnlineOrderFlag, SubTotal, TotalDue FROM Sales.SalesOrderHeader ORDER BY SalesOrderID;
