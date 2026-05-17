-- =====================================================================
-- Cohort Retention Analysis
-- =====================================================================
-- Goal: Measure how customer retention changes over time, by acquisition cohort.
--
-- Method: Group customers by their FIRST purchase month (their "cohort"),
-- then measure what % of each cohort returned to buy in each subsequent month.
--
-- The output is a retention matrix: rows = cohorts, columns = month index,
-- values = % of cohort that purchased in that month.
--
-- This is THE classic SaaS/retail retention analysis. Every analyst is
-- expected to be able to build this.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Query 3.1: Establish customer cohorts (their first-order month)
-- ---------------------------------------------------------------------
-- For each unique customer, find the month of their FIRST delivered order.
-- That month becomes their permanent cohort label.

WITH first_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', MIN(o.order_purchase_timestamp))::DATE AS cohort_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    cohort_month,
    COUNT(*) AS new_customers_in_cohort
FROM first_orders
GROUP BY cohort_month
ORDER BY cohort_month;

-- ---------------------------------------------------------------------
-- Query 3.2: Customer activity by cohort × month
-- ---------------------------------------------------------------------
-- For every (customer, order) combination, figure out:
--   1. Which cohort that customer belongs to (their first-order month)
--   2. How many months AFTER their first order this order was placed
--
-- This is the building block. We'll aggregate it in the next query.

WITH first_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', MIN(o.order_purchase_timestamp))::DATE AS cohort_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
customer_activity AS (
    -- Every customer + every order they placed, with cohort info attached
    SELECT
        fo.customer_unique_id,
        fo.cohort_month,
        DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS order_month,
        -- "Months since cohort start" — index 0, 1, 2, 3...
        -- This is the magic calculation: integer months between two dates
        (EXTRACT(YEAR FROM o.order_purchase_timestamp)::INT - EXTRACT(YEAR FROM fo.cohort_month)::INT) * 12
        + (EXTRACT(MONTH FROM o.order_purchase_timestamp)::INT - EXTRACT(MONTH FROM fo.cohort_month)::INT)
        AS month_index
    FROM first_orders fo
    JOIN customers c ON fo.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
)
-- Quick check: peek at a few rows
SELECT *
FROM customer_activity
WHERE cohort_month = '2017-01-01'
ORDER BY customer_unique_id, month_index
LIMIT 20;

-- ---------------------------------------------------------------------
-- Query 3.3: The retention matrix — cohorts × months since first purchase
-- ---------------------------------------------------------------------
-- For each cohort × month_index combination, count distinct active customers,
-- then divide by the cohort size to get retention %.

WITH first_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', MIN(o.order_purchase_timestamp))::DATE AS cohort_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
customer_activity AS (
    SELECT
        fo.customer_unique_id,
        fo.cohort_month,
        (EXTRACT(YEAR FROM o.order_purchase_timestamp)::INT - EXTRACT(YEAR FROM fo.cohort_month)::INT) * 12
        + (EXTRACT(MONTH FROM o.order_purchase_timestamp)::INT - EXTRACT(MONTH FROM fo.cohort_month)::INT)
        AS month_index
    FROM first_orders fo
    JOIN customers c ON fo.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),
cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_unique_id) AS cohort_size
    FROM first_orders
    GROUP BY cohort_month
),
cohort_activity AS (
    SELECT
        cohort_month,
        month_index,
        COUNT(DISTINCT customer_unique_id) AS active_customers
    FROM customer_activity
    GROUP BY cohort_month, month_index
)
SELECT
    ca.cohort_month,
    cs.cohort_size,
    ca.month_index,
    ca.active_customers,
    ROUND(100.0 * ca.active_customers / cs.cohort_size, 2) AS retention_pct
FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
WHERE ca.cohort_month >= '2017-01-01'  -- skip the very small 2016 cohorts
  AND ca.month_index <= 6              -- focus on first 6 months of life
ORDER BY ca.cohort_month, ca.month_index;

-- ---------------------------------------------------------------------
-- Query 3.4: Pivoted retention matrix (one row per cohort, one column per month)
-- ---------------------------------------------------------------------
-- Reshape the long format from Query 3.3 into the classic retention matrix
-- where each cohort gets its own row and the months are columns.
-- Tableau can do this pivot too, but having both versions is useful.

WITH first_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', MIN(o.order_purchase_timestamp))::DATE AS cohort_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
customer_activity AS (
    SELECT
        fo.customer_unique_id,
        fo.cohort_month,
        (EXTRACT(YEAR FROM o.order_purchase_timestamp)::INT - EXTRACT(YEAR FROM fo.cohort_month)::INT) * 12
        + (EXTRACT(MONTH FROM o.order_purchase_timestamp)::INT - EXTRACT(MONTH FROM fo.cohort_month)::INT)
        AS month_index
    FROM first_orders fo
    JOIN customers c ON fo.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_unique_id) AS cohort_size
    FROM first_orders GROUP BY cohort_month
)
SELECT
    ca.cohort_month,
    cs.cohort_size,
    -- Pivot: each month_index becomes a column using FILTER (a clean PostgreSQL pattern)
    ROUND(100.0 * COUNT(DISTINCT ca.customer_unique_id) FILTER (WHERE ca.month_index = 1) / cs.cohort_size, 2) AS month_1_pct,
    ROUND(100.0 * COUNT(DISTINCT ca.customer_unique_id) FILTER (WHERE ca.month_index = 2) / cs.cohort_size, 2) AS month_2_pct,
    ROUND(100.0 * COUNT(DISTINCT ca.customer_unique_id) FILTER (WHERE ca.month_index = 3) / cs.cohort_size, 2) AS month_3_pct,
    ROUND(100.0 * COUNT(DISTINCT ca.customer_unique_id) FILTER (WHERE ca.month_index = 4) / cs.cohort_size, 2) AS month_4_pct,
    ROUND(100.0 * COUNT(DISTINCT ca.customer_unique_id) FILTER (WHERE ca.month_index = 5) / cs.cohort_size, 2) AS month_5_pct,
    ROUND(100.0 * COUNT(DISTINCT ca.customer_unique_id) FILTER (WHERE ca.month_index = 6) / cs.cohort_size, 2) AS month_6_pct
FROM customer_activity ca
JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
WHERE ca.cohort_month >= '2017-01-01'
GROUP BY ca.cohort_month, cs.cohort_size
ORDER BY ca.cohort_month;