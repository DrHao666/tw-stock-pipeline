-- 個股摘要：一檔一列，給 Dashboard（之後的 LINE bot 也用）直接查，不用在畫面那一層再組 SQL
-- 內容是每檔「最後一個有成交日」的價格、指標、趨勢，加上近 5 個有成交日出現過的訊號、每種訊號最近一次出現的日期
-- 名稱、市場、證券類別取 dim_stock 目前的版本；已下市的股票也保留，最後交易日會停在下市前
-- 漲跌幅用還原收盤價算，除權息當天不會被算成大跌

with signal_events as (
    -- 訊號轉成長表：一列一個（日期、股票、訊號），只留有出現的；代碼和 backtest_results 的 signal 欄位一致
    select s.trade_date, s.stock_id, e.signal
    from {{ ref('signals') }} s
    cross join lateral (values
        ('three_white_soldiers', s.three_white_soldiers),
        ('evening_star',         s.evening_star),
        ('dark_cloud_cover',     s.dark_cloud_cover),
        ('breakout',             s.trend_state = 'breakout'),
        ('pullback',             s.trend_state = 'pullback')
    ) as e(signal, fired)
    where e.fired
),

last_seen as (
    select
        stock_id,
        max(trade_date) filter (where signal = 'three_white_soldiers') as last_three_white_soldiers,
        max(trade_date) filter (where signal = 'evening_star')         as last_evening_star,
        max(trade_date) filter (where signal = 'dark_cloud_cover')     as last_dark_cloud_cover,
        max(trade_date) filter (where signal = 'breakout')             as last_breakout,
        max(trade_date) filter (where signal = 'pullback')             as last_pullback
    from signal_events
    group by stock_id
),

ranked as (
    -- 每檔的有成交日由新到舊編號，1 = 最後一個有成交日
    select
        p.*,
        lead(p.adj_close_price) over (partition by p.stock_id order by p.trade_date desc) as prev_adj_close,
        row_number() over (partition by p.stock_id order by p.trade_date desc) as recency
    from {{ ref('fact_daily_price') }} p
    where p.adj_close_price is not null
),

recent_signals as (
    -- 近 5 個有成交日出現過的訊號，依代碼排序方便畫面顯示
    select r.stock_id, array_agg(distinct e.signal order by e.signal) as signals_last_5d
    from ranked r
    join signal_events e on e.stock_id = r.stock_id and e.trade_date = r.trade_date
    where r.recency <= 5
    group by r.stock_id
),

latest as (
    select * from ranked where recency = 1
)

select
    l.stock_id,
    d.stock_name,
    d.market,
    d.security_type,
    d.industry,
    d.is_delisted,
    -- 回測只算個股，畫面上的「今日訊號」也用同一個範圍
    coalesce(d.security_type in ('股票', '創新板'), d.security_type is null and l.stock_id ~ '^[0-9]{4}$') as is_common_stock,
    l.trade_date                                                    as last_trade_date,
    l.close_price,
    round((l.adj_close_price / l.prev_adj_close - 1)::numeric, 6)   as change_pct,
    l.volume_shares,
    i.ma5,
    i.ma20,
    i.ma60,
    i.high_20,
    i.low_20,
    s.trend_state,
    coalesce(rs.signals_last_5d, '{}')                              as signals_last_5d,
    ls.last_three_white_soldiers,
    ls.last_evening_star,
    ls.last_dark_cloud_cover,
    ls.last_breakout,
    ls.last_pullback
from latest l
join {{ ref('dim_stock') }} d on d.stock_id = l.stock_id and d.is_current
left join {{ ref('indicators') }} i on i.stock_id = l.stock_id and i.trade_date = l.trade_date
left join {{ ref('signals') }} s on s.stock_id = l.stock_id and s.trade_date = l.trade_date
left join recent_signals rs on rs.stock_id = l.stock_id
left join last_seen ls on ls.stock_id = l.stock_id
