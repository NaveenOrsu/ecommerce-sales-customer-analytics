/*
    E-Commerce Sales & Customer Analytics
    RFM scoring and customer segmentation.

    Scoring:
      Recency   - days since the last order, measured from 31-Jan-2026, scored with NTILE(3)
                  R3 = most recent third, R1 = least recent third
      Frequency - 2 = repeat buyer (2+ orders), 1 = one-time buyer
      Monetary  - NTILE(3) on total product spend

    Each customer is also tagged with the category they last bought from,
    grouped into Durable / Repeatable / Other.

    Depends on: fact_orders, fact_order_items, dim_customers, dim_Products
*/

CREATE OR REPLACE VIEW rfm_segment AS

WITH x AS (
    SELECT
        c.customer_unique_id AS customer_unique_id,

        -- First and latest purchase dates
        MIN(CAST(o.order_purchase_timestamp AS DATE)) AS first_purchase_date,
        MAX(CAST(o.order_purchase_timestamp AS DATE)) AS last_purchase_date,

        -- Number of distinct orders
        COUNT(DISTINCT oi.order_id) AS Frequency,

        -- Total product spend
        SUM(oi.price) AS Monetary

    FROM fact_order_items oi

    JOIN fact_orders o
        ON o.order_id = oi.order_id

    JOIN dim_customers c
        ON c.customer_id = o.customer_id

    GROUP BY
        c.customer_unique_id
),

cat AS (
    SELECT
        c.customer_unique_id,
        p.product_category_name,

        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY
                o.order_purchase_timestamp DESC,
                oi.price DESC,
                p.product_category_name
        ) AS rn

    FROM fact_order_items oi

    JOIN fact_orders o
        ON o.order_id = oi.order_id

    JOIN dim_customers c
        ON c.customer_id = o.customer_id

    JOIN dim_Products p
        ON p.product_id = oi.product_id
),

x1 AS (
    SELECT
        x.customer_unique_id,
        x.first_purchase_date,
        x.last_purchase_date,
        x.Frequency,

        -- Recency measured as of 31-Jan-2026
        DATEDIFF(
            '2026-01-31',
            x.last_purchase_date
        ) AS Recency,

        x.Monetary,

        -- Repeat behaviour
        CASE
            WHEN x.Frequency >= 2
                THEN 'Repeat Buyer'
            ELSE 'One-Time Buyer'
        END AS buyer_type,

        -- Frequency score
        CASE
            WHEN x.Frequency >= 2
                THEN 2
            ELSE 1
        END AS F_score,

        cat.product_category_name,

        -- Category type
        CASE
            WHEN cat.product_category_name IN
                ('electronics', 'furniture', 'auto', 'home_goods', 'toys')
                THEN 'Durable'

            WHEN cat.product_category_name IN
                ('fashion', 'books')
                THEN 'Repeatable'

            ELSE 'Other'
        END AS category_type,

        -- Monetary score
        NTILE(3) OVER (
            ORDER BY
                x.Monetary ASC,
                x.customer_unique_id ASC
        ) AS M_score,

        -- Recency score
        -- R3 = most recent third
        -- R1 = least recent third
        NTILE(3) OVER (
            ORDER BY
                DATEDIFF(
                    '2026-01-31',
                    x.last_purchase_date
                ) DESC,
                x.Monetary DESC
        ) AS R_score

    FROM x

    LEFT JOIN cat
        ON cat.customer_unique_id = x.customer_unique_id
        AND cat.rn = 1
)

SELECT
    *,

    -- RFM score
    CONCAT(
        R_score,
        F_score,
        M_score
    ) AS RFM_score,

    -- Customer segmentation
    CASE

        -- Recent + Repeat + High Monetary
        WHEN R_score = 3
             AND F_score = 2
             AND M_score = 3
            THEN 'Champions'

        -- Recent + One-Time
        WHEN R_score = 3
             AND F_score = 1
            THEN 'Recent One-Time Buyers'

        -- Repeat + Relatively Recent
        WHEN R_score >= 2
             AND F_score = 2
            THEN 'Active Repeat Buyers'

        -- Repeat + Least Recent
        WHEN R_score = 1
             AND F_score = 2
            THEN 'At Risk'

        -- One-Time + High Monetary
        WHEN F_score = 1
             AND M_score = 3
            THEN 'One-Time High Value'

        -- Remaining One-Time Buyers
        WHEN F_score = 1
             AND M_score IN (1, 2)
            THEN 'Hibernating'

        ELSE 'Hibernating'

    END AS customer_segment

FROM x1

ORDER BY
    RFM_score DESC;
