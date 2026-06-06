-- METRIC 1: ON-TIME DELIVERY RATE (OTDR) BY STATE
select
	o.shipping_state,
    count(o.order_id) total_orders,
    count(case when o.actual_delivery <= o.expected_delivery then o.order_id else null end) on_time_deliveries,
    count(case when o.actual_delivery > o.expected_delivery then o.order_id else null end) late_deliveries,
    round(100.0*count(case when o.actual_delivery <= o.expected_delivery then o.order_id else null end)/count(o.order_id),2) otdr_pct,
    round(avg(case when o.actual_delivery > o.expected_delivery then o.actual_delivery-o.expected_delivery else null end),2) avg_days_late,
    max(case when o.actual_delivery > o.expected_delivery then o.actual_delivery-o.expected_delivery else null end) max_days_late
from orders o
where o.order_status = 'delivered'
group by o.shipping_state;

-- METRIC 2: OTDR BY SELLER TIER
select
	s.seller_tier,
    round(avg(s.avg_dispatch_days),2) average_dispatch_days,
    count(distinct o.order_id) total_orders,
    count(distinct case when o.actual_delivery <= o.expected_delivery then o.order_id else null end) on_time_deliveries,
    count(distinct case when o.actual_delivery > o.expected_delivery then o.order_id else null end) late_deliveries,
    round(100.0*count(distinct case when o.actual_delivery <= o.expected_delivery then o.order_id else null end)/count(o.order_id),2) otdr_pct,
    round(avg(case when o.actual_delivery > o.expected_delivery then o.actual_delivery-o.expected_delivery else null end),2) avg_days_late,
    max(case when o.actual_delivery > o.expected_delivery then o.actual_delivery-o.expected_delivery else null end) max_days_late
from sellers s
join order_items oi on s.seller_id = oi.seller_id
join orders o on oi.order_id = o.order_id
where o.order_status = 'delivered'
group by s.seller_tier;

-- METRIC 3: RETURN RATE & ROOT CAUSE ANALYSIS

-- METRIC 4: PAYMENT FAILURE RATE BY METHOD & GATEWAY

-- METRIC 5: FULFILLMENT FUNNEL BY MONTH

-- METRIC 6: COD VS. PREPAID ORDER ANALYSIS
