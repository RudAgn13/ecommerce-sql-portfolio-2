-- ============================================================
-- Project 01: Customer Lifecycle Analysis
-- Database: CartIQ (PostgreSQL 15)
-- ============================================================
-- What This Project Answers:
--   Who are our best customers? Who is about to leave?
--   What does it cost to acquire them and how long do they stick around?
--   These are the first questions any Head of Growth asks.
--   Without this foundation, marketing is flying blind.
-- ============================================================


-- ============================================================
-- METRIC 1: CUSTOMER ORDER SUMMARY
-- ============================================================
-- Business Context:
--   This is the foundation query for the entire project.
--   Before any segmentation or scoring, you need a clean
--   per-customer view of behaviour. Every subsequent metric
--   in this project builds on top of this shape.
--
-- What It Tells You:
--   How many times has each customer ordered, how much have
--   they spent in total, and how long have they been active?
--   Lifespan (days between first and last order) is a core
--   input into Lifetime Value calculations.
-- ============================================================

select
	c.customer_id,
    count(distinct o.order_id) delivered_orders,
    sum(o.net_amount) total_spend,
    min(o.order_date) first_order_date,
    max(o.order_date) last_order_date,
    max(o.order_date)::date-min(o.order_date)::date lifespan
from customers c
join orders o on c.customer_id = o.customer_id
where o.order_status = 'delivered'
group by c.customer_id;


-- ============================================================
-- METRIC 2: AVERAGE ORDER VALUE (AOV) BY CUSTOMER TIER
-- ============================================================
-- Business Context:
--   AOV is one of the three levers of revenue growth
--   (the other two being acquisition and purchase frequency).
--   Splitting by tier tells you whether your loyalty programme
--   is actually driving higher spend. If Platinum customers
--   have the same AOV as Bronze, the tier structure isn't
--   working — customers are being rewarded without spending more.
--
-- What It Tells You:
--   Which tiers spend more per order, and which tiers have
--   higher purchase frequency. AOV also informs the free
--   shipping threshold — set it just above the tier's AOV
--   to nudge customers to add one more item.
--
-- Note:
--   Only tiers with at least one delivered order will appear.
--   Tiers with zero delivered orders are excluded by the join.
-- ============================================================

select
	c.tier,
    count(distinct c.customer_id) customers_in_tier,
    count(distinct o.order_id) total_delivered_orders,
    sum(o.net_amount) total_revenue,
    round(sum(o.net_amount)/nullif(count(distinct o.order_id),0),2) AOV,
    round(1.0*count(distinct o.order_id)/nullif(count(distinct c.customer_id),0),2) avg_orders_per_customer
from customers c
join orders o on c.customer_id = o.customer_id
where o.order_status = 'delivered'
group by c.tier
order by aov desc;


-- ============================================================
-- METRIC 3: RFM SEGMENTATION
-- ============================================================
-- Business Context:
--   RFM (Recency, Frequency, Monetary) is the industry standard
--   for customer segmentation because it is directly actionable.
--   The output maps 1:1 to CRM playbooks:
--     Champions      → Loyalty perks, early access to sales
--     Loyal          → Upsell and cross-sell campaigns
--     New Customer   → Onboarding flow, category discovery
--     At Risk        → Win-back discount, re-engagement email
--     Lost           → Sunset or last-chance offer
--     Needs Attention → Lighter nudge, preference survey
--
-- How It Works:
--   Each customer is scored 1–5 on Recency, Frequency, and
--   Monetary value using NTILE(5) window functions. The scores
--   are then combined into a segment label using business rules.
--
-- Note on Recency Anchor:
--   Recency uses MAX(order_date) from the orders table instead
--   of CURRENT_DATE. This is intentional — all seed data is from
--   2024, so using CURRENT_DATE would classify every customer as
--   churned and make the segmentation meaningless. In a production
--   environment, replace with CURRENT_DATE.
-- ============================================================

with RFM as
(
select
	o.customer_id,
    (select max(order_date)::date from orders) - max(o.order_date)::date recency,
	-- using (select max(order_date)::date from orders) instead of current_date for static and sensible querying
    count(distinct o.order_id) frequency,
    sum(o.net_amount) monetary
from orders o
where o.order_status = 'delivered'
group by o.customer_id
)
, RFM2 as
(
select
  	customer_id,
	ntile(5) over (order by recency desc) r,
    ntile(5) over (order by frequency asc) f,
    ntile(5) over (order by monetary asc) m
from RFM
)
, final as
(
select
	t1.customer_id,
	case
    	when t2.r>=4 and t2.f>=4 then'Champion'
        when t2.r>=3 and t2.f>=3 then 'Loyal'
        when t2.r>=4 and t2.f<=2 then 'New Customer'
        when t2.r<=2 and t2.f>=3 then 'At Risk'
        when t2.r=1 and t2.f=1 then 'Lost'
        else 'Needs Attention'
    end segment,
    t1.recency,
    t1.frequency,
    t1.monetary
from RFM t1
join RFM2 t2 on t1.customer_id = t2.customer_id
)
select
	segment,
    count(customer_id) customers_by_segment,
    round(avg(recency),2) avg_recency,
    round(avg(frequency),2) avg_frequency,
    round(avg(monetary),2) avg_monetary
from final
group by segment;


-- ============================================================
-- METRIC 4: COHORT RETENTION — MONTH 0 TO MONTH 6
-- ============================================================
-- Business Context:
--   Retention curves are the single most important signal of
--   product health. A curve that flattens at ~30% by Month 3
--   means you have a loyal core. One that drops to 5% by
--   Month 2 means customers are one-and-done — a product or
--   expectation problem, not a marketing problem.
--   This is the chart that goes into every quarterly business review.
--
-- How It Works:
--   Each customer is assigned a cohort_month (the month of their
--   first delivered order). For each subsequent month they place
--   another delivered order, they count as "retained". The
--   retention % is active customers in Month N divided by the
--   original cohort size (Month 0).
--
-- Implementation Note:
--   cohort_month is derived using MIN(order_date) as a window
--   function (PARTITION BY customer_id) inside the base CTE.
--   This avoids a separate subquery join and is more efficient.
--   Cohort size is recovered using MAX(CASE WHEN months_since_first = 0)
--   as a window function — no additional join needed.
-- ============================================================

with base as 
(
select distinct
    o.customer_id,
    min(date_trunc('month', o.order_date)) over (partition by o.customer_id) as cohort_month,
    date_trunc('month', o.order_date) as activity_month
from orders o
where o.order_status = 'delivered'
)
, monthly_counts as 
(
select 
    cohort_month,
    ((extract(year from age(activity_month, cohort_month)) * 12) + extract(month from age(activity_month, cohort_month)))::int as months_since_first,
    count(distinct customer_id) as active_customers
from base
group by cohort_month, months_since_first
)
select 
    cohort_month,
    max(case when months_since_first = 0 then active_customers end) over (partition by cohort_month) as total_customers_in_cohort,
    months_since_first,
    active_customers,
    round(100.0 * active_customers / max(case when months_since_first = 0 then active_customers end) over (partition by cohort_month), 2) as retention_pct
from monthly_counts
where months_since_first between 0 and 6
order by cohort_month, months_since_first;


-- ============================================================
-- METRIC 5: CHURN RISK FLAGGING
-- ============================================================
-- Business Context:
--   Identifying customers before they fully churn gives the
--   CRM team a window to intervene — a targeted discount,
--   a personalised recommendation, or a re-engagement email.
--   The 60-day threshold is where most ecom platforms see
--   a meaningful drop in recovery rate. Beyond 180 days,
--   reactivation cost typically exceeds expected revenue.
--
-- Segment Definitions:
--   Early Churn Risk (60–89 days)  → Intervene now, highest recovery rate
--   Churning (90–179 days)         → Last-chance win-back offer
--   Churned (180+ days)            → Sunset or high-value exception treatment
--
-- What It Tells You:
--   Sorted by total_spend descending so the highest-value
--   at-risk customers surface first — these are the ones
--   worth spending budget to recover.
--
-- Note on Recency Anchor:
--   Same as Metric 3 — uses MAX(order_date) as the reference
--   point instead of CURRENT_DATE to keep results meaningful
--   with the 2024 seed dataset. Replace with CURRENT_DATE in
--   a production environment.
--
-- Note on Bucket NULLs:
--   Customers with days_since_last_order < 60 are excluded
--   by the HAVING clause, so the CASE WHEN will always match.
--   The ELSE NULL is included explicitly for defensive clarity.
-- ============================================================

select
	o.customer_id,
    (select max(order_date)::date from orders) - max(o.order_date)::date days_since_last_order,
    -- using (select max(order_date)::date from orders) instead of current_date for static and sensible querying
    case
    	when (select max(order_date)::date from orders) - max(o.order_date)::date >= 180 then 'Churned'
        when (select max(order_date)::date from orders) - max(o.order_date)::date between 90 and 179 then 'Churning'
        when (select max(order_date)::date from orders) - max(o.order_date)::date between 60 and 89 then 'Early Churn Risk'
        else null
    end bucket,
    c.tier,
    c.acquisition_channel,
    count(distinct o.order_id) total_orders,
    sum(o.net_amount) total_spend
from orders o
join customers c on o.customer_id = c.customer_id
where o.order_status = 'delivered'
group by o.customer_id, c.tier, c.acquisition_channel
having (select max(order_date)::date from orders) - max(o.order_date)::date >= 60
order by total_spend desc;


-- ============================================================
-- METRIC 6: LTV BY ACQUISITION CHANNEL
-- ============================================================
-- Business Context:
--   LTV (Lifetime Value) is the counterpart to CAC (Customer
--   Acquisition Cost). Without LTV you cannot evaluate whether
--   a channel is profitable. The LTV:CAC ratio is the core
--   metric for deciding how much to spend on each channel:
--     LTV:CAC > 3:1  → Healthy, consider scaling spend
--     LTV:CAC 1–3:1  → Marginal, optimise before scaling
--     LTV:CAC < 1:1  → Loss-making, reduce or cut channel
--
-- How LTV Is Computed:
--   computed_ltv = average_order_value × average_purchase_frequency
--                  × average_customer_lifespan (in years)
--   AOV is calculated as total channel revenue / total channel orders
--   (weighted average) rather than AVG of individual customer AOVs —
--   this avoids inflation from customers with a single large order.
--
-- Known Limitation:
--   Customers with only one delivered order have lifespan = 0 days,
--   which zeroes out computed_ltv even if they spent significantly.
--   A more robust approach for production is a time-boxed LTV
--   (e.g. revenue in first 12 months), which handles single-order
--   customers correctly. This formula is used here for interpretability.
-- ============================================================

with customer_summary as
(
select
	c.customer_id,
    c.acquisition_channel,
    sum(o.net_amount) customer_revenue,
    count(distinct o.order_id) customer_order_volume,
    round(1.0*(max(o.order_date)::date - min(o.order_date)::date)/365,2) customer_lifespan
from customers c
join orders o on c.customer_id = o.customer_id
where o.order_status = 'delivered'
group by c.customer_id, c.acquisition_channel
)
select
  	acquisition_channel,
  	count(distinct customer_id) cohort_size,
  	round(1.0*sum(customer_revenue)/sum(customer_order_volume),2) average_order_value,
  	round(avg(customer_order_volume),2) average_purchase_frequency,
  	round(avg(customer_lifespan),2) average_customer_lifespan,
    round(avg(customer_revenue),2) average_spend_per_customer,
  	round((1.0*sum(customer_revenue)/sum(customer_order_volume))*(avg(customer_order_volume))*(avg(customer_lifespan)),2) computed_ltv
from customer_summary
group by acquisition_channel
order by computed_ltv desc;
