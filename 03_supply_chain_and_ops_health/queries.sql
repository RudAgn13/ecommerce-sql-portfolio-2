-- ============================================================
-- Project 03: Supply Chain & Operations Health
-- Database: CartIQ (PostgreSQL 15)
-- ============================================================
-- What This Project Answers:
--   Operations analytics is underrepresented in most analyst
--   portfolios — yet ecommerce companies hire heavily for it.
--   Logistics performance directly impacts NPS, repeat purchase
--   rate, and unit economics. This project covers the metrics
--   a Head of Logistics and a Head of Finance review daily:
--   on-time delivery, return root cause, payment failure leakage,
--   fulfilment funnel drop-off, and COD vs prepaid health.
-- ============================================================


-- ============================================================
-- METRIC 1: ON-TIME DELIVERY RATE (OTDR) BY STATE
-- ============================================================
-- Business Context:
--   OTDR is the #1 logistics KPI. It directly affects customer
--   satisfaction, repeat purchase rate, and NPS. Courier SLA
--   negotiations, warehouse placement decisions, and last-mile
--   partner selection are all driven by state-level OTDR data.
--   A state with 60% OTDR is haemorrhaging customer trust —
--   and that trust loss shows up in retention metrics 30–60
--   days later, making it a leading indicator worth watching weekly.
--
-- What It Tells You:
--   - otdr_pct: which states have a systemic delivery problem?
--   - avg_days_late: how bad is it when deliveries are late?
--     a state with 80% OTDR but avg 10 days late is worse than
--     one with 75% OTDR but avg 1 day late.
--   - max_days_late: worst-case delay — useful for flagging
--     extreme outliers that inflate customer complaints.
--
-- Note:
--   avg_days_late and max_days_late use ELSE NULL so that
--   on-time deliveries are excluded from the late-day average.
--   Using ELSE 0 would incorrectly drag the average down.
--
-- Key Output Columns:
--   shipping_state, total_orders, on_time_deliveries,
--   late_deliveries, otdr_pct, avg_days_late, max_days_late
-- ============================================================

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


-- ============================================================
-- METRIC 2: OTDR BY SELLER TIER
-- ============================================================
-- Business Context:
--   When OTDR is poor, the question is: is this a courier problem
--   or a seller problem? Splitting by seller tier answers this.
--   If Elite sellers have 95% OTDR while New sellers have 55%,
--   the problem is seller dispatch speed — not the courier.
--   This distinction determines whether ops invests in courier
--   renegotiation or seller onboarding improvement.
--   avg_dispatch_days from the sellers table is included to
--   test whether self-reported dispatch speed correlates with
--   actual end-to-end delivery performance.
--
-- What It Tells You:
--   - otdr_pct by tier: does seller experience drive delivery quality?
--   - average_dispatch_days: do faster-dispatching seller tiers
--     actually achieve better OTDR, or is the bottleneck elsewhere?
--
-- Note on Denominator:
--   COUNT(DISTINCT o.order_id) is used throughout because the join
--   through order_items can produce duplicate order rows when an
--   order contains multiple items from the same seller tier.
--   Using COUNT without DISTINCT would inflate the denominator
--   and understate OTDR.
--
-- Key Output Columns:
--   seller_tier, average_dispatch_days, total_orders,
--   on_time_deliveries, late_deliveries, otdr_pct,
--   avg_days_late, max_days_late
-- ============================================================

select
	s.seller_tier,
    round(avg(s.avg_dispatch_days),2) average_dispatch_days,
    count(distinct o.order_id) total_orders,
    count(distinct case when o.actual_delivery <= o.expected_delivery then o.order_id else null end) on_time_deliveries,
    count(distinct case when o.actual_delivery > o.expected_delivery then o.order_id else null end) late_deliveries,
    round(100.0*count(distinct case when o.actual_delivery <= o.expected_delivery then o.order_id else null end)/count(distinct o.order_id),2) otdr_pct,
    round(avg(case when o.actual_delivery > o.expected_delivery then o.actual_delivery-o.expected_delivery else null end),2) avg_days_late,
    max(case when o.actual_delivery > o.expected_delivery then o.actual_delivery-o.expected_delivery else null end) max_days_late
from sellers s
join order_items oi on s.seller_id = oi.seller_id
join orders o on oi.order_id = o.order_id
where o.order_status = 'delivered'
group by s.seller_tier;


-- ============================================================
-- METRIC 3: RETURN RATE & ROOT CAUSE ANALYSIS
-- ============================================================
-- Business Context:
--   Returns are a profit killer. Every return triggers reverse
--   logistics costs, potential write-downs, and a refund liability.
--   Identifying root cause tells ops where to intervene:
--     damaged / wrong_item    → fulfilment or packaging failure (fix ops)
--     quality_issue           → seller-side problem (seller penalty or delisting)
--     size_mismatch           → product data problem (fix size guides)
--     changed_mind / late     → customer expectation problem (fix marketing)
--   Without root cause, every return looks the same and the fix
--   is always "reduce returns" with no actionable path.
--
-- What It Tells You:
--   - sellers_fault_return_pct: what % of returns in each reason/category
--     combination is attributable to seller failure vs platform/customer?
--   - avg_days_to_resolve: slow resolution erodes trust even after a bad
--     experience — a 10-day refund wait turns a returner into a churner.
--   - number_of_return_in_category: total returns within the parent
--     category across all return reasons, showing which categories
--     have the highest absolute return burden.
--
-- Implementation Note:
--   COUNT(c.parent_category) OVER (PARTITION BY c.parent_category)
--   is used for category-level return totals. The alternative
--   SUM(COUNT(r.return_id)) OVER (PARTITION BY c.parent_category)
--   is a nested aggregate that PostgreSQL does not allow without
--   wrapping in an outer query — the window function approach here
--   is cleaner and achieves the same result.
--   Join path: returns → orders → order_items → products → categories.
--   If an order has multiple items across categories, a single return
--   could appear in multiple category rows. This is an edge case
--   in this dataset but worth noting for production use.
--
-- Key Output Columns:
--   return_reason, parent_category, number_of_return_in_category,
--   total_returns, total_refund_value, avg_days_to_resolve,
--   seller_fault_returns, rejected_refunds,
--   avg_refund_amount_per_return, sellers_fault_return_pct
-- ============================================================

select
	r.return_reason,
  	c.parent_category,
    count(c.parent_category) over (partition by c.parent_category) number_of_return_in_category,
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


-- ============================================================
-- METRIC 4: PAYMENT FAILURE RATE BY METHOD & GATEWAY
-- ============================================================
-- Business Context:
--   Every payment failure is a lost order — the customer attempted
--   to buy, the transaction failed, and most won't retry. Payment
--   failure rates by gateway are used to negotiate SLAs with payment
--   partners and to decide which gateways to default-promote at
--   checkout. A gateway with 8% failure rate on high-AOV transactions
--   is costing more in lost revenue than it saves in processing fees.
--
-- What It Tells You:
--   - failure_rate_pct: which method and gateway combinations fail most?
--   - failed_gmv: the rupee value of orders lost to payment failure —
--     this converts a % into a number leadership responds to.
--   - most_common_failure_reason: MODE() surfaces the single most
--     frequent failure reason per gateway, enabling targeted fixes
--     (e.g. 'timeout' → infrastructure issue, 'card_declined' →
--     issuer-side problem that requires a different intervention).
--
-- Key Output Columns:
--   payment_gateway, payment_method, total_payment_attempts,
--   successful_payments, failed_payments, refunded_payments,
--   failed_gmv, failure_rate_pct, most_common_failure_reason
-- ============================================================

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


-- ============================================================
-- METRIC 5: FULFILLMENT FUNNEL BY MONTH
-- ============================================================
-- Business Context:
--   Not all orders placed become revenue. Each stage of the funnel
--   has a different failure mode and a different owner:
--     Placed → Confirmed drop-off  : cancellation at checkout (pricing or product data)
--     Confirmed → Shipped drop-off : seller dispatch failure (seller ops)
--     Shipped → Delivered drop-off : last-mile failure (courier ops)
--     Delivered → Returned         : product quality or expectation failure
--   Tracking this funnel monthly lets ops pinpoint which stage
--   is degrading and assign accountability to the right team.
--
-- What It Tells You:
--   - confirmation_rate_pct: how many orders survive past cancellation?
--   - delivered_rate_pct: of all orders placed, how many reach the customer?
--   - returned_rate_pct: of orders that arrived, how many came back?
--     Note — denominator is delivered + returned (orders that physically
--     reached the customer), not total placed. This is the correct
--     business definition of return rate.
--   - cancellation_rate_pct: direct measure of pre-fulfilment drop-off.
--
-- Key Output Columns:
--   order_month, placed_orders, confirmed_orders, shipped_orders,
--   delivered_orders, returned_orders, cancelled_orders,
--   confirmation_rate_pct, delivered_rate_pct,
--   returned_rate_pct, cancellation_rate_pct
-- ============================================================

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


-- ============================================================
-- METRIC 6: COD VS PREPAID ORDER ANALYSIS
-- ============================================================
-- Business Context:
--   COD (Cash on Delivery) orders carry significantly higher
--   operational costs than prepaid: failed delivery attempts,
--   return-to-origin (RTO) risk, and cash reconciliation overhead.
--   In India, COD can represent 40–60% of orders in tier-2 and
--   tier-3 cities despite being more expensive to fulfil.
--   This analysis tells ops where to restrict COD and push
--   prepaid incentives (discounts, loyalty points) to shift
--   the payment mix without losing the order.
--
-- What It Tells You:
--   - return_rate_pct: COD typically has 2–3x higher return rate
--     than prepaid because customers face no friction to reject delivery.
--   - payment_failure_pct: for prepaid, this measures gateway drop-off.
--     For COD, payment_status = 'failed' captures orders where cash
--     collection was unsuccessful at the door.
--   - net_amount_per_order: if COD AOV is significantly lower than
--     prepaid, it signals that high-value customers prefer prepaid —
--     reinforcing the case for prepaid incentives on large orders.
--
-- Note on LEFT JOIN:
--   The final join between payments_cte and returns_grouped uses
--   LEFT JOIN to guarantee both COD and prepaid always appear in
--   the output even if one payment type has zero returns and
--   returns_grouped produces no row for it. COALESCE then handles
--   the resulting NULL as 0.
--
-- Key Output Columns:
--   payment_method, order_count, total_net_amount,
--   net_amount_per_order, return_count, return_rate_pct,
--   payment_failure_count, payment_failure_pct
-- ============================================================

with payments_cte as (
    select
        (case when pay.payment_method='cod' then 'cod' else 'prepaid' end) payment_method,
        count(distinct pay.order_id) order_count,
        sum(pay.amount) total_net_amount,
        round(avg(pay.amount),2) net_amount_per_order,
        count(case when pay.payment_status='failed' then 1 end) payment_failure_count
    from payments pay
    group by (case when pay.payment_method='cod' then 'cod' else 'prepaid' end)
), returns_cte as (
    select
        order_id,
        count(return_id) number_of_returns
    from returns
    group by order_id
), returns_grouped as (
    select
        (case when pay.payment_method='cod' then 'cod' else 'prepaid' end) payment_method,
        sum(rc.number_of_returns) total_returns
    from payments pay
    join returns_cte rc on pay.order_id = rc.order_id
    group by (case when pay.payment_method='cod' then 'cod' else 'prepaid' end)
)
select
    pc.payment_method,
    pc.order_count,
    pc.total_net_amount,
    pc.net_amount_per_order,
    coalesce(rg.total_returns, 0) return_count,
    round(100.0*coalesce(rg.total_returns, 0) / nullif(pc.order_count, 0), 2) return_rate_pct,
    pc.payment_failure_count,
    round(100.0*pc.payment_failure_count / nullif(pc.order_count, 0), 2) payment_failure_pct
from payments_cte pc
left join returns_grouped rg on pc.payment_method = rg.payment_method;
