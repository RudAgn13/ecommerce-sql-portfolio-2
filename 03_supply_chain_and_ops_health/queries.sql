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
select
	r.return_reason,
  	c.parent_category,
    count(c.parent_category) over (partition by c.parent_category) number_of_return_in_category,
    -- or sum(count(r.return_id)) over (partition by c.parent_category) as number_of_return_in_category, claude tell me if this is better
    count(r.return_id) total_returns,
    sum(r.refund_amount) total_refund_value,
    round(avg(r.return_resolved_at::date-r.return_requested_at::date),2) avg_days_to_resolve,
    count(case when r.seller_fault=true then r.return_id else null end) seller_fault_returns,
    count(case when r.refund_status='rejected' then r.return_id else null end) rejected_refunds,
    round(sum(r.refund_amount)/nullif(count(r.return_id),0),2) avg_refund_amount_per_return,
    round(100.0*count(case when r.seller_fault=true then r.return_id else null end)/count(r.return_id),2) sellers_fault_return_pct
from returns r
join orders o on r.order_id = o.order_id
join order_items oi on o.order_id = oi.order_id
join products p on oi.product_id = p.product_id
join categories c on p.category_id = c.category_id
group by r.return_reason, c.parent_category;

-- METRIC 4: PAYMENT FAILURE RATE BY METHOD & GATEWAY

-- METRIC 5: FULFILLMENT FUNNEL BY MONTH

-- METRIC 6: COD VS. PREPAID ORDER ANALYSIS
