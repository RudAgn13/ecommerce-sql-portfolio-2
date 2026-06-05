# Project 01 — Customer Lifecycle Analysis

## What This Project Is About

Every ecommerce business eventually asks the same questions: who are our best customers, who is about to leave, and what does it actually cost to acquire someone who sticks around? This project builds the analytical foundation to answer all three.

The six metrics here move from raw behaviour (order summary) to segmentation (RFM, churn risk) to financial modelling (AOV, LTV). Together they give a complete picture of the customer base — not just what happened, but what it means and what to do about it.

---

## Metrics

| # | Metric | Business Question Answered |
|---|--------|---------------------------|
| 1 | CUSTOMER ORDER SUMMARY | How active is each customer and how long have they been with us? |
| 2 | AOV BY CUSTOMER TIER | Is the loyalty programme actually driving higher spend? |
| 3 | RFM SEGMENTATION | Which customers should marketing prioritise right now? |
| 4 | COHORT RETENTION (MONTH 0–6) | Are we getting better or worse at keeping customers? |
| 5 | CHURN RISK FLAGGING | Which high-value customers are about to leave? |
| 6 | LTV BY ACQUISITION CHANNEL | Which channels bring customers worth keeping? |

---

## METRIC 1 — CUSTOMER ORDER SUMMARY

**Why It Matters:** This is the foundation query for the project. Before any segmentation, you need a clean per-customer summary of delivered orders, total spend, first and last order dates, and active lifespan. Every subsequent metric in this project builds on this shape.

**Key Output Columns:** `customer_id`, `delivered_orders`, `total_spend`, `first_order_date`, `last_order_date`, `lifespan` (days)

---

## METRIC 2 — AOV BY CUSTOMER TIER

**Why It Matters:** AOV is one of the three levers of revenue growth alongside acquisition and purchase frequency. If Platinum customers have the same AOV as Bronze, the tier structure is not incentivising spend — customers are being rewarded without contributing more. AOV by tier also informs where to set the free shipping threshold to nudge customers into adding one more item.

**Key Output Columns:** `tier`, `customers_in_tier`, `total_delivered_orders`, `total_revenue`, `aov`, `avg_orders_per_customer`

**Note:** Only tiers with at least one delivered order appear. Tiers with zero delivered orders are excluded by the inner join.

---

## METRIC 3 — RFM SEGMENTATION

**Why It Matters:** RFM (Recency, Frequency, Monetary) is the industry standard for customer segmentation because each segment maps directly to a CRM action:

| Segment | CRM Action |
|---------|-----------|
| Champion | Loyalty perks, early sale access |
| Loyal | Upsell and cross-sell campaigns |
| New Customer | Onboarding flow, category discovery |
| At Risk | Win-back discount, re-engagement email |
| Lost | Sunset or last-chance high-value offer |
| Needs Attention | Lighter nudge, preference survey |

**How Scoring Works:** Each customer is scored 1–5 on Recency, Frequency, and Monetary value using `NTILE(5)` window functions. Segments are assigned by applying business rules to the R and F scores.

**Key Output Columns:** `segment`, `customers_by_segment`, `avg_recency`, `avg_frequency`, `avg_monetary`

**Design Note:** Recency uses `MAX(order_date)` from the orders table as the anchor point instead of `CURRENT_DATE`. This is intentional — all seed data is from 2024, so using `CURRENT_DATE` would classify every customer as churned and render the segmentation meaningless. In a production pipeline, replace with `CURRENT_DATE`.

---

## METRIC 4 — COHORT RETENTION (MONTH 0 TO MONTH 6)

**Why It Matters:** Retention curves are the single most important signal of product health. A curve that flattens at ~30% by Month 3 shows a loyal core. One that drops to under 10% by Month 2 is a product or expectation problem — not a marketing problem. This chart goes into every quarterly business review.

**How It Works:** Each customer is assigned a cohort based on the month of their first delivered order. For each subsequent month they order again, they count as retained. Retention % = active customers in Month N / cohort size at Month 0.

**Key Output Columns:** `cohort_month`, `total_customers_in_cohort`, `months_since_first`, `active_customers`, `retention_pct`

**Implementation Note:** Cohort month is derived using `MIN(order_date)` as a window function partitioned by customer — this avoids a separate subquery join. Cohort size is recovered using `MAX(CASE WHEN months_since_first = 0)` as a window function — no additional join needed. Both are efficient patterns worth knowing.

---

## METRIC 5 — CHURN RISK FLAGGING

**Why It Matters:** Identifying customers before they fully churn gives the CRM team a window to act. The 60-day threshold is where most ecom platforms see a meaningful drop in reactivation rate. Beyond 180 days, reactivation cost typically exceeds expected revenue for an average customer.

**Bucket Definitions:**
- **Early Churn Risk (60–89 days):** Highest recovery rate — intervene now
- **Churning (90–179 days):** Last-chance win-back offer
- **Churned (180+ days):** Sunset or high-value exception treatment

**Key Output Columns:** `customer_id`, `days_since_last_order`, `bucket`, `tier`, `acquisition_channel`, `total_orders`, `total_spend`

**Design Note:** Results are sorted by `total_spend` descending so the highest-value at-risk customers surface first. These are the ones worth allocating budget to recover. Same `MAX(order_date)` recency anchor as Metric 3.

---

## METRIC 6 — LTV BY ACQUISITION CHANNEL

**Why It Matters:** LTV without CAC is incomplete, but you cannot evaluate channel profitability without first knowing LTV. The LTV:CAC ratio is how growth teams decide where to scale spend:
- **LTV:CAC > 3:1** — Healthy, consider scaling
- **LTV:CAC 1–3:1** — Marginal, optimise before scaling
- **LTV:CAC < 1:1** — Loss-making, reduce or cut

**How LTV Is Computed:**
```
computed_ltv = average_order_value × average_purchase_frequency × average_customer_lifespan
```
AOV is calculated as total channel revenue divided by total channel orders (weighted average), not as an average of individual customer AOVs. This avoids inflation from single high-spend customers.

**Key Output Columns:** `acquisition_channel`, `cohort_size`, `average_order_value`, `average_purchase_frequency`, `average_customer_lifespan`, `average_spend_per_customer`, `computed_ltv`

**Known Limitation:** Customers with only one delivered order have a lifespan of 0 days, which zeroes out `computed_ltv` regardless of spend. A time-boxed LTV (e.g. revenue in first 12 months) handles this correctly and is the preferred approach in production. The formula-based approach is used here for interpretability and to demonstrate the component inputs clearly.

---

## SQL Concepts Demonstrated

| Concept | Where Used |
|---------|-----------|
| Multi-table join | All metrics |
| Aggregation (`SUM`, `COUNT`, `MIN`, `MAX`) | All metrics |
| `NULLIF` for safe division | Metrics 2, 6 |
| `NTILE(5)` window function | Metric 3 |
| `DATE_TRUNC` | Metric 4 |
| Window function for cohort assignment (`MIN() OVER PARTITION BY`) | Metric 4 |
| `MAX(CASE WHEN) OVER PARTITION BY` for cohort size | Metric 4 |
| `AGE()` for month offset calculation | Metric 4 |
| `HAVING` clause on aggregated date expression | Metric 5 |
| Multi-level CTE | Metrics 3, 4, 6 |
| `CASE WHEN` bucketing | Metrics 3, 5 |

---

## Files

| File | Description |
|------|-------------|
| `queries.sql` | All 6 queries with full business context comments |

---

## Database

CartIQ Ecommerce Platform — PostgreSQL 15  
Seed Data: `schema/create_tables_and_seed.sql`  
Tables Used: `customers`, `orders`
