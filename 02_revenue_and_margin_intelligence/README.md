# Project 02 — Revenue & Margin Intelligence

## What This Project Is About

Revenue is vanity, margin is sanity. Most ecommerce reporting stops at GMV — how much was sold. This project goes further, asking how much was actually kept after discounts, cancellations, returns, and cost of goods. Every metric here maps directly to a decision that Finance, Category, or Growth leadership makes on a weekly basis.

The five metrics move from top-line revenue (GMV waterfall) to category-level profitability (contribution margin) to promotional strategy (discount depth) to growth quality (MoM/YoY) to customer concentration risk (Pareto analysis).

---

## Metrics

| # | Metric | Business Question Answered |
|---|--------|---------------------------|
| 1 | MONTHLY GMV VS NET REVENUE VS REALIZED REVENUE | Where is revenue being lost between sale and settlement? |
| 2 | CONTRIBUTION MARGIN BY CATEGORY | Which categories are actually profitable, and which are subsidised? |
| 3 | DISCOUNT DEPTH ANALYSIS | At what discount level do orders start losing money? |
| 4 | MONTH-OVER-MONTH GROWTH WITH YOY COMPARISON | Is growth real, or just a seasonal repeat? |
| 5 | REVENUE CONCENTRATION — TOP 20% CUSTOMERS | How fragile is the revenue base? |

---

## METRIC 1 — MONTHLY GMV VS NET REVENUE VS REALIZED REVENUE

**Why It Matters:** These three numbers tell three different stories about the same period. GMV is what gets announced in press releases. Net Revenue removes discounts — what customers actually paid. Realized Revenue removes cancellations and returns — what the business kept. A platform with ₹100Cr GMV but 25% leakage is a very different business from one with 5% leakage. Tracking this waterfall monthly tells you whether operations are getting tighter or looser over time.

**Key Columns Explained:**
- `discount_rate_pct` — are promotions getting more aggressive over time?
- `leakage_rate_pct` — what share of revenue is being eroded by failed orders? Rising leakage often signals a seller fulfilment or product quality problem, not a demand problem.
- `aov` — computed only on delivered orders to reflect true transaction value, not inflated by cancelled order amounts.

**Key Output Columns:** `order_month`, `gross_merchandise_value`, `total_discounts`, `net_revenue`, `revenue_lost`, `realized_revenue`, `discount_rate_pct`, `leakage_rate_pct`, `total_orders`, `cancelled_count`, `returned_count`, `aov`

---

## METRIC 2 — CONTRIBUTION MARGIN BY CATEGORY

**Why It Matters:** A category driving 30% of GMV at 2% gross margin is destroying value — it consumes logistics, seller management, and customer support resources without generating proportional profit. This is the query a Category Manager runs every Monday to decide which categories to promote, reprice, or fix.

**Key Columns Explained:**
- `gross_profit_pct` — the primary health indicator for a category. Negative means the category is loss-making at the product level before even accounting for logistics and marketing.
- `net_platform_take` — commission earned by CartIQ minus return costs absorbed. A negative value means CartIQ is subsidising that category.
- `return_value` — high return value relative to gross revenue signals a quality or expectation mismatch worth investigating at the seller level.

**Design Note:** Platform commission is calculated on all delivered order items. This reflects real marketplace economics — the transaction fee is charged at point of sale and is not reversed on return. Return costs are deducted separately to show net platform take.

**Key Output Columns:** `parent_category`, `category_name`, `total_delivered_orders`, `gross_category_revenue`, `total_cogs`, `return_value`, `platform_commission`, `gross_profit`, `gross_profit_pct`, `net_platform_take`

---

## METRIC 3 — DISCOUNT DEPTH ANALYSIS

**Why It Matters:** Heavy discounting inflates GMV but erodes margin and trains customers to wait for sales before purchasing at full price. This query finds the discount threshold beyond which orders become loss-making per line. The output directly informs promotional guardrails — most ecommerce companies set a floor below which sellers cannot discount without approval from the category team.

**Key Columns Explained:**
- `avg_margin_pct` by bucket — at what discount level does margin turn negative? This is the breakeven discount rate.
- `total_gross_profit` by bucket — where is the most absolute profit being made or destroyed?
- `avg_unit_price` — average revenue per line item within each bucket. Note: if quantity > 1 on a line, this reflects average line value rather than strictly average unit price. For this dataset, quantities are predominantly 1, so the distinction is minimal.

**Key Output Columns:** `bucket`, `count`, `total_revenue`, `total_cogs`, `total_gross_profit`, `avg_margin_pct`, `avg_unit_price`

---

## METRIC 4 — MONTH-OVER-MONTH GROWTH WITH YOY COMPARISON

**Why It Matters:** A 20% MoM revenue jump in October is meaningless without context — if last year it was +40% in October driven by Diwali, you are actually underperforming. YoY comparison normalises for seasonality and gives a true read on whether the business is growing structurally or just riding a calendar event. This is typically the first chart in any monthly business review deck.

**Key Columns Explained:**
- `MoM_growth` — short-term momentum. Useful for catching sudden drops that need immediate investigation.
- `YoY_growth` — seasonality-adjusted growth. The number leadership actually cares about for evaluating business performance.

**Note:** YoY will return NULL for the first 12 months of data since there is no prior year to compare against. This is expected and correct behaviour, not a query error.

**Key Output Columns:** `order_month`, `revenue`, `MoM_growth (%)`, `YoY_growth (%)`

---

## METRIC 5 — REVENUE CONCENTRATION — TOP 20% CUSTOMERS

**Why It Matters:** In most ecommerce businesses, roughly 20% of customers drive 60–80% of revenue (the Pareto principle). Knowing your actual concentration ratio tells you how fragile the revenue base is — and how much it costs to lose a single high-value customer. This analysis justifies the business case for retention investment. Protecting one Platinum customer may be worth more than acquiring ten Bronze ones.

**How to Read the Output:** Scroll down the ranked list and find where `cumulative_revenue_pct` crosses 80%. The `customer_pct` value at that row is your concentration ratio. If the top 15% of customers account for 80% of revenue, the business is heavily concentrated and highly sensitive to churn among its best customers.

**Design Note on ROW_NUMBER:** `ROW_NUMBER()` is used instead of `RANK()` or `DENSE_RANK()` to ensure `customer_pct` increases smoothly with each row even when multiple customers have identical spend. `RANK()` would assign the same percentage to tied customers, creating flat steps in the cumulative curve and overstating concentration at those spend levels.

**Scope Note:** This query includes all orders regardless of status to measure total revenue contribution per customer across their full relationship with CartIQ. To measure concentration on collected revenue only, add `WHERE order_status = 'delivered'` to the CTE.

**Key Output Columns:** `customer_id`, `cumulative_revenue_pct`, `customer_pct`

---

## SQL Concepts Demonstrated

| Concept | Where Used |
|---------|-----------|
| `DATE_TRUNC` for monthly grouping | Metrics 1, 4 |
| Conditional aggregation (`CASE WHEN` inside `SUM` / `COUNT`) | Metrics 1, 2 |
| `NULLIF` for safe division | Metrics 1, 2, 3, 5 |
| 4-table join | Metric 2 |
| Inline margin calculation from joined tables | Metrics 2, 3 |
| CTE for staged calculation | Metrics 3, 4, 5 |
| `LAG()` window function with offset (1 and 12) | Metric 4 |
| Cumulative `SUM() OVER (ORDER BY)` | Metric 5 |
| `ROW_NUMBER()` for smooth percentile ranking | Metric 5 |
| `COUNT(*) OVER ()` for total count in window | Metric 5 |

---

## Files

| File | Description |
|------|-------------|
| `queries.sql` | All 5 queries with full business context comments |

---

## Database

CartIQ Ecommerce Platform — PostgreSQL 15  
Seed Data: `schema/create_tables_and_seed.sql`  
Tables Used: `orders`, `order_items`, `products`, `categories`
