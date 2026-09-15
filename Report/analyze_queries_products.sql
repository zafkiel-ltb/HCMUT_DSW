SET NOCOUNT ON;
USE CompanyX;

PRINT '=== TOP SUBCATEGORY by customers (individual online) ===';
SELECT TOP 12 ps.Name AS subcat, pc.Name AS cat, COUNT(DISTINCT h.CustomerID) AS customers, SUM(d.OrderQty) AS qty, CAST(SUM(d.LineTotal) AS decimal(18,0)) AS revenue
FROM Sales.SalesOrderDetail d JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID
JOIN Production.Product p ON p.ProductID=d.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID
JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID
WHERE h.OnlineOrderFlag=1 GROUP BY ps.Name, pc.Name ORDER BY customers DESC;

PRINT '=== TOP SUBCATEGORY by revenue (reseller) ===';
SELECT TOP 8 ps.Name AS subcat, pc.Name AS cat, COUNT(DISTINCT h.CustomerID) AS customers, SUM(d.OrderQty) AS qty, CAST(SUM(d.LineTotal) AS decimal(18,0)) AS revenue
FROM Sales.SalesOrderDetail d JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID
JOIN Production.Product p ON p.ProductID=d.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID
JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID
WHERE h.OnlineOrderFlag=0 GROUP BY ps.Name, pc.Name ORDER BY revenue DESC;

PRINT '=== TOP 10 PRODUCTS by customers (online) ===';
SELECT TOP 10 p.Name, COUNT(DISTINCT h.CustomerID) AS customers, SUM(d.OrderQty) AS qty
FROM Sales.SalesOrderDetail d JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID JOIN Production.Product p ON p.ProductID=d.ProductID
WHERE h.OnlineOrderFlag=1 GROUP BY p.Name ORDER BY customers DESC;

PRINT '=== CATEGORY MIX per customer (online) ===';
WITH cat AS (SELECT h.CustomerID, pc.Name AS category FROM Sales.SalesOrderDetail d JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID JOIN Production.Product p ON p.ProductID=d.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID WHERE h.OnlineOrderFlag=1 GROUP BY h.CustomerID, pc.Name)
SELECT n_cat, COUNT(*) AS customers FROM (SELECT CustomerID, COUNT(*) AS n_cat FROM cat GROUP BY CustomerID) x GROUP BY n_cat ORDER BY n_cat;

PRINT '=== BIKE buyers who also bought accessories/clothing (online) ===';
WITH cat AS (SELECT h.CustomerID, pc.Name AS category FROM Sales.SalesOrderDetail d JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID JOIN Production.Product p ON p.ProductID=d.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID WHERE h.OnlineOrderFlag=1 GROUP BY h.CustomerID, pc.Name)
SELECT SUM(CASE WHEN has_acc=1 OR has_clo=1 THEN 1 ELSE 0 END) AS bike_and_other, COUNT(*) AS bike_buyers
FROM (SELECT CustomerID, MAX(CASE WHEN category='Accessories' THEN 1 ELSE 0 END) AS has_acc, MAX(CASE WHEN category='Clothing' THEN 1 ELSE 0 END) AS has_clo, MAX(CASE WHEN category='Bikes' THEN 1 ELSE 0 END) AS has_bike FROM cat GROUP BY CustomerID) y WHERE has_bike=1;

PRINT '=== FIRST ORDER category vs churn (eligible online) ===';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader GROUP BY CustomerID),
firsto AS (SELECT h.CustomerID, MIN(h.SalesOrderID) AS soid FROM Sales.SalesOrderHeader h JOIN agg ON agg.CustomerID=h.CustomerID AND agg.first_dt=h.OrderDate GROUP BY h.CustomerID),
fcat AS (SELECT f.CustomerID, MAX(CASE WHEN pc.Name='Bikes' THEN 1 ELSE 0 END) AS first_bike FROM firsto f JOIN Sales.SalesOrderDetail d ON d.SalesOrderID=f.soid JOIN Production.Product p ON p.ProductID=d.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID GROUP BY f.CustomerID)
SELECT first_bike, SUM(CASE WHEN last_dt<='2013-06-30' THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM fcat JOIN agg ON agg.CustomerID=fcat.CustomerID JOIN Sales.Customer c ON c.CustomerID=agg.CustomerID WHERE agg.first_dt<='2013-06-30' AND c.StoreID IS NULL GROUP BY first_bike;

PRINT '=== ORDERS BY MONTH-OF-YEAR (online) ===';
SELECT MONTH(OrderDate) AS m, COUNT(*) AS orders FROM Sales.SalesOrderHeader WHERE OnlineOrderFlag=1 GROUP BY MONTH(OrderDate) ORDER BY m;

PRINT '=== AVG DAYS BETWEEN ORDERS (customers with >=2 orders) ===';
WITH o AS (SELECT CustomerID, OrderDate, LAG(OrderDate) OVER (PARTITION BY CustomerID ORDER BY OrderDate, SalesOrderID) AS prev FROM Sales.SalesOrderHeader)
SELECT CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END AS ctype, CAST(AVG(DATEDIFF(day,prev,OrderDate)*1.0) AS decimal(10,1)) AS avg_gap, COUNT(*) AS n_gaps
FROM o JOIN Sales.Customer c ON c.CustomerID=o.CustomerID WHERE prev IS NOT NULL GROUP BY CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END;

PRINT '=== MEDIAN-ish gap buckets (individual) ===';
WITH o AS (SELECT CustomerID, OrderDate, LAG(OrderDate) OVER (PARTITION BY CustomerID ORDER BY OrderDate, SalesOrderID) AS prev FROM Sales.SalesOrderHeader WHERE OnlineOrderFlag=1)
SELECT CASE WHEN g<=30 THEN '<=30' WHEN g<=90 THEN '31-90' WHEN g<=180 THEN '91-180' WHEN g<=365 THEN '181-365' ELSE '>365' END AS bucket, COUNT(*) AS n
FROM (SELECT DATEDIFF(day,prev,OrderDate) AS g FROM o WHERE prev IS NOT NULL) x GROUP BY CASE WHEN g<=30 THEN '<=30' WHEN g<=90 THEN '31-90' WHEN g<=180 THEN '91-180' WHEN g<=365 THEN '181-365' ELSE '>365' END ORDER BY MIN(g);

PRINT '=== AVG ORDER VALUE online by income ===';
SELECT d.YearlyIncome, CAST(AVG(h.TotalDue) AS decimal(10,0)) AS avg_order, COUNT(DISTINCT h.CustomerID) AS customers
FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=c.PersonID
WHERE h.OnlineOrderFlag=1 GROUP BY d.YearlyIncome ORDER BY avg_order DESC;

PRINT '=== BIKE share by age group (online) ===';
SELECT CASE WHEN DATEDIFF(year,d.BirthDate,'2014-06-30')<40 THEN '<40' WHEN DATEDIFF(year,d.BirthDate,'2014-06-30')<50 THEN '40-49' WHEN DATEDIFF(year,d.BirthDate,'2014-06-30')<60 THEN '50-59' ELSE '60+' END AS age,
 COUNT(DISTINCT h.CustomerID) AS customers,
 COUNT(DISTINCT CASE WHEN pc.Name='Bikes' THEN h.CustomerID END) AS bike_buyers
FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=c.PersonID
JOIN Sales.SalesOrderDetail sd ON sd.SalesOrderID=h.SalesOrderID JOIN Production.Product p ON p.ProductID=sd.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID
WHERE h.OnlineOrderFlag=1 GROUP BY CASE WHEN DATEDIFF(year,d.BirthDate,'2014-06-30')<40 THEN '<40' WHEN DATEDIFF(year,d.BirthDate,'2014-06-30')<50 THEN '40-49' WHEN DATEDIFF(year,d.BirthDate,'2014-06-30')<60 THEN '50-59' ELSE '60+' END ORDER BY age;

PRINT '=== PARETO: revenue share of top 20% customers ===';
WITH s AS (SELECT CustomerID, SUM(TotalDue) AS spend FROM Sales.SalesOrderHeader GROUP BY CustomerID),
r AS (SELECT spend, NTILE(5) OVER (ORDER BY spend DESC) AS q FROM s)
SELECT q, COUNT(*) AS customers, CAST(SUM(spend) AS decimal(18,0)) AS revenue, CAST(100.0*SUM(spend)/(SELECT SUM(spend) FROM s) AS decimal(5,1)) AS pct FROM r GROUP BY q ORDER BY q;

PRINT '=== ONLINE: bike subcategory (Mountain/Road/Touring) by gender ===';
SELECT d.Gender, ps.Name, COUNT(DISTINCT h.CustomerID) AS customers
FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID JOIN Sales.vPersonDemographics d ON d.BusinessEntityID=c.PersonID
JOIN Sales.SalesOrderDetail sd ON sd.SalesOrderID=h.SalesOrderID JOIN Production.Product p ON p.ProductID=sd.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID
WHERE ps.Name LIKE '%Bikes' AND h.OnlineOrderFlag=1 GROUP BY d.Gender, ps.Name ORDER BY ps.Name, d.Gender;
