-- =====================================================================
-- Data Quality Checks
-- Before analyzing data, you have to trust it. These queries verify:
--   1. We have the date coverage we expect
--   2. There are no duplicate primary keys
--   3. Critical columns aren't full of NULLs
--   4. Foreign key relationships are intact
-- Every analyst project should start here.
-- =====================================================================


-- Q1.1: What date range does the data cover?
-- Expecting: roughly Sep 2016 to Oct 2018
SELECT
    MIN(order_purchase_timestamp) AS earliest_order,
    MAX(order_purchase_timestamp) AS latest_order,
    COUNT(*) AS total_orders,
    COUNT(DISTINCT customer_id) AS unique_customers
FROM orders;


-- Q1.2: How many orders by status?
-- Why this matters: we'll likely filter to "delivered" only for revenue analysis
SELECT
    order_status,
    COUNT(*) AS order_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM orders
GROUP BY order_status
ORDER BY order_count DESC;


-- Q1.3: Null check on critical fields
-- Why this matters: we need to know what to handle. NULL delivered dates are common
-- because cancelled orders never deliver.
SELECT
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS null_purchase_time,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS null_delivered_date,
    SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS null_estimated_delivery
FROM orders;


-- Q1.4: Verify no duplicate primary keys
-- Why this matters: trust no one, verify everything. PRIMARY KEY constraint
-- should prevent duplicates but this confirms the load was clean.
SELECT order_id, COUNT(*) AS dup_count
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1;
-- Expected: 0 rows returned


-- Q1.5: Do all orders have at least one item?
-- This catches join surprises before they bite us.
SELECT COUNT(*) AS orders_without_items
FROM orders o
LEFT JOIN order_items oi ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL;
-- A small number is expected (cancelled orders that never got items) 