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

-- METRIC 3: RECENCY FREQUENCY MONETARY (RFM) SEGMENTATION
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

-- METRIC 4: COHORT RETENTION - MONTH 0 TO MONTH 6
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

-- METRIC 5: CHURN RISK FLAGGING
select
	o.customer_id,
    (select max(order_date)::date from orders) - max(o.order_date)::date days_since_last_order,
    -- using (select max(order_date)::date from orders) instead of current_date for static and sensible querying
    case
    	when (select max(order_date)::date from orders) - max(o.order_date)::date >= 180 then 'Churned'
        when (select max(order_date)::date from orders) - max(o.order_date)::date between 90 and 179 then 'Churning'
        when (select max(order_date)::date from orders) - max(o.order_date)::date between 60 and 89 then 'Early Churn Risk'
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
