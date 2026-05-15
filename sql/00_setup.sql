-- =====================================================================
-- Olist E-Commerce Database Setup
-- Creates 9 tables matching the Kaggle Olist Brazilian E-Commerce dataset
-- and loads CSV files into them.
-- =====================================================================

-- Drop existing tables (idempotent: safe to re-run this script)
DROP TABLE IF EXISTS order_reviews CASCADE;
DROP TABLE IF EXISTS order_payments CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS sellers CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS geolocation CASCADE;
DROP TABLE IF EXISTS product_category_translation CASCADE;


-- ---------------------------------------------------------------------
-- customers: one row per unique customer-order pair (yes, weird but real)
-- customer_unique_id is the actual customer identity
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id TEXT PRIMARY KEY,
    customer_unique_id TEXT,
    customer_zip_code_prefix TEXT,
    customer_city TEXT,
    customer_state CHAR(2)
);


-- ---------------------------------------------------------------------
-- orders: one row per order
-- ---------------------------------------------------------------------
CREATE TABLE orders (
    order_id TEXT PRIMARY KEY,
    customer_id TEXT REFERENCES customers(customer_id),
    order_status TEXT,
    order_purchase_timestamp TIMESTAMP,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);


-- ---------------------------------------------------------------------
-- sellers
-- ---------------------------------------------------------------------
CREATE TABLE sellers (
    seller_id TEXT PRIMARY KEY,
    seller_zip_code_prefix TEXT,
    seller_city TEXT,
    seller_state CHAR(2)
);


-- ---------------------------------------------------------------------
-- products
-- ---------------------------------------------------------------------
CREATE TABLE products (
    product_id TEXT PRIMARY KEY,
    product_category_name TEXT,
    product_name_lenght INTEGER,
    product_description_lenght INTEGER,
    product_photos_qty INTEGER,
    product_weight_g INTEGER,
    product_length_cm INTEGER,
    product_height_cm INTEGER,
    product_width_cm INTEGER
);


-- ---------------------------------------------------------------------
-- order_items: one row per item in an order (a single order can have multiple items)
-- ---------------------------------------------------------------------
CREATE TABLE order_items (
    order_id TEXT REFERENCES orders(order_id),
    order_item_id INTEGER,
    product_id TEXT REFERENCES products(product_id),
    seller_id TEXT REFERENCES sellers(seller_id),
    shipping_limit_date TIMESTAMP,
    price NUMERIC(10, 2),
    freight_value NUMERIC(10, 2),
    PRIMARY KEY (order_id, order_item_id)
);


-- ---------------------------------------------------------------------
-- order_payments: an order can have multiple payment methods (split payments)
-- ---------------------------------------------------------------------
CREATE TABLE order_payments (
    order_id TEXT REFERENCES orders(order_id),
    payment_sequential INTEGER,
    payment_type TEXT,
    payment_installments INTEGER,
    payment_value NUMERIC(10, 2),
    PRIMARY KEY (order_id, payment_sequential)
);


-- ---------------------------------------------------------------------
-- order_reviews: one review per order (1-5 stars)
-- ---------------------------------------------------------------------
CREATE TABLE order_reviews (
    review_id TEXT,
    order_id TEXT REFERENCES orders(order_id),
    review_score INTEGER,
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);


-- ---------------------------------------------------------------------
-- geolocation: zip code → lat/long lookup
-- ---------------------------------------------------------------------
CREATE TABLE geolocation (
    geolocation_zip_code_prefix TEXT,
    geolocation_lat NUMERIC(10, 7),
    geolocation_lng NUMERIC(10, 7),
    geolocation_city TEXT,
    geolocation_state CHAR(2)
);


-- ---------------------------------------------------------------------
-- product_category_translation: Portuguese → English category names
-- ---------------------------------------------------------------------
CREATE TABLE product_category_translation (
    product_category_name TEXT PRIMARY KEY,
    product_category_name_english TEXT
);


-- =====================================================================
-- Load data from CSVs

-- =====================================================================



\copy customers FROM '/Users/mubinamirzaeva/Desktop/ecommerce-customer-analytics/data/raw/olist_customers_dataset.csv' DELIMITER ',' CSV HEADER;
\copy sellers FROM '/Users/mubinamirzaeva/Desktop/ecommerce-customer-analytics/data/raw/olist_sellers_dataset.csv' DELIMITER ',' CSV HEADER;
\copy products FROM '/Users/mubinamirzaeva/Desktop/ecommerce-customer-analytics/data/raw/olist_products_dataset.csv' DELIMITER ',' CSV HEADER;
\copy orders FROM '/Users/mubinamirzaeva/Desktop/ecommerce-customer-analytics/data/raw/olist_orders_dataset.csv' DELIMITER ',' CSV HEADER;
\copy order_items FROM '/Users/mubinamirzaeva/Desktop/ecommerce-customer-analytics/data/raw/olist_order_items_dataset.csv' DELIMITER ',' CSV HEADER;
\copy order_payments FROM '/Users/mubinamirzaeva/Desktop/ecommerce-customer-analytics/data/raw/olist_order_payments_dataset.csv' DELIMITER ',' CSV HEADER;
\copy order_reviews FROM '/Users/mubinamirzaeva/Desktop/ecommerce-customer-analytics/data/raw/olist_order_reviews_dataset.csv' DELIMITER ',' CSV HEADER;
\copy geolocation FROM '/Users/mubinamirzaeva/Desktop/ecommerce-customer-analytics/data/raw/olist_geolocation_dataset.csv' DELIMITER ',' CSV HEADER;
\copy product_category_translation FROM '/Users/mubinamirzaeva/Desktop/ecommerce-customer-analytics/data/raw/product_category_name_translation.csv' DELIMITER ',' CSV HEADER;


-- =====================================================================
-- Verify the load worked
-- =====================================================================
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation
UNION ALL SELECT 'category_translation', COUNT(*) FROM product_category_translation
ORDER BY row_count DESC;