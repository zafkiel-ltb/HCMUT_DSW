SET NOCOUNT ON;
USE CompanyX;

PRINT '=== CHURN by orders BEFORE cutoff (no leakage) ===';
WITH pre AS (SELECT CustomerID, COUNT(*) AS n_pre, MIN(OrderDate) AS first_dt FROM Sales.SalesOrderHeader WHERE OrderDate<='2013-06-30' GROUP BY CustomerID),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>'2013-06-30')
SELECT CASE WHEN n_pre=1 THEN '1' WHEN n_pre=2 THEN '2' WHEN n_pre<=5 THEN '3-5' ELSE '6+' END AS bucket,
 SUM(CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM pre LEFT JOIN post ON post.CustomerID=pre.CustomerID
GROUP BY CASE WHEN n_pre=1 THEN '1' WHEN n_pre=2 THEN '2' WHEN n_pre<=5 THEN '3-5' ELSE '6+' END ORDER BY bucket;

PRINT '=== same, individuals only ===';
WITH pre AS (SELECT h.CustomerID, COUNT(*) AS n_pre FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID WHERE OrderDate<='2013-06-30' AND c.StoreID IS NULL GROUP BY h.CustomerID),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>'2013-06-30')
SELECT CASE WHEN n_pre=1 THEN '1' WHEN n_pre=2 THEN '2' ELSE '3+' END AS bucket,
 SUM(CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM pre LEFT JOIN post ON post.CustomerID=pre.CustomerID
GROUP BY CASE WHEN n_pre=1 THEN '1' WHEN n_pre=2 THEN '2' ELSE '3+' END ORDER BY bucket;

PRINT '=== same, stores only ===';
WITH pre AS (SELECT h.CustomerID, COUNT(*) AS n_pre FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID WHERE OrderDate<='2013-06-30' AND c.StoreID IS NOT NULL GROUP BY h.CustomerID),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>'2013-06-30')
SELECT CASE WHEN n_pre<=2 THEN '1-2' WHEN n_pre<=5 THEN '3-5' ELSE '6+' END AS bucket,
 SUM(CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM pre LEFT JOIN post ON post.CustomerID=pre.CustomerID
GROUP BY CASE WHEN n_pre<=2 THEN '1-2' WHEN n_pre<=5 THEN '3-5' ELSE '6+' END ORDER BY bucket;

PRINT '=== CHURN by category bought BEFORE cutoff (individuals) ===';
WITH pre AS (SELECT DISTINCT h.CustomerID FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID WHERE OrderDate<='2013-06-30' AND c.StoreID IS NULL),
post AS (SELECT DISTINCT CustomerID FROM Sales.SalesOrderHeader WHERE OrderDate>'2013-06-30'),
cat AS (SELECT h.CustomerID, MAX(CASE WHEN pc.Name='Accessories' OR pc.Name='Clothing' THEN 1 ELSE 0 END) AS has_acc FROM Sales.SalesOrderDetail d JOIN Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID JOIN Production.Product p ON p.ProductID=d.ProductID JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID=p.ProductSubcategoryID JOIN Production.ProductCategory pc ON pc.ProductCategoryID=ps.ProductCategoryID WHERE h.OrderDate<='2013-06-30' GROUP BY h.CustomerID)
SELECT cat.has_acc, SUM(CASE WHEN post.CustomerID IS NULL THEN 1 ELSE 0 END) AS churn, COUNT(*) AS total
FROM pre JOIN cat ON cat.CustomerID=pre.CustomerID LEFT JOIN post ON post.CustomerID=pre.CustomerID GROUP BY cat.has_acc;

PRINT '=== Revenue reconciliation ===';
SELECT CAST(SUM(SubTotal) AS decimal(18,0)) AS subtotal, CAST(SUM(TaxAmt) AS decimal(18,0)) AS tax, CAST(SUM(Freight) AS decimal(18,0)) AS freight, CAST(SUM(TotalDue) AS decimal(18,0)) AS totaldue FROM Sales.SalesOrderHeader;
SELECT CAST(SUM(LineTotal) AS decimal(18,0)) AS sum_linetotal FROM Sales.SalesOrderDetail;
SELECT CAST(SUM(d.LineTotal) AS decimal(18,0)) AS linetotal_with_category FROM Sales.SalesOrderDetail d JOIN Production.Product p ON p.ProductID=d.ProductID WHERE p.ProductSubcategoryID IS NOT NULL;

PRINT '=== Revenue per customer by type ===';
SELECT CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END AS ctype, COUNT(DISTINCT h.CustomerID) AS customers, CAST(SUM(h.TotalDue)/COUNT(DISTINCT h.CustomerID) AS decimal(18,0)) AS revenue_per_customer
FROM Sales.SalesOrderHeader h JOIN Sales.Customer c ON c.CustomerID=h.CustomerID GROUP BY CASE WHEN c.StoreID IS NULL THEN 'Individual' ELSE 'Store' END;

PRINT '=== Effect of excluding cancelled + negative orders on churn label ===';
WITH agg AS (SELECT CustomerID, MIN(OrderDate) AS first_dt, MAX(OrderDate) AS last_dt FROM Sales.SalesOrderHeader WHERE Status=5 AND TotalDue>=0 GROUP BY CustomerID)
SELECT CASE WHEN last_dt<='2013-06-30' THEN 'Churn' ELSE 'Active' END AS label, COUNT(*) AS customers FROM agg WHERE first_dt<='2013-06-30' GROUP BY CASE WHEN last_dt<='2013-06-30' THEN 'Churn' ELSE 'Active' END;

PRINT '=== Among churned (label), how many had a gap > 365 days earlier in their own history (evidence of late returns) ===';
WITH o AS (SELECT CustomerID, OrderDate, LAG(OrderDate) OVER (PARTITION BY CustomerID ORDER BY OrderDate, SalesOrderID) AS prev FROM Sales.SalesOrderHeader)
SELECT COUNT(DISTINCT CustomerID) AS customers_returned_after_365 FROM o WHERE prev IS NOT NULL AND DATEDIFF(day,prev,OrderDate)>365;
SELECT COUNT(DISTINCT CustomerID) AS customers_with_2plus FROM (SELECT CustomerID FROM Sales.SalesOrderHeader GROUP BY CustomerID HAVING COUNT(*)>=2) x;
