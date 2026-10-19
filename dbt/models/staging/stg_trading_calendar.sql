-- 交易日曆：從 raw 推出每個「抓過的日期」是否開市
-- 不寫死週末休市（以前有補行上班的週六開盤），也能抓到颱風假這類臨時休市
-- raw 裡沒有的日期不會出現在這裡，代表「還沒抓」，不是休市

with twse as (
    select trade_date, stat = 'OK' as is_open
    from {{ source('raw', 'twse_mi_index') }}
),

-- 櫃買中心休市日 stat 仍是 'ok'，要看 data 有沒有資料
tpex as (
    select
        r.trade_date,
        coalesce(sum(jsonb_array_length(t.tbl -> 'data')), 0) > 0 as is_open
    from {{ source('raw', 'tpex_otc_quotes') }} r
    left join lateral jsonb_array_elements(r.payload -> 'tables') as t(tbl) on true
    group by r.trade_date
)

select
    coalesce(twse.trade_date, tpex.trade_date) as trade_date,
    twse.is_open as twse_open,   -- NULL：這天還沒抓上市
    tpex.is_open as tpex_open,   -- NULL：這天還沒抓上櫃
    coalesce(twse.is_open, tpex.is_open) as is_trading_day
from twse
full outer join tpex on twse.trade_date = tpex.trade_date
