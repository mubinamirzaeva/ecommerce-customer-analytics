-- =====================================================================
-- Satisfaction and Operations Analysis
-- =====================================================================
-- Goal: Diagnose the drivers of customer satisfaction and identify
-- operational levers that could improve the first-purchase experience.
--
-- Strategic context: prior analyses established that Olist is a
-- structurally single-purchase business with near-zero retention. This
-- section investigates whether the first-purchase experience itself is
-- responsible, and identifies specific operational levers.
--
-- The analyses below cover review score distribution, delivery
-- performance, the relationship between delivery and reviews, seller
-- quality dispersion, and category-level satisfaction patterns.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Query 4.1: Review score distribution and aggregate operational metrics
-- ---------------------------------------------------------------------
-- Establishes the baseline. Before diagnosing what drives reviews,
-- we need to understand the distribution we are working with.

SELECT
    review_score,
    COUNT(*) AS review_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_reviews
FROM order_reviews r
JOIN orders o ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY review_score
ORDER BY review_score DESC;

-- ---------------------------------------------------------------------
-- Query 4.2: Delivery performance metrics by review score
-- ---------------------------------------------------------------------
-- Two distinct delivery dimensions:
--   delivery_days: actual time from purchase to delivery (raw speed)
--   delivery_vs_estimate: actual delivery date minus estimated date
--                         (negative = delivered early; positive = late)
--
-- Both are computed and analyzed separately, because they capture
-- different aspects of the customer experience.

SELECT
    r.review_score,
    COUNT(*) AS orders,
    ROUND(AVG(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp))/86400)::NUMERIC, 1)
        AS avg_delivery_days,
    ROUND(AVG(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_estimated_delivery_date))/86400)::NUMERIC, 1)
        AS avg_days_vs_estimate,
    ROUND(100.0 * COUNT(*) FILTER (WHERE o.order_delivered_customer_date > o.order_estimated_delivery_date) / COUNT(*), 1)
        AS pct_delivered_late
FROM order_reviews r
JOIN orders o ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY r.review_score
ORDER BY r.review_score DESC;

-- ---------------------------------------------------------------------
-- Query 4.3: Isolating the effect of estimate accuracy from delivery speed
-- ---------------------------------------------------------------------
-- This query controls for delivery speed by bucketing orders into
-- similar delivery-time bands, then examines whether estimate accuracy
-- has an independent effect on review scores within each band.
--
-- If estimate accuracy matters independently of speed, we expect to see
-- review scores vary systematically with the days-vs-estimate column
-- WITHIN each delivery-time band.

WITH delivery_data AS (
    SELECT
        r.review_score,
        EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp))/86400 AS delivery_days,
        EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_estimated_delivery_date))/86400 AS days_vs_estimate
    FROM order_reviews r
    JOIN orders o ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    CASE
        WHEN delivery_days < 7 THEN '1. Under 7 days'
        WHEN delivery_days < 14 THEN '2. 7-13 days'
        WHEN delivery_days < 21 THEN '3. 14-20 days'
        WHEN delivery_days < 30 THEN '4. 21-29 days'
        ELSE '5. 30+ days'
    END AS delivery_speed_band,
    CASE
        WHEN days_vs_estimate <= -7 THEN 'A. Early by 7+ days'
        WHEN days_vs_estimate <= -3 THEN 'B. Early by 3-6 days'
        WHEN days_vs_estimate <= 0 THEN 'C. On time or 1-2 early'
        WHEN days_vs_estimate <= 3 THEN 'D. Late by 1-3 days'
        ELSE 'E. Late by 4+ days'
    END AS estimate_accuracy_band,
    COUNT(*) AS orders,
    ROUND(AVG(review_score)::NUMERIC, 2) AS avg_review_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 1) AS pct_negative_reviews
FROM delivery_data
GROUP BY delivery_speed_band, estimate_accuracy_band
HAVING COUNT(*) >= 100
ORDER BY delivery_speed_band, estimate_accuracy_band;


-- ---------------------------------------------------------------------
-- Query 4.4: Seller quality dispersion
-- ---------------------------------------------------------------------
-- Identifies sellers with high order volume and consistently low
-- review scores. These are the sellers whose poor performance has the
-- largest impact on platform reputation and where intervention would
-- have the largest effect.
--
-- Filter to sellers with at least 50 reviews to ensure statistical
-- meaningfulness; a seller with 3 bad reviews tells us nothing.

WITH seller_performance AS (
    SELECT
        oi.seller_id,
        COUNT(DISTINCT oi.order_id) AS total_orders,
        COUNT(DISTINCT r.review_id) AS total_reviews,
        ROUND(AVG(r.review_score)::NUMERIC, 2) AS avg_review_score,
        ROUND(100.0 * COUNT(*) FILTER (WHERE r.review_score <= 2) / COUNT(*), 1) AS pct_negative_reviews,
        s.seller_state
    FROM order_items oi
    JOIN order_reviews r ON oi.order_id = r.order_id
    JOIN orders o ON oi.order_id = o.order_id
    JOIN sellers s ON oi.seller_id = s.seller_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id, s.seller_state
)
SELECT
    seller_id,
    seller_state,
    total_orders,
    total_reviews,
    avg_review_score,
    pct_negative_reviews
FROM seller_performance
WHERE total_reviews >= 50
ORDER BY pct_negative_reviews DESC, total_orders DESC
LIMIT 25;


-- ---------------------------------------------------------------------
-- Query 4.5: Seller quality distribution and revenue concentration
-- ---------------------------------------------------------------------
-- Buckets sellers by average review score and reports what share of
-- orders and revenue flows through each tier. Reveals whether the
-- marketplace has a small underperforming long tail or a more diffuse
-- quality problem.

WITH seller_metrics AS (
    SELECT
        oi.seller_id,
        COUNT(DISTINCT oi.order_id) AS orders,
        SUM(oi.price + oi.freight_value) AS gross_revenue,
        AVG(r.review_score) AS avg_score
    FROM order_items oi
    JOIN order_reviews r ON oi.order_id = r.order_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id
    HAVING COUNT(DISTINCT oi.order_id) >= 10
)
SELECT
    CASE
        WHEN avg_score >= 4.5 THEN '1. Excellent (4.5+)'
        WHEN avg_score >= 4.0 THEN '2. Good (4.0-4.49)'
        WHEN avg_score >= 3.5 THEN '3. Adequate (3.5-3.99)'
        WHEN avg_score >= 3.0 THEN '4. Poor (3.0-3.49)'
        ELSE '5. Very Poor (<3.0)'
    END AS quality_tier,
    COUNT(*) AS seller_count,
    SUM(orders) AS total_orders,
    ROUND(100.0 * SUM(orders) / SUM(SUM(orders)) OVER (), 1) AS pct_orders,
    ROUND(SUM(gross_revenue)::NUMERIC, 0) AS total_revenue,
    ROUND(100.0 * SUM(gross_revenue) / SUM(SUM(gross_revenue)) OVER (), 1) AS pct_revenue
FROM seller_metrics
GROUP BY quality_tier
ORDER BY quality_tier;


-- ---------------------------------------------------------------------
-- Query 4.6: Review scores by product category
-- ---------------------------------------------------------------------
-- Identifies which product categories have systemically lower
-- satisfaction. Joins through the category translation table for
-- readable English names.

SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
    COUNT(DISTINCT oi.order_id) AS orders,
    ROUND(AVG(r.review_score)::NUMERIC, 2) AS avg_review_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE r.review_score <= 2) / COUNT(*), 1) AS pct_negative_reviews
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN order_reviews r ON oi.order_id = r.order_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN product_category_translation t ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY category
HAVING COUNT(DISTINCT oi.order_id) >= 200
ORDER BY pct_negative_reviews DESC
LIMIT 20;