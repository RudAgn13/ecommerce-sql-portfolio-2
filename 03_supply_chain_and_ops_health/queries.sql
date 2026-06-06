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

-- METRIC 3: RETURN RATE & ROOT CAUSE ANALYSIS

-- METRIC 4: PAYMENT FAILURE RATE BY METHOD & GATEWAY

-- METRIC 5: FULFILLMENT FUNNEL BY MONTH

-- METRIC 6: COD VS. PREPAID ORDER ANALYSIS
