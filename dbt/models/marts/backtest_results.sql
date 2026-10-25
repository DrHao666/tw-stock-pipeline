-- 回測結果：每種訊號 × 持有天數一列，訊號出現後的報酬統計與基準比較
-- 基準 = 回測範圍內所有股票、所有日子的平均報酬（等於隨機抽日的期望值，結果固定、不受抽樣影響）
-- 超額報酬 = 訊號股的報酬 − 同一天所有股票的平均報酬，扣掉大盤當時的漲跌
-- t 值 = 平均超額報酬 / 標準誤；同一檔連續幾天出現訊號時持有期間會重疊，樣本不完全獨立，t 值會偏樂觀

with settings as (
    select max(value) filter (where name = 'round_trip_cost') as round_trip_cost
    from {{ ref('backtest_settings') }}
),

-- 轉成長表：一列一個（日期、股票、持有天數），方便兩種持有天數用同一段邏輯算
returns_long as (
    select f.trade_date, f.stock_id, h.horizon_days, h.ret
    from {{ ref('forward_returns') }} f
    cross join lateral (values (5, f.return_5d), (20, f.return_20d)) as h(horizon_days, ret)
    where h.ret is not null
),

daily_average as (
    select trade_date, horizon_days, avg(ret) as day_avg_return
    from returns_long
    group by trade_date, horizon_days
),

baseline as (
    select horizon_days, avg(ret) as baseline_return, count(*) as baseline_observations
    from returns_long
    group by horizon_days
),

-- 訊號也轉成長表：一列一個（日期、股票、訊號），只留有出現的
signal_events as (
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

event_returns as (
    select
        e.signal,
        r.horizon_days,
        r.ret,
        r.ret - d.day_avg_return as excess_return
    from signal_events e
    join returns_long r on r.trade_date = e.trade_date and r.stock_id = e.stock_id
    join daily_average d on d.trade_date = r.trade_date and d.horizon_days = r.horizon_days
)

select
    er.signal,
    er.horizon_days,
    count(*)                                                        as events,
    round(avg(er.ret), 6)                                           as avg_return,
    round((percentile_cont(0.5) within group (order by er.ret))::numeric, 6) as median_return,
    round(avg((er.ret > 0)::int), 4)                                as win_rate,
    round(avg(er.ret) - max(st.round_trip_cost), 6)                 as avg_return_after_cost,
    round(max(b.baseline_return), 6)                                as baseline_return,
    round(avg(er.excess_return), 6)                                 as avg_excess_return,
    round((avg(er.excess_return) / nullif(stddev_samp(er.excess_return) / sqrt(count(*)), 0))::numeric, 2) as t_stat
from event_returns er
join baseline b on b.horizon_days = er.horizon_days
cross join settings st
group by er.signal, er.horizon_days
