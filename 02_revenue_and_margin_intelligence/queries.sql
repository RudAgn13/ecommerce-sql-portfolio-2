--METRIC 1: Monthly GMV vs Net Revenue vs Realized Revenue
select
	date_trunc('month', o.order_date) order_month,
    sum(o.gross_amount) gross_merchandise_value,
    sum(o.discount_amount) total_discounts,
    sum(o.net_amount) net_revenue,
    sum(case when o.order_status in ('cancelled','returned') then o.net_amount else 0 end) revenue_lost,
    sum(o.net_amount) - sum(case when o.order_status in ('cancelled','returned') then o.net_amount else 0 end) realized_revenue,
    round(100.0*sum(o.discount_amount)/sum(o.gross_amount),2) discount_rate_pct,
    round(100.0*sum(case when o.order_status in ('cancelled','returned') then o.net_amount else 0 end)/sum(o.net_amount),2) leakage_rate_pct,
    count(distinct o.order_id) total_orders,
    count(distinct case when o.order_status='cancelled' then o.order_id else null end) cancelled_count,
    count(distinct case when o.order_status='returned' then o.order_id else null end) returned_count,
    round(sum(case when o.order_status='delivered' then o.net_amount else 0 end)/count(distinct case when o.order_status='delivered' then o.order_id else null end),2) aov
from orders o
group by date_trunc('month', o.order_date)
order by order_month;

--METRIC 2: Contribution Margin by Category

--METRIC 3: Discount Depth Analysis

--METRIC 4: Month-over-Month Growth with Year-over-Year Comparison

--METRIC 5: Revenue Concentration — Top 20% Customers
