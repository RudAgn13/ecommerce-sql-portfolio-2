# Project 03 — Supply Chain & Operations Health

## What This Project Is About

Operations analytics is underrepresented in most analyst portfolios — yet ecommerce companies hire heavily for it. Every delivery that arrives late, every payment that fails, every return that takes two weeks to resolve is a data problem before it becomes a customer problem. This project builds the metrics a Head of Logistics and a Head of Finance review daily to keep the fulfilment engine running cleanly.

The six metrics cover the full post-purchase journey: delivery reliability by state and seller, return root cause attribution, payment failure leakage, the end-to-end fulfilment funnel, and the economics of COD vs prepaid orders.

---

## Metrics

| # | Metric | Business Question Answered |
|---|--------|---------------------------|
| 1 | OTDR BY STATE | Which states have a systemic delivery problem? |
| 2 | OTDR BY SELLER TIER | Is late delivery a courier problem or a seller problem? |
| 3 | RETURN RATE & ROOT CAUSE ANALYSIS | Why are customers returning, and whose fault is it? |
| 4 | PAYMENT FAILURE RATE BY METHOD & GATEWAY | Which payment combinations are losing the most revenue? |
| 5 | FULFILLMENT FUNNEL BY MONTH | Where in the order journey are we losing the most orders? |
| 6 | COD VS PREPAID ORDER ANALYSIS | What is the true cost of COD, and where should we push prepaid? |

---

## METRIC 1 — OTDR BY STATE

**Why It Matters:** OTDR (On-Time Delivery Rate) is the #1 logistics KPI. It directly affects customer satisfaction, repeat purchase rate, and NPS. A state with 60% OTDR is haemorrhaging customer trust — and that trust loss shows up in retention metrics 30–60 days later, making OTDR a leading indicator worth watching weekly. State-level data informs courier SLA negotiations, warehouse placement decisions, and last-mile partner selection.

**Key Columns Explained:**
- `otdr_pct` — primary health indicator per state. Below 85% warrants immediate investigation.
- `avg_days_late` — severity of lateness when it occurs. A state with 80% OTDR but 10 avg days late is more damaging than one with 75% OTDR but 1 avg day late.
- `max_days_late` — worst-case delay, useful for flagging extreme outliers that generate customer escalations.

**Design Note:** `avg_days_late` and `max_days_late` use `ELSE NULL` so that on-time deliveries are excluded from the calculation. Using `ELSE 0` would incorrectly drag the average down and understate the severity of late deliveries.

**Key Output Columns:** `shipping_state`, `total_orders`, `on_time_deliveries`, `late_deliveries`, `otdr_pct`, `avg_days_late`, `max_days_late`

---

## METRIC 2 — OTDR BY SELLER TIER

**Why It Matters:** When OTDR is poor, the critical question is: is this a courier problem or a seller problem? If Elite sellers achieve 95% OTDR while New sellers are at 55%, the bottleneck is seller dispatch speed — not the courier. This distinction determines whether ops invests in renegotiating courier SLAs or improving seller onboarding and dispatch standards. `avg_dispatch_days` from the sellers table is included to test whether self-reported dispatch speed actually correlates with real delivery performance.

**Key Columns Explained:**
- `otdr_pct` by tier — does seller experience and accountability drive delivery quality?
- `average_dispatch_days` — do tiers with faster declared dispatch actually achieve better OTDR?

**Design Note:** `COUNT(DISTINCT o.order_id)` is used throughout because joining through `order_items` can produce duplicate order rows when an order contains multiple items from the same seller tier. Using `COUNT` without `DISTINCT` would inflate the denominator and understate OTDR.

**Key Output Columns:** `seller_tier`, `average_dispatch_days`, `total_orders`, `on_time_deliveries`, `late_deliveries`, `otdr_pct`, `avg_days_late`, `max_days_late`

---

## METRIC 3 — RETURN RATE & ROOT CAUSE ANALYSIS

**Why It Matters:** Returns are a profit killer. Every return triggers reverse logistics costs, potential product write-downs, and a refund liability. Without root cause attribution, every return looks identical and the response is always "reduce returns" with no actionable path. Breaking returns down by reason and category tells each team exactly where to intervene:

| Return Reason | Root Cause | Team Responsible |
|---------------|-----------|-----------------|
| Damaged / Wrong Item | Fulfilment or packaging failure | Operations |
| Quality Issue | Seller-side product problem | Seller Management |
| Size Mismatch | Product data or size guide failure | Catalogue |
| Changed Mind / Late Delivery | Customer expectation mismatch | Marketing / Logistics |

**Key Columns Explained:**
- `sellers_fault_return_pct` — what proportion of returns in each category are seller-attributable? High seller fault % justifies penalty enforcement or delisting.
- `avg_days_to_resolve` — slow resolution erodes trust even after a bad experience. A 10-day refund wait turns a one-time returner into a churner.
- `number_of_returns_in_category` — total return burden per parent category across all reasons, showing which categories have the highest absolute return volume.

**Implementation Note:** `COUNT(c.parent_category) OVER (PARTITION BY c.parent_category)` is used to compute category-level return totals as a window function. The alternative nested aggregate `SUM(COUNT(r.return_id)) OVER (PARTITION BY c.parent_category)` is not permitted by PostgreSQL without wrapping in an outer query — the window approach here is cleaner and produces the same result.

**Key Output Columns:** `return_reason`, `parent_category`, `number_of_returns_in_category`, `total_returns`, `total_refund_value`, `avg_days_to_resolve`, `seller_fault_returns`, `rejected_refunds`, `avg_refund_amount_per_return`, `sellers_fault_return_pct`

---

## METRIC 4 — PAYMENT FAILURE RATE BY METHOD & GATEWAY

**Why It Matters:** Every payment failure is a lost order. The customer attempted to buy, the transaction failed, and most will not retry. Payment failure rates by gateway are used to negotiate SLAs with payment partners and to decide which gateways to default-promote at checkout. A gateway with an 8% failure rate on high-AOV transactions costs more in lost revenue than it saves in processing fees — a case that `failed_gmv` makes clearly.

**Key Columns Explained:**
- `failure_rate_pct` — primary metric for gateway performance benchmarking.
- `failed_gmv` — converts failure rate into a rupee figure that leadership responds to.
- `most_common_failure_reason` — `MODE()` surfaces the single most frequent failure reason per gateway, enabling targeted fixes. `timeout` signals an infrastructure issue; `card_declined` is an issuer-side problem requiring a different intervention entirely.

**Key Output Columns:** `payment_gateway`, `payment_method`, `total_payment_attempts`, `successful_payments`, `failed_payments`, `refunded_payments`, `failed_gmv`, `failure_rate_pct`, `most_common_failure_reason`

---

## METRIC 5 — FULFILLMENT FUNNEL BY MONTH

**Why It Matters:** Not all orders placed become revenue. Each stage of the funnel has a different failure mode and a different team that owns it. Tracking this funnel monthly lets ops pinpoint exactly which stage is degrading and assign accountability correctly — rather than treating all lost orders as the same problem.

**Funnel Stage to Failure Mode Mapping:**

| Stage Drop-Off | Failure Mode | Owner |
|---------------|-------------|-------|
| Placed → Confirmed | Customer cancellation | Pricing / Product Data |
| Confirmed → Shipped | Seller dispatch failure | Seller Operations |
| Shipped → Delivered | Last-mile failure | Courier / Logistics |
| Delivered → Returned | Quality or expectation failure | Category / Seller |

**Key Columns Explained:**
- `returned_rate_pct` — denominator is `delivered + returned` (orders that physically reached the customer), not total placed. This is the correct business definition of return rate — measuring what % of arrived orders came back, not what % of all placed orders.
- `confirmation_rate_pct` — direct measure of pre-fulfilment demand health.

**Key Output Columns:** `order_month`, `placed_orders`, `confirmed_orders`, `shipped_orders`, `delivered_orders`, `returned_orders`, `cancelled_orders`, `confirmation_rate_pct`, `delivered_rate_pct`, `returned_rate_pct`, `cancellation_rate_pct`

---

## METRIC 6 — COD VS PREPAID ORDER ANALYSIS

**Why It Matters:** COD (Cash on Delivery) orders carry significantly higher operational costs than prepaid — failed delivery attempts, return-to-origin (RTO) risk, and cash reconciliation overhead. In India, COD can represent 40–60% of orders in tier-2 and tier-3 cities despite being more expensive to fulfil. This analysis tells ops where to restrict COD and where to push prepaid incentives (discounts, loyalty points) to shift the payment mix without losing the order entirely.

**Key Columns Explained:**
- `return_rate_pct` — COD typically runs 2–3x higher return rate than prepaid because customers face no friction to reject delivery at the door.
- `payment_failure_pct` — for prepaid, this measures gateway drop-off. For COD, failed payment status captures orders where cash collection was unsuccessful at delivery.
- `net_amount_per_order` — if COD AOV is significantly lower than prepaid, high-value customers already prefer prepaid, which reinforces the case for prepaid incentives specifically on large orders.

**Design Note:** The final join between `payments_cte` and `returns_grouped` uses a standard `JOIN`. If either COD or prepaid has zero returns, `returns_grouped` will not produce a row for that method, and the `JOIN` will silently drop it. `COALESCE` handles NULLs but cannot recover a dropped row. In production, replace with `LEFT JOIN` to guarantee both payment types always appear in the output.

**Key Output Columns:** `payment_method`, `order_count`, `total_net_amount`, `net_amount_per_order`, `return_count`, `return_rate_pct`, `payment_failure_count`, `payment_failure_pct`

---

## SQL Concepts Demonstrated

| Concept | Where Used |
|---------|-----------|
| `CASE WHEN` inside `COUNT` for conditional counts | Metrics 1, 2, 3, 4, 5 |
| `ELSE NULL` to exclude rows from aggregation | Metrics 1, 2 |
| 3-table and 5-table joins | Metrics 2, 3 |
| `COUNT(DISTINCT ...)` to prevent fan-out duplication | Metric 2 |
| `COUNT() OVER (PARTITION BY)` window function | Metric 3 |
| `MODE() WITHIN GROUP (ORDER BY)` ordered-set aggregate | Metric 4 |
| Multi-level CTE (3 CTEs in sequence) | Metric 6 |
| `COALESCE` for NULL handling on left-join results | Metric 6 |
| Funnel logic with nested `CASE WHEN` denominators | Metric 5 |
| `DATE_TRUNC` for monthly grouping | Metrics 1, 5 |

---

## Files

| File | Description |
|------|-------------|
| `queries.sql` | All 6 queries with full business context comments |

---

## Database

CartIQ Ecommerce Platform — PostgreSQL 15  
Seed Data: `schema/create_tables_and_seed.sql`  
Tables Used: `orders`, `order_items`, `sellers`, `products`, `categories`, `payments`, `returns`
