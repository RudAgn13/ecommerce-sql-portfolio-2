# Project 04 — Marketing & Acquisition ROI

## What This Project Is About

Marketing is the largest variable cost in ecommerce — and the hardest to justify without data. This project builds the analytical foundation to answer whether marketing spend is actually working: which channels acquire customers cheaply enough to be profitable, which email campaigns convert, which traffic sources drive revenue, and whether individual campaigns generated more than they cost.

The four metrics move from acquisition cost (CAC) to campaign funnel analysis (email) to session-level attribution (UTM) to full campaign ROI. Together they give a complete picture of marketing efficiency that a CMO, growth lead, or performance marketing manager can act on directly.

---

## Metrics

| # | Metric | Business Question Answered |
|---|--------|---------------------------|
| 1 | CUSTOMER ACQUISITION COST (CAC) BY CHANNEL | Which channels acquire customers at a profitable cost? |
| 2 | EMAIL CAMPAIGN FUNNEL | Where in the email funnel does conversion break down? |
| 3 | CHANNEL PERFORMANCE — SESSIONS TO ORDERS | Which traffic sources drive the highest quality visits? |
| 4 | CAMPAIGN ROI | Did each campaign make or lose money? |

---

## METRIC 1 — CUSTOMER ACQUISITION COST (CAC) BY CHANNEL

**Why It Matters:** CAC is meaningless without LTV, but you cannot evaluate channel profitability without first knowing what it costs to acquire a customer from each source. The LTV:CAC ratio is how growth teams decide where to scale spend and where to cut:
- **LTV:CAC > 3:1** — Healthy, consider scaling
- **LTV:CAC 1–3:1** — Marginal, optimise before scaling
- **LTV:CAC < 1:1** — Loss-making, reduce or cut

**Key Columns Explained:**
- `total_spend` — total marketing cost attributed to each channel bucket
- `customers_acquired` — unique customers acquired via that channel
- `cac` — cost per acquired customer, the primary optimisation metric for any performance marketing team

**Design Note on Channel Mapping:** The `marketing_events` table stores channel as a traffic source (`google`, `meta`, `email`, `push`, `sms`) while the `customers` table stores `acquisition_channel` as a business label (`paid_search`, `social`, `email`, `organic`, `referral`). These do not match directly. A `CASE WHEN` mapping bridges both columns to a shared `channel_bucket` before joining. This is intentional and documented in the query.

**Key Output Columns:** `channel_bucket`, `total_spend`, `customers_acquired`, `cac`

---

## METRIC 2 — EMAIL CAMPAIGN FUNNEL

**Why It Matters:** Email is typically the highest-ROI retention channel in ecommerce. A campaign with a 45% open rate but 0.2% purchase conversion has a broken offer or landing page — not a delivery problem. This funnel pinpoints exactly where conversion breaks at each stage, and each drop-off has a different fix:

| Stage Drop-Off | Problem | Fix |
|---------------|---------|-----|
| Low open rate | Subject line or send-time | A/B test subject lines, optimise send window |
| Low CTR | Email content or offer | Redesign creative, sharpen CTA |
| Low purchase conversion | Landing page or product-offer mismatch | Fix landing page, improve offer relevance |

**Key Columns Explained:**
- `open_rate_pct` — what % of recipients engage at all?
- `click_through_rate_pct` — of those who opened, what % took action? Uses `unique_clickers` as the numerator to avoid counting repeat clicks from the same customer multiple times.
- `purchase_conversion_pct` — of those who clicked, what % bought within 3 days? The 3-day window captures intent-driven purchases without attributing unrelated future orders to the campaign.

**Implementation Note:** The time-window filter and `email_clicked` condition are applied in the `LEFT JOIN` clause rather than in `WHERE`. This keeps all email event rows in scope for the funnel counts (sent, opened, clicked) while only matching orders that meet the attribution criteria. Filtering in `WHERE` would eliminate non-clicked rows and break the sent and opened counts entirely.

**Key Output Columns:** `campaign_name`, `emails_sent`, `emails_opened`, `emails_clicked`, `unique_clickers`, `order_within_3_days`, `revenue_from_order_within_3_days`, `open_rate_pct`, `click_through_rate_pct`, `purchase_conversion_pct`

---

## METRIC 3 — CHANNEL PERFORMANCE — SESSIONS TO ORDERS

**Why It Matters:** Not all traffic is equal. A channel driving 10,000 sessions at 0.5% conversion is underperforming one driving 1,000 sessions at 8% conversion. Revenue per session normalises both volume and conversion into one comparable metric across all channels. This is how growth teams decide where to increase paid spend and where to pull back — without needing to run a controlled experiment first.

**Key Columns Explained:**
- `bounce_rate_pct` — what % of sessions leave immediately with no engagement? High bounce on a paid channel means the ad creative and landing page are misaligned — budget is being wasted before the customer even sees a product.
- `conversion_rate_pct` — of all sessions, what % resulted in a placed order?
- `revenue_per_session` — the most actionable single metric. Multiply by incremental sessions to forecast revenue from additional spend on that channel.

**Implementation Note:** Sessions are joined to orders on `session_id` — a precise one-to-one attribution since `session_id` is stored directly on the orders table. This avoids the fan-out risk of joining on `customer_id`, which would incorrectly attribute all of a customer's orders to every session they ever had.

**Key Output Columns:** `utm_source`, `utm_medium`, `total_sessions`, `bounced_sessions`, `converted_sessions`, `orders_from_converted_sessions`, `revenue_from_orders_from_converted_sessions`, `bounce_rate_pct`, `conversion_rate_pct`, `revenue_per_session`

---

## METRIC 4 — CAMPAIGN ROI

**Why It Matters:** CAC and email funnels measure efficiency at a channel or campaign level. ROI is the final word on whether a campaign was worth running at all. A campaign that spent ₹50,000 and attributed ₹200,000 in revenue has a 300% ROI. One that spent ₹50,000 and attributed ₹30,000 destroyed value. This is what the CMO presents to the CFO when justifying the marketing budget — and what gets campaigns renewed or cut.

**Key Columns Explained:**
- `revenue_attributed` — total order revenue from customers who clicked a campaign touchpoint and placed an order within 7 days
- `roi` — (attributed_revenue - total_spend) / total_spend × 100. Positive = campaign made money. Negative = campaign lost money.
- `customers_touched` — total reach of the campaign across all event types (sent, impression, clicked)
- `number_of_conversions` — unique customers who both engaged with the campaign and placed an order within the attribution window

**Implementation Note:** `c2` uses a `RIGHT JOIN` from orders to `marketing_events` to ensure every campaign appears even if it drove zero orders — the right join preserves all `marketing_events` rows regardless of order matches. The final `LEFT JOIN` from `c1` to `c2` brings spend and conversions together cleanly. `COALESCE` handles campaigns with zero attributed revenue.

**Attribution Limitation:** A customer who clicked multiple campaigns within 7 days will have their order attributed to all of those campaigns simultaneously. This is last-touch attribution without deduplication — the same order can appear in multiple campaigns' ROI figures. This is a known limitation standard in most marketing analytics tools. A deduplicated model would require selecting the single most recent click per order before attribution.

**Key Output Columns:** `campaign_name`, `revenue_attributed`, `roi`, `customers_touched`, `number_of_conversions`

---

## SQL Concepts Demonstrated

| Concept | Where Used |
|---------|-----------|
| Multi-CTE architecture | Metrics 1, 4 |
| `CASE WHEN` channel mapping across mismatched schema columns | Metric 1 |
| `LEFT JOIN` with compound ON conditions for time-window attribution | Metric 2 |
| Funnel counts in a single pass using conditional aggregation | Metric 2 |
| `COUNT(DISTINCT ...)` for unique clicker deduplication | Metric 2 |
| Session-level join (`session_id`) for precise attribution | Metric 3 |
| `RIGHT JOIN` to preserve all campaign rows regardless of order matches | Metric 4 |
| `COALESCE` for zero-value campaigns | Metrics 2, 4 |
| ROI formula implementation | Metric 4 |
| `NULLIF` for safe division throughout | All metrics |

---

## Files

| File | Description |
|------|-------------|
| `queries.sql` | All 4 queries with full business context comments |

---

## Database

CartIQ Ecommerce Platform — PostgreSQL 15  
Seed Data: `schema/create_tables_and_seed.sql`  
Tables Used: `marketing_events`, `customers`, `orders`, `customer_sessions`
