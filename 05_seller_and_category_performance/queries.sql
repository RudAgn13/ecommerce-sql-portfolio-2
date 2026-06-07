-- METRIC 1: SELLER SCORECARD
with attrib as (
select
	s.seller_id,
    count(distinct o.order_id) total_delivered_orders,
    sum(oi.line_total) gross_merchandise_value,
    round(100.0*count(distinct case when o.actual_delivery<=o.expected_delivery then o.order_id end)/count(distinct o.order_id),2) otdr_pct,
    round(100.0*count(r.return_id)/count(oi.item_id),2) return_rate_pct,
    round(avg(o.actual_delivery::date - o.order_date::date - s.avg_dispatch_days)::decimal,2) dispatch_to_delivery_days
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
    ntile(4) over (order by composite_score desc)
from comp;

-- METRIC 2: TOP AND BOTTOM 5 SELLERS BY GMV
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

-- METRIC 3: CATEGORY VELOCITY - FAST/SLOW MOVING
with product_analytics as (
select
	p.product_id,
    p.category_id,
    coalesce(sum(oi.quantity),0) units_sold,
  	sum(oi.line_total) total_revenue,
    current_date - max(order_date)::date days_since_last_sale,
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

-- METRIC 4: REPEAT PURCHASE RATE BY CATEGORY
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

--METRIC 5: NEW VS. RETURNING SELLER GMV CONTRIBUTION OVER TIME
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
