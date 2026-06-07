-- ============================================================
-- Project 04: Marketing & Acquisition ROI
-- Database: CartIQ (PostgreSQL 15)
-- ============================================================
-- What This Project Answers:
--   Marketing is the largest variable cost in ecommerce.
--   This project determines which spend is actually working —
--   by calculating Customer Acquisition Cost (CAC) per channel,
--   measuring email campaign conversion at every funnel stage,
--   attributing revenue to sessions by UTM source, and computing
--   end-to-end ROI per campaign. Without this, marketing budgets
--   are allocated on intuition rather than evidence.
-- ============================================================


-- ============================================================
-- METRIC 1: CUSTOMER ACQUISITION COST (CAC) BY CHANNEL
-- ============================================================
-- Business Context:
--   CAC is the counterpart to LTV. Without CAC you cannot evaluate
--   whether a channel is profitable. The LTV:CAC ratio is how
--   growth teams decide where to scale spend:
--     LTV:CAC > 3:1  → Healthy, consider scaling
--     LTV:CAC 1–3:1  → Marginal, optimise before scaling
--     LTV:CAC < 1:1  → Loss-making, reduce or cut
--   If paid search CAC is ₹1,500 but those customers have ₹15,000
--   LTV, it is a great channel. If social CAC is ₹800 but LTV is
--   ₹1,200, it is barely worth running.
--
-- What It Tells You:
--   - total_spend: how much was spent acquiring customers via each channel.
--   - customers_acquired: how many customers that spend produced.
--   - cac: cost per acquired customer — the primary optimisation metric
--     for any performance marketing team.
--
-- Design Note on Channel Mapping:
--   The marketing_events table stores channel as the traffic source
--   (google, meta, email, push, sms) while the customers table stores
--   acquisition_channel as a business label (paid_search, social, email,
--   organic, referral). These do not match directly. A CASE WHEN mapping
--   bridges both columns to a shared channel_bucket before joining.
--   This mapping is intentional and documented in the inline comment.
--
-- Key Output Columns:
--   channel_bucket, total_spend, customers_acquired, cac
-- ============================================================

with channel_expense as (
    select
        (case
            when me.channel in ('google') then 'paid_search'
            when me.channel in ('meta','instagram') then 'social'
            when me.channel in ('email') then 'email'
            when me.channel in ('push','sms') then 'push_sms'
            else 'other'
        end) channel_bucket,
  		-- mapping intentional because marketing_events and cutomers tables have unmatched channels
        sum(me.cost_per_event) total_spend
    from marketing_events me
    group by channel_bucket
), acquired as (
    select
        (case
            when c.acquisition_channel = 'paid_search' then 'paid_search'
            when c.acquisition_channel = 'social' then 'social'
            when c.acquisition_channel = 'email' then 'email'
            when c.acquisition_channel in ('organic','referral') then 'other'
            else 'other'
        end) channel_bucket,
        count(c.customer_id) customers_acquired
    from customers c
    group by channel_bucket
)
select
    ce.channel_bucket,
    round(ce.total_spend,2) total_spend,
    a.customers_acquired,
    round(ce.total_spend / nullif(a.customers_acquired, 0), 2) cac
from channel_expense ce
left join acquired a on ce.channel_bucket = a.channel_bucket
order by cac asc;


-- ============================================================
-- METRIC 2: EMAIL CAMPAIGN FUNNEL
-- ============================================================
-- Business Context:
--   Email is typically the highest-ROI retention channel in ecommerce.
--   A campaign with 45% open rate but 0.2% purchase conversion has a
--   broken offer or landing page — not a delivery problem. This funnel
--   pinpoints exactly where conversion breaks: sent → opened → clicked
--   → purchased. Each drop-off stage has a different fix:
--     Low open rate       → subject line or send-time problem
--     Low CTR             → email content or offer problem
--     Low purchase conv.  → landing page or product-offer mismatch
--
-- What It Tells You:
--   - open_rate_pct: what % of recipients engage at all?
--   - click_through_rate_pct: of those who opened, what % took action?
--     Uses unique_clickers as numerator to avoid counting repeat clicks
--     from the same customer multiple times.
--   - purchase_conversion_pct: of those who clicked, what % bought
--     within 3 days? The 3-day window captures intent-driven purchases
--     without attributing unrelated orders to the campaign.
--
-- Implementation Note:
--   The time-window filter and email_clicked condition are applied
--   in the LEFT JOIN clause rather than in WHERE. This keeps all
--   email event rows in scope for the funnel counts (sent, opened,
--   clicked) while only matching orders that meet the attribution
--   criteria. Filtering in WHERE would eliminate non-clicked rows
--   and break the sent and opened counts.
--
-- Key Output Columns:
--   campaign_name, emails_sent, emails_opened, emails_clicked,
--   unique_clickers, order_within_3_days,
--   revenue_from_order_within_3_days, open_rate_pct,
--   click_through_rate_pct, purchase_conversion_pct
-- ============================================================

select
    me.campaign_name,
    count(case when me.event_type = 'email_sent' then 1 end) emails_sent,
    count(case when me.event_type = 'email_opened' then 1 end) emails_opened,
    count(case when me.event_type = 'email_clicked' then 1 end) emails_clicked,
    count(distinct case when me.event_type = 'email_clicked' then me.customer_id end) unique_clickers,
    count(o.order_id) as order_within_3_days, --handled in join
    coalesce(sum(o.net_amount), 0) as revenue_from_order_within_3_days,
    round(100.0 * count(case when me.event_type = 'email_opened' then 1 end) / nullif(count(case when me.event_type = 'email_sent' then 1 end), 0), 2) as open_rate_pct,
    round(100.0 * count(distinct case when me.event_type = 'email_clicked' then me.customer_id end) / nullif(count(case when me.event_type = 'email_opened' then 1 end), 0), 2) as click_through_rate_pct,
    round(100.0 * count(o.order_id) / nullif(count(case when me.event_type = 'email_clicked' then 1 end), 0), 2) as purchase_conversion_pct
from marketing_events me
left join orders o 
    on me.customer_id = o.customer_id
    and me.event_type = 'email_clicked'
    and o.order_date::date - me.event_timestamp::date between 0 and 3
where me.channel = 'email'
group by me.campaign_name;


-- ============================================================
-- METRIC 3: CHANNEL PERFORMANCE — SESSIONS TO ORDERS
-- ============================================================
-- Business Context:
--   Not all traffic is equal. A channel driving 10,000 sessions
--   at 0.5% conversion is underperforming one driving 1,000 sessions
--   at 8% conversion. Revenue per session is the single number that
--   normalises both volume and conversion into one comparable metric
--   across channels. This is how growth teams decide where to increase
--   paid spend and where to cut.
--
-- What It Tells You:
--   - bounce_rate_pct: what % of sessions leave immediately with no
--     engagement? High bounce on a paid channel means the ad creative
--     and landing page are misaligned — budget is being wasted.
--   - conversion_rate_pct: of all sessions, what % resulted in an order?
--   - revenue_per_session: the most actionable single metric — multiply
--     this by incremental sessions to forecast revenue from additional spend.
--
-- Implementation Note:
--   Sessions are joined to orders on session_id — a precise one-to-one
--   attribution since session_id is stored directly on the orders table.
--   This avoids the fan-out risk of joining on customer_id, which would
--   attribute all of a customer's orders to every session they ever had.
--
-- Key Output Columns:
--   utm_source, utm_medium, total_sessions, bounced_sessions,
--   converted_sessions, orders_from_converted_sessions,
--   revenue_from_orders_from_converted_sessions,
--   bounce_rate_pct, conversion_rate_pct, revenue_per_session
-- ============================================================

select
	cs.utm_source,
    cs.utm_medium,
    count(cs.session_id) total_sessions,
    count(distinct case when cs.bounce=true then cs.session_id end) bounced_sessions,
    count(distinct case when cs.converted=true then cs.session_id end) converted_sessions,
    count(case when cs.converted=true then o.order_id end) orders_from_converted_sessions,
    sum(case when cs.converted=true then o.net_amount end) revenue_from_orders_from_converted_sessions,
    round(100.0*count(distinct case when cs.bounce=true then cs.session_id end)/nullif(count(cs.session_id),0),2) bounce_rate_pct,
    round(100.0*count(distinct case when cs.converted=true then cs.session_id end)/nullif(count(cs.session_id),0),2) conversion_rate_pct,
    round(coalesce(sum(case when cs.converted=true then o.net_amount end),0)/nullif(count(cs.session_id),0),2) revenue_per_session
from customer_sessions cs
left join orders o on cs.session_id = o.session_id
group by cs.utm_source, cs.utm_medium;


-- ============================================================
-- METRIC 4: CAMPAIGN ROI
-- ============================================================
-- Business Context:
--   CAC and email funnels measure efficiency. ROI is the final word
--   on whether a campaign was worth running at all. A campaign that
--   spent ₹50,000 and attributed ₹200,000 in revenue has a 300% ROI.
--   One that spent ₹50,000 and attributed ₹30,000 destroyed value.
--   This metric is what the CMO presents to the CFO when justifying
--   the marketing budget.
--
-- What It Tells You:
--   - revenue_attributed: total order revenue from customers who clicked
--     a campaign touchpoint and ordered within 7 days.
--   - roi: (attributed_revenue - total_spend) / total_spend * 100.
--     Positive = campaign made money. Negative = campaign lost money.
--   - customers_touched: reach of the campaign across all event types.
--   - number_of_conversions: unique customers who both engaged and ordered.
--
-- Implementation Note:
--   c2 uses a RIGHT JOIN from orders to marketing_events to ensure
--   every campaign appears even if it drove zero orders — the right join
--   preserves all marketing_events rows regardless of order matches.
--   The final LEFT JOIN from c1 to c2 then brings spend and conversions
--   together cleanly. COALESCE handles campaigns with zero attributed revenue.
--
-- Attribution Limitation:
--   A customer who clicked multiple campaigns within 7 days will have
--   their order attributed to all of those campaigns simultaneously.
--   This is last-touch attribution without deduplication — the same
--   order can appear in multiple campaign ROI figures. This is a known
--   limitation of session-level attribution and is standard behaviour
--   in most marketing analytics tools. A deduplicated model would require
--   selecting the single most recent click per order before attribution.
--
-- Key Output Columns:
--   campaign_name, revenue_attributed, roi,
--   customers_touched, number_of_conversions
-- ============================================================

with c1 as (
select
	me.campaign_name,
    sum(me.cost_per_event) total_campaign_spend,
    count(distinct me.customer_id) customers_touched
from marketing_events me
group by me.campaign_name
)
, c2 as (
select
	me.campaign_name,
	sum(o.net_amount) revenue_attributed,
    count(distinct o.customer_id) number_of_conversions
from orders o
right join marketing_events me on
	o.customer_id = me.customer_id
    and o.order_date::date-me.event_timestamp::date between 0 and 7
  	and me.event_type in ('email_clicked', 'push_clicked', 'sms_clicked', 'ad_clicked')
group by me.campaign_name
)
select
	c1.campaign_name,
    coalesce(c2.revenue_attributed, 0) revenue_attributed,
    round(100.0*(coalesce(c2.revenue_attributed, 0) - c1.total_campaign_spend)/nullif(c1.total_campaign_spend,0),2) roi,
    c1.customers_touched,
    coalesce(c2.number_of_conversions, 0) number_of_conversions
from c1
left join c2 on c1.campaign_name = c2.campaign_name;
