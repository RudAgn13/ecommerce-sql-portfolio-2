-- ============================================================
-- Project 05: Seller & Category Performance
-- Database: CartIQ (PostgreSQL 15)
-- ============================================================
-- What This Project Answers:
--   Marketplace health lives and dies with seller quality.
--   A platform where top sellers are high-quality and compliant
--   grows; one where bad sellers dominate with poor products
--   and high returns collapses. This project builds the analytical
--   framework to grade sellers, rank them within their tiers,
--   identify fast and slow-moving categories, measure customer
--   loyalty by category, and track how new vs established sellers
--   contribute to GMV over time.
-- ============================================================


-- ============================================================
-- METRIC 1: SELLER SCORECARD
-- ============================================================
-- Business Context:
--   Seller account managers use scorecards to make tier promotion
--   decisions, enforce penalties, and prioritise which sellers
--   to feature in campaigns. Without a structured score, decisions
--   are subjective and inconsistent. This scorecard weights four
--   dimensions that directly impact customer experience and platform
--   economics: delivery reliability (OTDR), return rate, revenue
--   contribution (GMV), and fulfilment speed.
--
-- Composite Score Weights:
--   OTDR          → 30 pts max  (customer satisfaction driver)
--   Return Rate   → 30 pts max  (direct cost to platform)
--   GMV           → 20 pts max  (revenue contribution)
--   Delivery Speed → 20 pts max  (customer experience)
--   Total         → 100 pts max
--
-- What It Tells You:
--   - composite_score: a single comparable number per seller
--     enabling tier review, penalty enforcement, and account
--     manager prioritisation.
--   - performance_quartile: NTILE(4) partitions sellers into
--     four equal groups — Q1 = top performers, Q4 = bottom.
--     Sellers in Q4 for two consecutive periods are candidates
--     for deactivation review.
--   - dispatch_to_delivery_days: actual delivery window minus
--     the seller's declared avg_dispatch_days, approximating
--     courier-only transit time. This is a workaround because
--     the schema does not store a discrete ship date — it is
--     the closest available proxy given the data.
--
-- Key Output Columns:
--   seller_id, total_delivered_orders, gross_merchandise_value,
--   otdr_pct, return_rate_pct, dispatch_to_delivery_days,
--   composite_score, performance_quartile
-- ============================================================

with attrib as (
select
	s.seller_id,
    count(distinct o.order_id) total_delivered_orders,
    sum(oi.line_total) gross_merchandise_value,
    round(100.0*count(distinct case when o.actual_delivery<=o.expected_delivery then o.order_id end)/count(distinct o.order_id),2) otdr_pct,
    round(100.0*count(r.return_id)/count(oi.item_id),2) return_rate_pct,
    round(avg(o.actual_delivery::date - o.order_date::date - s.avg_dispatch_days)::decimal,2) dispatch_to_delivery_days
	--doing this because we do not have a specific column for shipping date. this is the closest we can get to it as per data.
from sellers s
left join order_items oi on s.seller_id = oi.seller_id
left join orders o on oi.order_id = o.order_id
left join returns r on oi.item_id = r.item_id
where o.order_status='delivered'
group by s.seller_id
order by s.seller_id
), comp as (
select
	*,
	(case
    	when otdr_pct>=95 then 30
        when otdr_pct>=85 then 20
        else 10
    end +
    case
    	when return_rate_pct<=2 then 30
        when return_rate_pct<=5 then 20
        else 5
    end +
    case
    	when gross_merchandise_value>=500000 then 20
        when gross_merchandise_value>=100000 then 15
        else 5
    end +
    case
    	when dispatch_to_delivery_days<=4 then 20
        when dispatch_to_delivery_days<=7 then 10
        else 5
    end) composite_score
from attrib
)
select
	*,
    ntile(4) over (order by composite_score desc) performance_quartile
from comp;


-- ============================================================
-- METRIC 2: TOP AND BOTTOM 3 SELLERS BY GMV
-- ============================================================
-- Business Context:
--   Within each tier, the spread between top and bottom performers
--   reveals the health of that tier. A wide GMV gap between top
--   and bottom elite sellers signals that the tier definition is
--   too broad. Account managers use this to celebrate and learn
--   from top performers, and to put bottom performers on structured
--   improvement plans before considering deactivation.
--   Comparing top_ranks and bottom_ranks side by side in one query
--   gives a complete picture of each tier's performance distribution.
--
-- What It Tells You:
--   - top_ranks <= 3: the three highest GMV sellers within each tier.
--   - bottom_ranks <= 3: the three lowest GMV sellers within each tier.
--   - RANK() is used instead of ROW_NUMBER() so that sellers with
--     identical GMV receive the same rank — ties are surfaced rather
--     than arbitrarily broken.
--
-- Note:
--   Inner joins are intentional here to exclude sellers with zero
--   delivered orders. A seller that has never fulfilled a delivered
--   order has no meaningful GMV rank and should not appear in this
--   analysis.
--
-- Key Output Columns:
--   seller_tier, seller_id, gmv, top_ranks, bottom_ranks
-- ============================================================

with seller_gmv as (
select
	s.seller_tier,
    s.seller_id,
    sum(oi.line_total) gmv
from sellers s
join order_items oi on s.seller_id = oi.seller_id
--inner join intentional, to drop sellers with 0 delivered items/orders
join orders o on oi.order_id = o.order_id
where o.order_status = 'delivered'
group by s.seller_tier, s.seller_id
)
, ranked_sellers as (
select
	seller_tier,
    seller_id,
    gmv,
    rank() over (partition by seller_tier order by gmv desc) top_ranks,
    rank() over (partition by seller_tier order by gmv asc) bottom_ranks
from seller_gmv
)
select
    seller_tier,
    seller_id,
    gmv,
    top_ranks,
    bottom_ranks
from ranked_sellers
where top_ranks <= 3 or bottom_ranks <= 3
order by seller_tier, gmv desc;


-- ============================================================
-- METRIC 3: CATEGORY VELOCITY — FAST/SLOW MOVING
-- ============================================================
-- Business Context:
--   Slow-moving inventory is working capital being destroyed.
--   Every unit that sits unsold represents procurement cost,
--   storage cost, and opportunity cost. This analysis tells the
--   category team which products to discount or liquidate (slow
--   movers) and which to restock faster (top movers). GMV tied
--   up in slow movers is the number that gets attention in a
--   finance review — it converts velocity into a rupee figure.
--
-- What It Tells You:
--   - top_movers: products in the top quartile of units sold
--     within their category — these drive category GMV.
--   - slow_movers: products in the bottom quartile — candidates
--     for promotional clearance or delisting.
--   - gmv_tied_up_in_slow_movers: total revenue generated by
--     slow movers. Counterintuitively, a high number here means
--     the slow movers are high-priced items — a different problem
--     from low-priced items that simply don't sell.
--   - avg_days_since_last_sale: recency of sales activity across
--     the category as a whole.
--
-- Note on Recency Anchor:
--   Uses MAX(order_date) from the orders table instead of
--   CURRENT_DATE for consistency with the seed dataset.
--
-- Note on COALESCE for Unsold Products:
--   Products with no delivered orders have NULL as their last
--   order date. COALESCE defaults these to MAX(order_date),
--   giving them days_since_last_sale = 0. This prevents NULL
--   from polluting the velocity analysis and keeps unsold
--   products from being misclassified as recently active.
--
-- Key Output Columns:
--   category_id, total_products, top_movers, slow_movers,
--   gmv_tied_up_in_slow_movers, avg_days_since_last_sale
-- ============================================================

with product_analytics as (
select
	p.product_id,
    p.category_id,
    coalesce(sum(oi.quantity),0) units_sold,
  	sum(oi.line_total) total_revenue,
    (select max(order_date)::date from orders) - coalesce(max(order_date),(select max(order_date)::date from orders))::date days_since_last_sale,
    --coalesce here ensures that people who have NOT sold anything say days_since_last_sale = 0, which helps to not pollute the velocity analysis
	ntile(4) over (partition by p.category_id order by coalesce(sum(oi.quantity),0) desc) quartile
from products p
left join order_items oi on p.product_id = oi.product_id
left join orders o on oi.order_id = o.order_id and o.order_status = 'delivered'
group by p.product_id, p.category_id
)
select
	category_id,
    count(product_id) total_products,
    count(case when quartile=1 then quartile end) top_movers,
    count(case when quartile=4 then quartile end) slow_movers,
    sum(case when quartile=4 then total_revenue else 0 end) gmv_tied_up_in_slow_movers,
    round(avg(days_since_last_sale),2) avg_days_since_last_sale
from product_analytics
group by category_id
order by gmv_tied_up_in_slow_movers desc;


-- ============================================================
-- METRIC 4: REPEAT PURCHASE RATE BY CATEGORY
-- ============================================================
-- Business Context:
--   Repeat purchase rate is one of the clearest signals of
--   category health. High repeat rate means customers trust
--   the category and keep coming back — loyalty and product-market
--   fit. Low repeat rate means one of two things: either the
--   category is inherently one-time-purchase (furniture, large
--   appliances) or there is a quality or trust problem driving
--   customers away after one bad experience. Knowing which is
--   which is critical before taking any action — you would not
--   run a re-engagement campaign for furniture the same way
--   you would for skincare.
--
-- What It Tells You:
--   - repeat_purchase_rate_pct: the primary health indicator.
--     Compare across categories to identify loyalty leaders
--     and laggards.
--   - avg_orders_per_buyer: how sticky is the category on average?
--     A category with 60% repeat rate but avg 2.1 orders per buyer
--     is different from one with 60% repeat rate and avg 5.8 orders.
--
-- Key Output Columns:
--   parent_category, total_unique_buyers, repeat_buyers,
--   repeat_purchase_rate_pct, avg_orders_per_buyer
-- ============================================================

with by_customer as (
select
	c.parent_category,
    o.customer_id,
    count(distinct o.order_id) orders_placed
from categories c
join products p on c.category_id = p.category_id
join order_items oi on p.product_id = oi.product_id
join orders o on oi.order_id = o.order_id
where o.order_status = 'delivered'
group by c.parent_category, o.customer_id
)
select
	parent_category,
    count(customer_id) total_unique_buyers,
    count(case when orders_placed>=2 then 1 end) repeat_buyers,
	round(100.0*count(case when orders_placed>=2 then 1 end)/nullif(count(customer_id),0),2) repeat_purchase_rate_pct,
    round(avg(orders_placed),2) avg_orders_per_buyer
from by_customer
group by parent_category;


-- ============================================================
-- METRIC 5: NEW VS ESTABLISHED SELLER GMV CONTRIBUTION OVER TIME
-- ============================================================
-- Business Context:
--   A healthy marketplace sees established sellers growing steadily
--   while new sellers consistently onboard and contribute. If GMV
--   is entirely concentrated in sellers onboarded 2+ years ago,
--   the platform is stagnating — no fresh supply, no new competition,
--   and high dependency on a small group of long-term sellers.
--   Tracking the new vs established GMV split monthly tells leadership
--   whether the seller acquisition funnel is working.
--
-- What It Tells You:
--   - gmv_by_bucket: absolute GMV contribution from new vs established
--     sellers each month.
--   - gmv_pct: share of total monthly GMV from each bucket. A healthy
--     platform typically sees new sellers contribute 15–25% of GMV,
--     growing over time as they mature into established sellers.
--   - sellers_by_bucket: how many unique sellers in each bucket are
--     actively contributing GMV each month?
--
-- Bucket Definition:
--   New seller        → onboarded within 18 months of the database
--                       max order date. 18 months is chosen to capture
--                       sellers still in their growth phase on CartIQ.
--   Established seller → onboarded more than 18 months before max order date.
--
-- Note on Recency Anchor:
--   Gap is calculated using the database MAX(order_date) as "today"
--   for consistency with the 2024 seed dataset. In production,
--   replace with CURRENT_DATE.
--
-- Implementation Note on Nested Window Function:
--   gmv_pct uses SUM(SUM(oi.line_total)) OVER (PARTITION BY order_month).
--   The inner SUM(oi.line_total) aggregates to bucket + month level
--   via GROUP BY. The outer SUM(...) OVER then totals across buckets
--   within the same month via the window partition, giving the monthly
--   total against which the bucket share is calculated.
--
-- Key Output Columns:
--   buckets, order_month, gmv_by_bucket, gmv_pct, sellers_by_bucket
-- ============================================================

with seller_onboarding as (
select
	s.seller_id,
    date_trunc('month', s.onboarded_at)::date onboarding_date,
  	
    extract(year from (select max(o.order_date) from orders o)) * 12 - extract(year from s.onboarded_at) * 12 + extract(month from (select max(o.order_date) from orders o)) - extract(month from s.onboarded_at) gap
from sellers s
), seller_buckets as (
select
	seller_id,
  	
    case
    	when gap<18 then 'new'
		--18 months to see different things in data.
        else 'established'
    end buckets
from seller_onboarding
)
select
	sb.buckets,
    date_trunc('month', o.order_date)::date order_month,
	sum(oi.line_total) gmv_by_bucket,
    round(100.0*sum(oi.line_total)/nullif(sum(sum(oi.line_total)) over (partition by date_trunc('month', o.order_date)), 0), 2) gmv_pct,
    --inner sum(oi.line_total) uses group by bucket and order_month to find the gmv for said month and bucket of seller. further, the window function adds these and totals the same for each order_month as mentioned in partition by.
    count(distinct sb.seller_id) sellers_by_bucket
from seller_buckets sb
join products p on sb.seller_id = p.seller_id
join order_items oi on p.product_id = oi.product_id
join orders o on oi.order_id = o.order_id
where o.order_status = 'delivered'
group by sb.buckets, date_trunc('month', o.order_date)
order by order_month;
