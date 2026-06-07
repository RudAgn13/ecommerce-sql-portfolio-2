-- METRIC 1: SELLER SCORECARD
with attrib as (
select
	s.seller_id,
    count(distinct o.order_id) total_delivered_orders,
    sum(oi.line_total) gross_merchandise_value,
    round(100.0*count(distinct case when o.actual_delivery<=o.expected_delivery then o.order_id end)/count(distinct o.order_id),2) otdr_pct,
    round(100.0*count(r.return_id)/count(oi.item_id),2) return_rate_pct,
    round(avg(o.actual_delivery::date - o.order_date::date - s.avg_dispatch_days)::decimal,2) dispatch_to_delivery_days
from sellers s
left join order_items oi on s.seller_id = oi.seller_id
left join orders o on oi.order_id = o.order_id
left join returns r on oi.item_id = r.item_id
where o.order_status='delivered'
group by s.seller_id
order by s.seller_id
), comp as (
select
	*,
	(case
    	when otdr_pct>=95 then 30
        when otdr_pct>=85 then 20
        else 10
    end +
    case
    	when return_rate_pct<=2 then 30
        when return_rate_pct<=5 then 20
        else 5
    end +
    case
    	when gross_merchandise_value>=500000 then 20
        when gross_merchandise_value>=100000 then 15
        else 5
    end +
    case
    	when dispatch_to_delivery_days<=4 then 20
        when dispatch_to_delivery_days<=7 then 10
        else 5
    end) composite_score
from attrib
)
select
	*,
    ntile(4) over (order by composite_score desc)
from comp;

-- METRIC 2: TOP AND BOTTOM 5 SELLERS BY GMV

-- METRIC 3: CATEGORY VELOCITY - FAST/SLOW MOVING

-- METRIC 4: REPEAT PURCHASE RATE BY CATEGORY

--METRIC 5: NEW VS. RETURNING SELLER GMV CONTRIBUTION OVER TIME
