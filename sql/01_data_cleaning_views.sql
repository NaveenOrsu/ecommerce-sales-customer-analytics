/*
    E-Commerce Sales & Customer Analytics
    Staging layer - cleaned views built on top of the raw tables.

    Raw data problems handled here:
      - order dates stored in two different formats
      - prices stored as text with a currency symbol
      - negative amounts where they should be positive
      - blank strings instead of NULLs
      - duplicate rows in orders, items and payments
      - invalid customer ages, blank product categories

    Run this file top to bottom - dim_customers depends on fact_orders.
*/

-- ----------------------------------------------------------------------------------------------
-- 1. fact_orders - one row per order
-- ----------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW Fact_orders AS
WITH Cleaned AS(
SELECT 
    order_id,
    customer_id,
    LOWER(TRIM(order_status)) AS order_status,
    CASE 
	WHEN order_purchase_timestamp LIKE '%/%' 
	THEN STR_TO_DATE(order_purchase_timestamp, '%m/%d/%Y %H:%i')
	ELSE CAST(order_purchase_timestamp AS DATE)
    END AS order_purchase_timestamp,
    CAST(order_approved_at AS Date) AS order_approved_at,
    CAST(order_delivered_carrier_date AS Date) AS order_delivered_carrier_date,
    CAST(order_delivered_customer_date AS Date) AS order_delivered_customer_date,
    CAST(order_estimated_delivery_date AS Date) AS order_estimated_delivery_date,
    ROW_NUMBER() OVER(PARTITION BY order_id ) AS rn
FROM
    orders)
SELECT 
order_id, customer_id, order_status, order_purchase_timestamp,
order_approved_at, order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date
FROM  cleaned
WHERE rn = 1;

-- ----------------------------------------------------------------------------------------------
-- 2. fact_order_items - one row per item line, prices cleaned
-- ----------------------------------------------------------------------------------------------
create or replace VIEW fact_order_items AS
With Cleaned AS (select 
order_id, 
order_item_id, 
product_id, 
seller_id, 
CAST(shipping_limit_date As Date) AS shipping_limit_date, 
CAST(ABS(REPLACE(price, '$', '')) AS DECIMAL(10,2)) AS price,
CAST(ABS(nullif(freight_value,'')) as DECIMAL(10,2)) AS freight_value, 
CAST(discount_rate as DECIMAL(10,2))  AS discount_rate 
from order_items
),
Deduplicate AS ( 
select *, 
row_number() over(partition by order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value, discount_rate ) as rn 
from cleaned )
select order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value, discount_rate from deduplicate where rn =1 ;

-- ----------------------------------------------------------------------------------------------
-- 3. dim_Products - blank categories defaulted, duplicates ranked out
-- ----------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_Products AS 
WITH Cleaned AS (
SELECT 
	product_id, 
	COALESCE(NULLIF(lower(TRIM(product_category_name)), ''),'Uncategorized')AS product_category_name, 
	product_name, product_brand, 
	NULLIF(CAST(product_weight_g AS DECIMAL(10,2)), 0) AS product_weight_g, 
	NULLIF(CAST(product_length_cm AS DECIMAL(10,2)), 0) AS product_length_cm, 
	NULLIF(CAST(product_height_cm AS DECIMAL(10,2)), 0) AS product_height_cm, 
	NULLIF(CAST(product_width_cm AS DECIMAL(10,2)), 0) AS product_width_cm, 
	CAST(abs(cost) AS DECIMAL(10,2)) AS cost,
	CAST(price AS DECIMAL(10,2)) AS price,
	ROW_NUMBER() OVER ( PARTITION BY product_id
    ORDER BY CASE WHEN product_category_name IN ('misc','other','general') THEN 1 ELSE 0 END) AS rn
FROM products)
SELECT product_id, product_category_name, product_name, product_brand, product_weight_g, 
product_length_cm, product_height_cm, product_width_cm, cost, price FROM cleaned 
WHERE rn =1 ;

-- ----------------------------------------------------------------------------------------------
-- 4. dim_customers - depends on fact_orders
--    adds first order month and total orders per unique customer
-- ----------------------------------------------------------------------------------------------
Create or replace view dim_customers AS
WITH Cleaned as (
select 
	customer_id, 
	customer_unique_id,
	customer_name,
	customer_gender,
	nullif(CAST(abs(customer_age) AS char),'') AS customer_age,
	customer_zip_code_prefix, 
	Nullif(trim(customer_city),'') AS customer_city, 
	customer_state, 
	Nullif(trim(customer_segment),'') AS customer_segment,
	row_number() over(partition by customer_id) as rn
from customers_messy)
Select 
customer_id, customer_unique_id,
customer_name, customer_gender,
CASE WHEN customer_age BETWEEN 0 AND 100 THEN customer_age ELSE NULL END as customer_age,
customer_zip_code_prefix, 
customer_city, customer_state,
customer_segment,
min(cast(order_purchase_timestamp as Date)) over(partition by c.customer_unique_id) AS FirstOrderMonth,
COUNT(o.order_id) OVER (PARTITION BY c.customer_unique_id) AS total_orders
from cleaned c join fact_orders o using(customer_id)
where rn =1;

-- ----------------------------------------------------------------------------------------------
-- 5. Fact_order_reviews - review dates cast to DATE
-- ----------------------------------------------------------------------------------------------
CReate or Replace  view Fact_order_reviews as
select 
review_id,
order_id, 
review_score, 
review_comment_title,
review_comment_message,
Cast(review_creation_date as Date) as review_creation_date,
Cast(review_answer_timestamp as Date) as review_answer_timestamp
from  order_reviews;

-- ----------------------------------------------------------------------------------------------
-- 6. fact_order_payments - payment types standardised, blanks kept as NULL
-- ----------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW fact_order_payments AS 
WITH cleaned AS(
SELECT 
	order_id, 
	payment_sequential, 
	LOWER(TRIM(BOTH '_' FROM REPLACE(REPLACE(TRIM(payment_type), ' ', '_'), '-', '_'))) AS payment_type, 
	payment_installments,
	CAST(NULLIF(TRIM(payment_value), '') AS DECIMAL(10,2)) AS payment_value -- Negative values as Returns
    -- instead of CAST('' AS ...) silently becoming 0 nullif() to keep the null values as it is
FROM order_payments),
Deduplicate As (
select *,
ROW_NUMBER() OVER(PARTITION BY order_id, payment_sequential, payment_type, payment_installments, payment_value ORDER BY (SELECT NULL)) AS rn 
From cleaned )
SELECT order_id, payment_sequential,payment_type, payment_installments,payment_value 
FROM Deduplicate WHERE rn = 1;
