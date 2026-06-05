--METRIC 1: Monthly GMV vs Net Revenue vs Realized Revenue
select
	date_trunc('month', o.order_date) order_month,
    sum(o.gross_amount) gross_merchandise_value,
    sum(o.discount_amount) total_discounts,
    sum(o.net_amount) net_revenue,
    sum(case when o.order_status in ('cancelled','returned') then o.net_amount else 0 end) revenue_lost,
    sum(o.net_amount) - sum(case when o.order_status in ('cancelled','returned') then o.net_amount else 0 end) realized_revenue,
    round(100.0*sum(o.discount_amount)/nullif(sum(o.gross_amount)),2) discount_rate_pct,
    round(100.0*sum(case when o.order_status in ('cancelled','returned') then o.net_amount else 0 end)/nullif(sum(o.net_amount)),2) leakage_rate_pct,
    count(distinct o.order_id) total_orders,
    count(distinct case when o.order_status='cancelled' then o.order_id else null end) cancelled_count,
    count(distinct case when o.order_status='returned' then o.order_id else null end) returned_count,
    round(sum(case when o.order_status='delivered' then o.net_amount else 0 end)/nullif(count(distinct case when o.order_status='delivered' then o.order_id else null end),0),2) aov
from orders o
group by date_trunc('month', o.order_date)
order by order_month;

--METRIC 2: Contribution Margin by Category
select
	ca.parent_category,
    ca.category_name,
    count(distinct oi.order_id) total_delivered_orders,
    sum(oi.line_total) gross_category_revenue,
    sum(oi.quantity*p.cost_price) total_cogs,
    sum(case when oi.is_returned=true then oi.line_total else 0 end) return_value,
    round(sum(oi.line_total*ca.commission_rate),2) platform_commission,
    --platforms have to pay commission for all order status, because txn takes place
    sum(oi.line_total)-sum(oi.quantity*p.cost_price)-sum(case when oi.is_returned=true then oi.line_total else 0 end) gross_profit,
    round(100.0*(sum(oi.line_total)-sum(oi.quantity*p.cost_price)-sum(case when oi.is_returned=true then oi.line_total else 0 end))/nullif(sum(oi.line_total),0),2) gross_profit_pct,
    round(sum(oi.line_total*ca.commission_rate)-sum(case when oi.is_returned=true then oi.line_total else 0 end),2) net_platform_take
from categories ca
join products p on ca.category_id = p.category_id
join order_items oi on p.product_id = oi.product_id
join orders o on oi.order_id = o.order_id
where o.order_status = 'delivered'
group by ca.parent_category, ca.category_name
order by gross_profit desc;

--METRIC 3: Discount Depth Analysis

--METRIC 4: Month-over-Month Growth with Year-over-Year Comparison

--METRIC 5: Revenue Concentration — Top 20% Customers
