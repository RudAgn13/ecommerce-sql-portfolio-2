-- METRIC 1: CUSTOMER ACQUISITION COST (CAC) BY CHANNEL
with channel_expense as (
    select
        (case
            when me.channel in ('google') then 'paid_search'
            when me.channel in ('meta','instagram') then 'social'
            when me.channel in ('email') then 'email'
            when me.channel in ('push','sms') then 'push_sms'
            else 'other'
        end) channel_bucket,
  		-- mapping intentional because marketing_events and sutomers tables have unmatched channels
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

-- METRIC 2: EMAIL CAMPAIGN FUNNEL
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

-- METRIC 3: CHANNEL PERFORMANCE - SESSIONS TO ORDERS
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

-- METRIC 4: CAMPAIGN ROI
