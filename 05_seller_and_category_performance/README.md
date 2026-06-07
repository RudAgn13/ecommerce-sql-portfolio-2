# Project 05 — Seller & Category Performance

## What This Project Is About

Marketplace health lives and dies with seller quality. A platform where top sellers are high-quality and compliant grows; one where bad sellers dominate with poor products and high returns collapses. At the same time, category health determines whether customers find what they are looking for — and come back for it.

This project builds the analytical framework to grade sellers on a composite scorecard, rank them within their tiers, identify fast and slow-moving categories, measure customer loyalty by category, and track how new vs established sellers contribute to GMV over time. Together these five metrics give the Seller Management and Category teams everything they need for weekly performance reviews.

---

## Metrics

| # | Metric | Business Question Answered |
|---|--------|---------------------------|
| 1 | SELLER SCORECARD | Which sellers are performing well, and which need intervention? |
| 2 | TOP AND BOTTOM 3 SELLERS BY GMV | Who are the best and worst contributors within each seller tier? |
| 3 | CATEGORY VELOCITY — FAST/SLOW MOVING | Where is working capital being tied up in unsold inventory? |
| 4 | REPEAT PURCHASE RATE BY CATEGORY | Which categories build loyalty, and which have a trust problem? |
| 5 | NEW VS ESTABLISHED SELLER GMV CONTRIBUTION OVER TIME | Is the seller acquisition funnel producing revenue? |

---

## METRIC 1 — SELLER SCORECARD

**Why It Matters:** Without a structured scorecard, seller tier promotion and penalty enforcement are subjective and inconsistent. A single composite number per seller enables account managers to prioritise their time — focus on Q4 sellers at risk of deactivation, reward Q1 sellers with better placement, and track improvement over time.

**Composite Score Weights:**

| Dimension | Max Points | Business Rationale |
|-----------|-----------|-------------------|
| OTDR | 30 | Primary driver of customer satisfaction and NPS |
| Return Rate | 30 | Direct cost to platform — reverse logistics, refunds, write-downs |
| GMV | 20 | Revenue contribution to the platform |
| Delivery Speed | 20 | Customer experience and repeat purchase driver |
| **Total** | **100** | |

**Key Columns Explained:**
- `composite_score` — a single comparable number enabling objective tier review and penalty decisions
- `performance_quartile` — `NTILE(4)` splits sellers into four equal groups. Q1 = top performers, Q4 = bottom. Sellers in Q4 for two consecutive review periods are candidates for deactivation review.
- `dispatch_to_delivery_days` — actual delivery window minus the seller's declared `avg_dispatch_days`, approximating courier-only transit time. This is a schema workaround — no discrete ship date column exists, so this is the closest available proxy.

**Key Output Columns:** `seller_id`, `total_delivered_orders`, `gross_merchandise_value`, `otdr_pct`, `return_rate_pct`, `dispatch_to_delivery_days`, `composite_score`, `performance_quartile`

---

## METRIC 2 — TOP AND BOTTOM 3 SELLERS BY GMV

**Why It Matters:** Within each tier, the spread between top and bottom performers reveals the health of that tier's definition. A wide GMV gap between the best and worst Elite sellers signals the tier is too broad. Account managers use this view to celebrate and learn from top performers, and to put bottom performers on structured improvement plans before escalating to deactivation.

**Key Columns Explained:**
- `top_ranks` — rank within tier by GMV descending. Top 3 = highest revenue contributors.
- `bottom_ranks` — rank within tier by GMV ascending. Bottom 3 = lowest revenue contributors, most at risk.
- `RANK()` is used instead of `ROW_NUMBER()` so sellers with identical GMV receive the same rank. Ties are surfaced rather than arbitrarily broken — relevant when two sellers have nearly identical performance.

**Design Note:** Inner joins are intentional to exclude sellers with zero delivered orders. A seller that has never fulfilled a delivered order has no meaningful GMV rank and should not appear in this analysis.

**Key Output Columns:** `seller_tier`, `seller_id`, `gmv`, `top_ranks`, `bottom_ranks`

---

## METRIC 3 — CATEGORY VELOCITY — FAST/SLOW MOVING

**Why It Matters:** Slow-moving inventory is working capital being destroyed. Every unsold unit represents procurement cost, storage cost, and opportunity cost. This analysis tells the category team which products to discount or liquidate (slow movers) and which to restock faster (top movers). `gmv_tied_up_in_slow_movers` converts velocity into a rupee figure — the number that gets attention in a finance review.

**Key Columns Explained:**
- `top_movers` — products in the top velocity quartile within their category. These drive category GMV and should be prioritised for restocking.
- `slow_movers` — products in the bottom velocity quartile. Primary candidates for promotional clearance or delisting.
- `gmv_tied_up_in_slow_movers` — total revenue generated by slow movers. A high number here means slow movers are expensive items that sell rarely, not just cheap items nobody wants — a different problem requiring a different fix.
- `avg_days_since_last_sale` — recency of sales activity across the category as a whole.

**Design Note on Recency Anchor:** Uses `MAX(order_date)` from the orders table instead of `CURRENT_DATE` for consistency with the 2024 seed dataset. In production, replace with `CURRENT_DATE`.

**Design Note on COALESCE:** Products with no delivered orders have a NULL last order date. `COALESCE` defaults these to `MAX(order_date)`, giving `days_since_last_sale = 0`. This prevents NULL from polluting the velocity analysis and keeps truly unsold products from being misclassified as recently active.

**Key Output Columns:** `category_id`, `total_products`, `top_movers`, `slow_movers`, `gmv_tied_up_in_slow_movers`, `avg_days_since_last_sale`

---

## METRIC 4 — REPEAT PURCHASE RATE BY CATEGORY

**Why It Matters:** Repeat purchase rate is one of the clearest signals of category health. High repeat rate signals loyalty and product-market fit. Low repeat rate means one of two things — either the category is inherently one-time-purchase (furniture, large appliances) or there is a quality or trust problem driving customers away after a single bad experience. Knowing which is which is critical before taking action: you would not run a re-engagement campaign for furniture the same way you would for skincare.

**Key Columns Explained:**
- `repeat_purchase_rate_pct` — the primary health indicator. Compare across categories to identify loyalty leaders and laggards.
- `avg_orders_per_buyer` — how sticky is the category on average? A category with 60% repeat rate but 2.1 avg orders per buyer is meaningfully different from one with 60% repeat rate and 5.8 avg orders — the latter has far stronger habitual behaviour.

**Key Output Columns:** `parent_category`, `total_unique_buyers`, `repeat_buyers`, `repeat_purchase_rate_pct`, `avg_orders_per_buyer`

---

## METRIC 5 — NEW VS ESTABLISHED SELLER GMV CONTRIBUTION OVER TIME

**Why It Matters:** A healthy marketplace sees established sellers growing steadily while new sellers consistently onboard and contribute. If GMV is entirely concentrated in sellers onboarded 2+ years ago, the platform is stagnating — no fresh supply, no new competition, and dangerously high dependency on a small group of long-term sellers. Tracking the new vs established GMV split monthly tells leadership whether the seller acquisition funnel is actually producing revenue.

**Key Columns Explained:**
- `gmv_pct` — share of total monthly GMV from each bucket. A healthy platform typically sees new sellers contribute 15–25% of GMV, growing over time as they mature.
- `sellers_by_bucket` — how many unique sellers in each bucket are actively contributing GMV each month? A rising count in the new bucket with flat GMV means new sellers are low-quality. A falling count means the acquisition funnel is slowing.

**Bucket Definition:**
- **New** — onboarded within 18 months of the database max order date. 18 months is chosen to capture sellers still in their growth ramp on CartIQ.
- **Established** — onboarded more than 18 months before max order date.

**Implementation Note on Nested Window Function:** `gmv_pct` uses `SUM(SUM(oi.line_total)) OVER (PARTITION BY order_month)`. The inner `SUM(oi.line_total)` aggregates to bucket + month level via `GROUP BY`. The outer `SUM(...) OVER` then totals across buckets within the same month via the window partition, giving the monthly total against which each bucket's share is calculated.

**Key Output Columns:** `buckets`, `order_month`, `gmv_by_bucket`, `gmv_pct`, `sellers_by_bucket`

---

## SQL Concepts Demonstrated

| Concept | Where Used |
|---------|-----------|
| Multi-level CTE | Metrics 1, 2, 4, 5 |
| `LEFT JOIN` to preserve all sellers including zero-order | Metric 1 |
| Composite weighted scoring with nested `CASE WHEN` addition | Metric 1 |
| `NTILE(4)` window function for performance quartiling | Metric 1 |
| `RANK() OVER (PARTITION BY)` within-tier ranking | Metric 2 |
| Dual `RANK()` in same query (top and bottom simultaneously) | Metric 2 |
| `NTILE(4) OVER (PARTITION BY category_id)` | Metric 3 |
| `COALESCE` for NULL date handling | Metric 3 |
| `LEFT JOIN` with ON-clause filter for delivered orders only | Metric 3 |
| Year × 12 month arithmetic for gap calculation | Metric 5 |
| Nested aggregate window function `SUM(SUM()) OVER` | Metric 5 |
| `COUNT(DISTINCT ...)` for unique seller counting | Metric 5 |

---

## Files

| File | Description |
|------|-------------|
| `queries.sql` | All 5 queries with full business context comments |

---

## Database

CartIQ Ecommerce Platform — PostgreSQL 15  
Seed Data: `schema/create_tables_and_seed.sql`  
Tables Used: `sellers`, `order_items`, `orders`, `returns`, `products`, `categories`, `customers`
