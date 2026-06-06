-- ============================================================
-- Project 02: Revenue & Margin Intelligence
-- Database: CartIQ (PostgreSQL 15)
-- ============================================================
-- What This Project Answers:
--   Revenue is vanity, margin is sanity. This project moves
--   beyond "how much did we sell" to "how much did we actually
--   make — and where are we losing it?" Every metric here maps
--   to a decision a Finance, Category, or Growth lead makes weekly.
-- ============================================================


-- ============================================================
-- METRIC 1: MONTHLY GMV VS NET REVENUE VS REALIZED REVENUE
-- ============================================================
-- Business Context:
--   These three numbers tell three different stories about the same period.
--   GMV (Gross Merchandise Value) is what gets announced in press releases.
--   Net Revenue removes discounts — what customers actually paid.
--   Realized Revenue removes cancellations and returns — what the business kept.
--   The gap between GMV and Realized Revenue is your leakage.
--   Tracking leakage rate % month-on-month tells you whether operations
--   are getting tighter or looser over time.
--
-- What It Tells You:
--   - discount_rate_pct: are promotions getting more aggressive?
--   - leakage_rate_pct: what % of revenue is being eroded by cancellations
--     and returns? rising leakage often signals a product quality or
--     seller fulfilment problem, not a demand problem.
--   - aov: computed only on delivered orders to reflect true transaction value.
--
-- Key Output Columns:
--   order_month, gross_merchandise_value, total_discounts, net_revenue,
--   revenue_lost, realized_revenue, discount_rate_pct, leakage_rate_pct,
--   total_orders, cancelled_count, returned_count, aov
-- ============================================================

select
	date_trunc('month', o.order_date) order_month,
    sum(o.gross_amount) gross_merchandise_value,
    sum(o.discount_amount) total_discounts,
    sum(o.net_amount) net_revenue,
    sum(case when o.order_status in ('cancelled','returned') then o.net_amount else 0 end) revenue_lost,
    sum(o.net_amount) - sum(case when o.order_status in ('cancelled','returned') then o.net_amount else 0 end) realized_revenue,
    round(100.0*sum(o.discount_amount)/nullif(sum(o.gross_amount),0),2) discount_rate_pct,
    round(100.0*sum(case when o.order_status in ('cancelled','returned') then o.net_amount else 0 end)/nullif(sum(o.net_amount),0),2) leakage_rate_pct,
    count(distinct o.order_id) total_orders,
    count(distinct case when o.order_status='cancelled' then o.order_id else null end) cancelled_count,
    count(distinct case when o.order_status='returned' then o.order_id else null end) returned_count,
    round(sum(case when o.order_status='delivered' then o.net_amount else 0 end)/nullif(count(distinct case when o.order_status='delivered' then o.order_id else null end),0),2) aov
from orders o
group by date_trunc('month', o.order_date)
order by order_month;


-- ============================================================
-- METRIC 2: CONTRIBUTION MARGIN BY CATEGORY
-- ============================================================
-- Business Context:
--   A category driving 30% of GMV at 2% gross margin is destroying value —
--   it consumes logistics, seller management, and customer support resources
--   without generating proportional profit. This is the query a Category Manager
--   runs every Monday to decide which categories to promote, reprice, or fix.
--   Gross margin % is the primary decision lever; net_platform_take shows
--   what CartIQ actually earns after absorbing return costs.
--
-- What It Tells You:
--   - gross_profit and gross_profit_pct: which categories are structurally
--     profitable vs which rely on volume to justify their existence.
--   - net_platform_take: commission earned minus return costs absorbed.
--     a negative net_platform_take means CartIQ is subsidising that category.
--   - return_value: high return value relative to revenue signals a quality
--     or expectation mismatch in that category.
--
-- Design Note:
--   Platform commission is calculated on all delivered order_items regardless
--   of return status. This reflects real marketplace economics — the transaction
--   fee is charged at point of sale, not reversed on return. Return costs are
--   then separately deducted to show net platform take.
--
-- Key Output Columns:
--   parent_category, category_name, total_delivered_orders,
--   gross_category_revenue, total_cogs, return_value, platform_commission,
--   gross_profit, gross_profit_pct, net_platform_take
-- ============================================================

select
	ca.parent_category,
    ca.category_name,
    count(distinct oi.order_id) total_delivered_orders,
    sum(oi.line_total) gross_category_revenue,
    sum(oi.quantity*p.cost_price) total_cogs,
    sum(case when oi.is_returned=true then oi.line_total else 0 end) return_value,
    round(sum(oi.line_total*ca.commission_rate),2) platform_commission,
    -- platforms have to pay commission for all order status, because txn takes place
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


-- ============================================================
-- METRIC 3: DISCOUNT DEPTH ANALYSIS
-- ============================================================
-- Business Context:
--   Heavy discounting inflates GMV but erodes margin and trains customers
--   to wait for sales before purchasing at full price. This query finds
--   the discount threshold beyond which orders become loss-making per line.
--   The output directly informs promotional guardrails — most ecom companies
--   set a floor below which sellers cannot discount without approval.
--
-- What It Tells You:
--   - avg_margin_pct by bucket: at what discount level does margin turn negative?
--   - total_gross_profit by bucket: where is the most profit being made or lost?
--   - avg_unit_price: average revenue per line item within each bucket.
--     note — if quantity > 1 on a line, this reflects average line value,
--     not strictly average price per unit. for this dataset, quantities are
--     predominantly 1, so the distinction is minimal.
--
-- Key Output Columns:
--   bucket, count, total_revenue, total_cogs, total_gross_profit,
--   avg_margin_pct, avg_unit_price
-- ============================================================

with bucketing as
(
select
	oi.item_id,
    oi.quantity*p.cost_price cogs,
    oi.line_total - oi.quantity*p.cost_price gross_profit,
    case 
        when oi.discount_pct = 0 then 'No Discount'
        when oi.discount_pct <= 0.10 then '1-10%'
        when oi.discount_pct <= 0.20 then '11-20%'
        when oi.discount_pct <= 0.30 then '21-30%'
        when oi.discount_pct <= 0.50 then '31-50%'
        else '50%+ Deep Discount'
    end bucket,
  	oi.line_total revenue
from order_items oi
join products p on oi.product_id = p.product_id
join orders o on oi.order_id = o.order_id
where o.order_status = 'delivered'
)
select
	b.bucket,
    count(b.item_id),
    sum(b.revenue) total_revenue,
    sum(b.cogs) total_cogs,
    sum(b.gross_profit) total_gross_profit,
    round(avg(b.gross_profit/nullif(b.revenue,0)),2) avg_margin_pct,
    round(sum(b.revenue)/count(b.item_id),2) avg_unit_price
from bucketing b
group by b.bucket
order by b.bucket;


-- ============================================================
-- METRIC 4: MONTH-OVER-MONTH GROWTH WITH YEAR-OVER-YEAR COMPARISON
-- ============================================================
-- Business Context:
--   A 20% MoM revenue jump in October is meaningless without context —
--   if last year it was +40% in October driven by Diwali, you are actually
--   underperforming. YoY comparison normalises for seasonality and gives a
--   true read on whether the business is growing or just riding a calendar event.
--   This is the first chart in any monthly business review deck.
--
-- What It Tells You:
--   - MoM_growth: short-term momentum — useful for catching sudden drops.
--   - YoY_growth: seasonality-adjusted growth — the number leadership cares about.
--   - YoY will return NULL for the first 12 months of data since there is no
--     prior year to compare against. This is expected and correct behaviour.
--
-- Key Output Columns:
--   order_month, revenue, MoM_growth (%), YoY_growth (%)
-- ============================================================

with cte as
(
select
	date_trunc('month', order_date) order_month,
    sum(net_amount) revenue
from orders
where order_status = 'delivered'
group by date_trunc('month', order_date)
)
select
	order_month,
    revenue,
    round(100.0*(revenue-lag(revenue,1) over (order by order_month))/nullif(lag(revenue,1) over (order by order_month),0),2) MoM_growth,
    round(100.0*(revenue-lag(revenue,12) over (order by order_month))/nullif(lag(revenue,12) over (order by order_month),0),2) YoY_growth
from cte;


-- ============================================================
-- METRIC 5: REVENUE CONCENTRATION — TOP 20% CUSTOMERS
-- ============================================================
-- Business Context:
--   In most ecommerce businesses, roughly 20% of customers drive 60–80% of revenue
--   (the Pareto principle). Knowing your actual concentration ratio tells you how
--   fragile the revenue base is and how much it costs to lose a single high-value
--   customer. It also justifies the business case for retention investment —
--   protecting one Platinum customer may be worth more than acquiring ten Bronze ones.
--
-- What It Tells You:
--   - cumulative_revenue_pct: as you scroll down the ranked list, at what customer_pct
--     does the cumulative revenue cross 80%? that crossover point is your concentration ratio.
--   - if the top 20% of customers account for 80%+ of revenue, the business is heavily
--     concentrated and highly sensitive to churn among its best customers.
--
-- Design Note on ROW_NUMBER:
--   ROW_NUMBER() is used instead of RANK() or DENSE_RANK() to ensure customer_pct
--   increases smoothly with each row even when multiple customers have identical spend.
--   RANK() would assign the same percentage to tied customers, creating flat steps
--   in the cumulative curve and overstating concentration at those spend levels.
--
-- Scope Note:
--   This query includes all orders regardless of status. The intent is to measure
--   total revenue contribution per customer across their entire relationship with
--   CartIQ, including cancelled and returned orders where the transaction was initiated.
--   To measure concentration on collected revenue only, add WHERE order_status = 'delivered'.
--
-- Key Output Columns:
--   customer_id, cumulative_revenue_pct, customer_pct
-- ============================================================

with customer_wise_revenue as
(
select
	customer_id,
    sum(net_amount) revenue
from orders
where order_status = 'delivered'
group by customer_id
)
select
	customer_id,
    round(100.0*sum(revenue) over (order by revenue desc, customer_id asc)/sum(revenue) over (), 2) cumulative_revenue_pct,
    round(100.0*row_number() over (order by revenue desc)/nullif(count(*) over (),0), 2) customer_pct
    -- row_number instead of rank or dense_rank ensures increasing percentage with each customer even if their spend is the same
from customer_wise_revenue;
