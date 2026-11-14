# E-Commerce Sales & Customer Analytics

**Tools:** MySQL · Power BI · DAX · Power Query

**Dataset:** Kaggle — synthetic U.S. e-commerce data, 2019–2025 (~80K orders, ~69K customers)

**[View the live dashboard](https://app.powerbi.com/view?r=eyJrIjoiMmM2YjFiNjYtNTY5MS00ZGEyLWFmZjQtNmUyZGEyZjY3ZTYyIiwidCI6ImM2ZTU0OWIzLTVmNDUtNDAzMi1hYWU5LWQ0MjQ0ZGM1YjJjNCJ9)** · **[Portfolio](https://codebasics.io/portfolio/NAVEEN-ORSU)** · **[LinkedIn](https://www.linkedin.com/in/naveenorsu/)**

---

## Problem

Find where the business is growing and where it is losing value, across sales, product profitability and customer retention over 7 years.

## SQL in this repository

| File | What it does |
| --- | --- |
| [`sql/01_data_cleaning_views.sql`](sql/01_data_cleaning_views.sql) | Builds the 6 cleaned views the report runs on |
| [`sql/02_rfm_customer_segmentation.sql`](sql/02_rfm_customer_segmentation.sql) | RFM scoring and the 6 customer segments |

## Data preparation (MySQL)

Raw tables had mixed date formats, currency stored as text, negative values, blank strings, invalid ages and duplicate rows.

Built **6 cleaned views** as a reporting layer:

| View | Purpose |
| --- | --- |
| `fact_orders` | De-duplicated orders; mixed date formats fixed with `STR_TO_DATE` |
| `fact_order_items` | Currency text stripped; negative prices corrected with `ABS` |
| `fact_order_payments` | Payment types standardised; blanks kept as NULL via `NULLIF` |
| `fact_order_reviews` | Review dates cast to DATE |
| `dim_Products` | Blank categories defaulted to `Uncategorized`; duplicates ranked out |
| `dim_customers` | Age validated 0–100; first order month and order count via window functions |

**Techniques used:** CTEs · `ROW_NUMBER` de-duplication · `COALESCE` / `NULLIF` · `CASE` · `LOWER` / `TRIM` standardisation · type casting

## RFM segmentation

- **Recency** — `DATEDIFF` from the 31-Jan-2026 snapshot date to the last order, scored with `NTILE(3)`
- **Frequency** — binary score: repeat buyer (2+ orders) vs one-time buyer
- **Monetary** — `NTILE(3)` on total product spend
- Each customer is tagged with the category they last bought from, grouped into Durable, Repeatable or Other
- Output: **6 segments** — Champions, Active Repeat Buyers, Recent One-Time Buyers, One-Time High Value, At Risk, Hibernating

## Power BI model

- **Star schema:** 2 fact tables, 3 dimension tables
- **~80 DAX measures:** YTD vs prior year, YoY variance, AOV, CLV, repeat customer rate
- **4-page report** with bookmarks, page navigation, KPI sparklines and dynamic YoY colour and arrow indicators

## Key findings

- **2025 growth was volume-led** — revenue +27.4% to $23M, orders +26.3%, AOV −0.6%
- **Electronics** — 74% of 2025 revenue but only an 18.2% margin; all 286 products below 25%
- **Fashion** — 62.4% margin on just ~7% of revenue
- **Retention is weak** — ~13% lifetime repeat-purchase rate, median 619 days to a second order

## Recommendations

1. 90-day post-purchase retention campaign to shorten the 619-day repeat gap
2. Shift marketing spend toward high-margin Fashion
3. Q4 stock planning on Electronics volume
4. Product bundles to lift AOV
