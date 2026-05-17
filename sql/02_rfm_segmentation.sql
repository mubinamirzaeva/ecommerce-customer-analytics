-- =====================================================================
-- RFM Customer Segmentation
-- =====================================================================
-- Goal: Segment customers by behavior to enable targeted retention and
-- growth strategies.
--
-- Method: For each customer, calculate three metrics:
--   R (Recency)  - days since last purchase (lower = better)
--   F (Frequency) - count of orders placed (higher = better)
--   M (Monetary) - total $ spent (higher = better)
--
-- Then score each customer 1-5 on each dimension using NTILE(),
-- and assign them to a behavioral segment based on the combination.
--
-- Note on data: Olist has TWO customer identifiers:
--   customer_id        = one row per customer-order pair (essentially per order)
--   customer_unique_id = the actual person across all their orders
-- We must use customer_unique_id for RFM. Otherwise every order looks
-- like a different customer and Frequency is always 1.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Query 2.1: Define the analysis date and confirm the dataset window
-- ---------------------------------------------------------------------
-- For Recency, we measure "days since last purchase as of when?"
-- We use the latest date in the dataset as our reference point.
-- In a real business this would be CURRENT_DATE — but our data is
-- historical (ends Oct 2018), so we anchor to the dataset's max date.

SELECT
    MAX(order_purchase_timestamp)::DATE AS analysis_anchor_date,
    COUNT(*) AS total_delivered_orders
FROM orders
WHERE order_status = 'delivered';

-- ---------------------------------------------------------------------
-- Query 2.2: Calculate raw RFM metrics for each unique customer
-- ---------------------------------------------------------------------
-- Building blocks:
--   - JOIN orders to customers (to get customer_unique_id)
--   - JOIN order_items to get revenue per order
--   - Filter to delivered orders only (cancelled orders aren't real revenue)
--
-- We use a CTE (Common Table Expression) — the WITH clause — to make
-- this readable. CTEs are like temporary named result sets.

WITH order_revenue AS (
    -- First, calculate the total revenue per order
    -- (an order can have multiple items, so we SUM)
    SELECT
        oi.order_id,
        SUM(oi.price + oi.freight_value) AS order_total
    FROM order_items oi
    GROUP BY oi.order_id
),
customer_orders AS (
    -- Now join orders + customers + revenue, filtered to delivered
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp::DATE AS order_date,
        orev.order_total
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN order_revenue orev ON o.order_id = orev.order_id
    WHERE o.order_status = 'delivered'
)
SELECT
    customer_unique_id,
    -- Recency: days from this customer's last order to dataset's max date
    ('2018-10-17'::DATE - MAX(order_date)) AS recency_days,
    -- Frequency: how many orders this customer placed
    COUNT(DISTINCT order_id) AS frequency,
    -- Monetary: total dollars spent across all their orders
    ROUND(SUM(order_total)::NUMERIC, 2) AS monetary
FROM customer_orders
GROUP BY customer_unique_id
ORDER BY monetary DESC
LIMIT 20;

-- ---------------------------------------------------------------------
-- Query 2.3: Full RFM scoring + segmentation
-- ---------------------------------------------------------------------
-- This builds on Query 2.2 but:
--   1. Calculates RFM for every customer (not just top 20)
--   2. Scores each customer 1-5 using NTILE()
--   3. Combines scores into a single RFM segment label
--
-- NTILE(5) is a window function that splits the ordered data into 5
-- equal buckets. For Monetary: bucket 5 = top 20% of spenders.
-- For Recency: bucket 5 = MOST recent (so we ORDER BY recency_days ASC).

WITH order_revenue AS (
    SELECT
        oi.order_id,
        SUM(oi.price + oi.freight_value) AS order_total
    FROM order_items oi
    GROUP BY oi.order_id
),
customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp::DATE AS order_date,
        orev.order_total
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN order_revenue orev ON o.order_id = orev.order_id
    WHERE o.order_status = 'delivered'
),
rfm_raw AS (
    SELECT
        customer_unique_id,
        ('2018-10-17'::DATE - MAX(order_date)) AS recency_days,
        COUNT(DISTINCT order_id) AS frequency,
        ROUND(SUM(order_total)::NUMERIC, 2) AS monetary
    FROM customer_orders
    GROUP BY customer_unique_id
),
rfm_scored AS (
    -- NTILE(5) divides customers into 5 equal-sized buckets
    -- Lower recency_days = more recent = better → ORDER BY ASC, so bucket 5 = most recent
    -- Higher frequency = better → ORDER BY DESC, so bucket 5 = highest frequency
    -- Higher monetary = better → ORDER BY DESC, so bucket 5 = highest spenders
    SELECT
        customer_unique_id,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days ASC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency DESC, monetary DESC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary DESC) AS m_score
    FROM rfm_raw
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    -- Combine R, F, M into a behavioral segment
    -- This is a simplified version of the standard RFM segmentation matrix
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 4 THEN 'Loyal'
        WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Potential Loyalists'
        WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4 THEN 'At Risk'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'Need Attention'
        WHEN r_score <= 2 AND m_score >= 3 THEN 'Cannot Lose Them'
        WHEN r_score <= 1 THEN 'Hibernating'
        ELSE 'Others'
    END AS segment
FROM rfm_scored
ORDER BY monetary DESC
LIMIT 25;


-- ---------------------------------------------------------------------
-- Query 2.4: Segment summary — who has what value?
-- ---------------------------------------------------------------------
-- This is the executive-summary view: for each segment, how many customers,
-- how much revenue, what % of total revenue. This goes straight onto a
-- dashboard.

WITH order_revenue AS (
    SELECT oi.order_id, SUM(oi.price + oi.freight_value) AS order_total
    FROM order_items oi GROUP BY oi.order_id
),
customer_orders AS (
    SELECT
        c.customer_unique_id, o.order_id,
        o.order_purchase_timestamp::DATE AS order_date,
        orev.order_total
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN order_revenue orev ON o.order_id = orev.order_id
    WHERE o.order_status = 'delivered'
),
rfm_raw AS (
    SELECT
        customer_unique_id,
        ('2018-10-17'::DATE - MAX(order_date)) AS recency_days,
        COUNT(DISTINCT order_id) AS frequency,
        ROUND(SUM(order_total)::NUMERIC, 2) AS monetary
    FROM customer_orders
    GROUP BY customer_unique_id
),
rfm_scored AS (
    SELECT
        customer_unique_id, recency_days, frequency, monetary,
        NTILE(5) OVER (ORDER BY recency_days ASC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency DESC, monetary DESC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary DESC) AS m_score
    FROM rfm_raw
),
segmented AS (
    SELECT *,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 4 THEN 'Loyal'
            WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
            WHEN r_score >= 3 AND f_score >= 3 THEN 'Potential Loyalists'
            WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4 THEN 'At Risk'
            WHEN r_score <= 2 AND f_score >= 3 THEN 'Need Attention'
            WHEN r_score <= 2 AND m_score >= 3 THEN 'Cannot Lose Them'
            WHEN r_score <= 1 THEN 'Hibernating'
            ELSE 'Others'
        END AS segment
    FROM rfm_scored
)
SELECT
    segment,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_customers,
    ROUND(SUM(monetary)::NUMERIC, 2) AS total_revenue,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 2) AS pct_revenue,
    ROUND(AVG(monetary)::NUMERIC, 2) AS avg_customer_value,
    ROUND(AVG(frequency)::NUMERIC, 2) AS avg_orders,
    ROUND(AVG(recency_days)::NUMERIC, 0) AS avg_recency_days
FROM segmented
GROUP BY segment
ORDER BY total_revenue DESC;


-- ---------------------------------------------------------------------
-- Query 2.5: Reality check — what's the repeat purchase rate?
-- ---------------------------------------------------------------------
-- Before trusting the RFM segmentation, we need to understand the
-- underlying purchase behavior. RFM assumes meaningful variation in
-- Frequency. If 97% of customers only buy once, the F dimension is
-- nearly useless and "Champions" becomes a meaningless label.

WITH order_revenue AS (
    SELECT oi.order_id, SUM(oi.price + oi.freight_value) AS order_total
    FROM order_items oi GROUP BY oi.order_id
),
customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        orev.order_total
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN order_revenue orev ON o.order_id = orev.order_id
    WHERE o.order_status = 'delivered'
),
customer_frequency AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS order_count
    FROM customer_orders
    GROUP BY customer_unique_id
)
SELECT
    CASE
        WHEN order_count = 1 THEN '1 order (one-time)'
        WHEN order_count = 2 THEN '2 orders'
        WHEN order_count = 3 THEN '3 orders'
        WHEN order_count BETWEEN 4 AND 5 THEN '4-5 orders'
        ELSE '6+ orders'
    END AS purchase_pattern,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_customers
FROM customer_frequency
GROUP BY purchase_pattern
ORDER BY MIN(order_count);

-- ---------------------------------------------------------------------
-- Query 2.6: Revised RFM segmentation accounting for low repeat rate
-- ---------------------------------------------------------------------
-- Given the data reality (~97% one-time buyers), we use a two-tier approach:
--   Tier 1: One-time buyers (the vast majority) — segment by Recency + Monetary
--   Tier 2: Repeat buyers (small but valuable) — full RFM
-- This is more honest than forcing all customers through standard RFM.

WITH order_revenue AS (
    SELECT oi.order_id, SUM(oi.price + oi.freight_value) AS order_total
    FROM order_items oi GROUP BY oi.order_id
),
customer_orders AS (
    SELECT
        c.customer_unique_id, o.order_id,
        o.order_purchase_timestamp::DATE AS order_date,
        orev.order_total
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN order_revenue orev ON o.order_id = orev.order_id
    WHERE o.order_status = 'delivered'
),
rfm_raw AS (
    SELECT
        customer_unique_id,
        ('2018-10-17'::DATE - MAX(order_date)) AS recency_days,
        COUNT(DISTINCT order_id) AS frequency,
        ROUND(SUM(order_total)::NUMERIC, 2) AS monetary
    FROM customer_orders
    GROUP BY customer_unique_id
),
rfm_scored AS (
    SELECT
        customer_unique_id, recency_days, frequency, monetary,
        NTILE(5) OVER (ORDER BY recency_days ASC) AS r_score,
        NTILE(5) OVER (ORDER BY monetary DESC) AS m_score
    FROM rfm_raw
)
SELECT
    CASE
        -- TIER 2: Repeat buyers (the rare and valuable ones)
        WHEN frequency >= 4 THEN 'VIP Repeat (4+ orders)'
        WHEN frequency = 3 THEN 'Loyal Repeat (3 orders)'
        WHEN frequency = 2 AND r_score >= 3 THEN 'Active Repeat (2 orders, recent)'
        WHEN frequency = 2 THEN 'Lapsed Repeat (2 orders, dormant)'
        -- TIER 1: One-time buyers — segment by Recency + Monetary
        WHEN frequency = 1 AND r_score >= 4 AND m_score >= 4 THEN 'New High-Value'
        WHEN frequency = 1 AND r_score >= 4 THEN 'New Customer'
        WHEN frequency = 1 AND r_score <= 2 AND m_score >= 4 THEN 'Lost High-Value'
        WHEN frequency = 1 AND r_score <= 2 THEN 'Lost / Hibernating'
        ELSE 'One-Time Mid-Tier'
    END AS segment,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_customers,
    ROUND(SUM(monetary)::NUMERIC, 2) AS total_revenue,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 2) AS pct_revenue,
    ROUND(AVG(monetary)::NUMERIC, 2) AS avg_customer_value,
    ROUND(AVG(frequency)::NUMERIC, 2) AS avg_orders,
    ROUND(AVG(recency_days)::NUMERIC, 0) AS avg_recency_days
FROM rfm_scored
GROUP BY segment
ORDER BY total_revenue DESC;