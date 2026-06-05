-- TARGET DATABASE: PostgreSQL v15
-- Project 1: Customer Lifecycle Analysis

-- METRIC 1: CUSTOMER ORDER SUMMARY
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

-- METRIC 2: AVERAGE ORDER VALUE (AOV) BY CUSTOMER TIER
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
