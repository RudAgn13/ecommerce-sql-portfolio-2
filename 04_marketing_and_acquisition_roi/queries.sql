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

-- METRIC 3: CHANNEL PERFORMANCE - SESSIONS TO ORDERS

-- METRIC 4: CAMPAIGN ROI
