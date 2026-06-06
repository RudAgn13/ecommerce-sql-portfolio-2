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
select
	p.payment_gateway,
	p.payment_method,
    count(p.payment_id) total_payment_attempts,
    count(case when p.payment_status='success' then p.payment_id else null end) successful_payments,
    count(case when p.payment_status='failed' then p.payment_id else null end) failed_payments,
    count(case when p.payment_status='refunded' then p.payment_id else null end) refunded_payments,
    sum(case when p.payment_status='failed' then p.amount else 0 end) failed_gmv,
    round(100.0*count(case when p.payment_status='failed' then p.payment_id else null end)/count(p.payment_id),2) failure_rate_pct,
    mode() within group (order by p.failure_reason) most_common_failure_reason
from payments p
group by p.payment_method, p.payment_gateway
order by failure_rate_pct desc;

-- METRIC 5: FULFILLMENT FUNNEL BY MONTH
select
	date_trunc('month', o.order_date)::date order_month,
    count(o.order_id) placed_orders,
    count(case when o.order_status<>'cancelled' then o.order_id else null end) confirmed_orders,
    count(case when o.order_status in ('shipped','delivered', 'returned') then o.order_id else null end) shipped_orders,
    count(case when o.order_status in ('delivered', 'returned') then o.order_id else null end) delivered_orders,
    count(case when o.order_status in ('returned') then o.order_id else null end) returned_orders,
    count(case when o.order_status in ('cancelled') then o.order_id else null end) cancelled_orders,
    round(100.0*count(case when o.order_status<>'cancelled' then o.order_id else null end)/nullif(count(o.order_id),0),2) confirmation_rate_pct,
    round(100.0*count(case when o.order_status in ('delivered', 'returned') then o.order_id else null end)/nullif(count(o.order_id),0),2) delivered_rate_pct,
    round(100.0*count(case when o.order_status in ('returned') then o.order_id else null end)/nullif(count(case when o.order_status in ('delivered', 'returned') then o.order_id else null end),0),2) returned_rate_pct,
    round(100.0*count(case when o.order_status in ('cancelled') then o.order_id else null end)/nullif(count(o.order_id),0),2) cancellation_rate_pct
from orders o
group by date_trunc('month', o.order_date)
order by order_month;

-- METRIC 6: COD VS. PREPAID ORDER ANALYSIS
