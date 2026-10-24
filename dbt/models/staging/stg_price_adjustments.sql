-- 會讓股價不連續的事件：除權息、減資、變更面額、ETF 分割／反分割，各來源整理成同一格式，一列一個事件
-- 每個事件都有「事件前收盤價」和「參考價」，係數 = 參考價 / 前收盤價，
-- 現金股利、股票股利、減資換股、面額換股都已反映在參考價裡，不需要另外拆公式
-- 除權息用「減除股利參考價」（交易所漲跌停的基準），不用含現金增資稀釋的「除權息參考價」：
-- 現增是股東自己出錢認購，用後者還原會在除權日造成實際上沒有發生的跳動
-- 官方表漏掉的事件由 seed manual_price_adjustments 人工補上，每筆附出處
-- 做成 table：資料量小，但 view 每次被測試或下游讀取都要重新解析 raw JSON

{{ config(materialized='table') }}

with twse_ex as (
    select
        {{ roc_to_date("rec ->> '資料日期'") }}           as event_date,
        trim(rec ->> '股票代號')                          as stock_id,
        'TWSE'::text                                      as market,
        'ex_rights'::text                                 as event_type,
        {{ clean_number("rec ->> '除權息前收盤價'") }}    as prev_close,
        coalesce(
            nullif({{ clean_number("rec ->> '減除股利參考價'") }}, 0),
            {{ clean_number("rec ->> '除權息參考價'") }}
        )                                                 as reference_price
    from ({{ event_records('twse_ex_rights') }}) e
),

twse_cr as (
    select
        {{ roc_to_date("rec ->> '恢復買賣日期'") }},
        trim(rec ->> '股票代號'),
        'TWSE',
        'capital_reduction',
        {{ clean_number("rec ->> '停止買賣前收盤價格'") }},
        {{ clean_number("rec ->> '恢復買賣參考價'") }}
    from ({{ event_records('twse_capital_reduction') }}) e
),

twse_pv as (
    select
        {{ roc_to_date("rec ->> '恢復買賣日期'") }},
        trim(rec ->> '股票代號'),
        'TWSE',
        'par_value_change',
        {{ clean_number("rec ->> '停止買賣前收盤價格'") }},
        {{ clean_number("rec ->> '恢復買賣參考價'") }}
    from ({{ event_records('twse_par_value_change') }}) e
),

-- 分割與反分割在同一張表，用「分割(反分割)」欄位區分
twse_split as (
    select
        {{ roc_to_date("rec ->> '恢復買賣日期'") }},
        trim(rec ->> 'ETF代號'),
        'TWSE',
        case when rec ->> '分割(反分割)' like '%反分割%' then 'etf_reverse_split' else 'etf_split' end,
        {{ clean_number("rec ->> '停止買賣前收盤價格'") }},
        {{ clean_number("rec ->> '恢復買賣參考價'") }}
    from ({{ event_records('twse_etf_split') }}) e
),

tpex_ex as (
    select
        {{ roc_to_date("rec ->> '除權息日期'") }},
        trim(rec ->> '代號'),
        'TPEx',
        'ex_rights',
        {{ clean_number("rec ->> '除權息前收盤價'") }},
        coalesce(
            nullif({{ clean_number("rec ->> '減除股利參考價'") }}, 0),
            {{ clean_number("rec ->> '除權息參考價'") }}
        )
    from ({{ event_records('tpex_ex_rights') }}) e
),

tpex_cr as (
    select
        {{ roc_to_date("rec ->> '恢復買賣日期'") }},
        trim(rec ->> '股票代號'),
        'TPEx',
        'capital_reduction',
        {{ clean_number("rec ->> '最後交易日之收盤價格'") }},
        {{ clean_number("rec ->> '減資恢復買賣開始日參考價格'") }}
    from ({{ event_records('tpex_capital_reduction') }}) e
),

-- 櫃買中心的面額變更、ETF 分割、反分割三張表欄位相同
tpex_pv as (
    select
        {{ roc_to_date("rec ->> '恢復買賣日期'") }},
        trim(rec ->> '證券代號'),
        'TPEx',
        'par_value_change',
        {{ clean_number("rec ->> '最後交易日之收盤價格'") }},
        {{ clean_number("rec ->> '恢復買賣開始參考價'") }}
    from ({{ event_records('tpex_par_value_change') }}) e
),

tpex_split as (
    select
        {{ roc_to_date("rec ->> '恢復買賣日期'") }},
        trim(rec ->> '證券代號'),
        'TPEx',
        'etf_split',
        {{ clean_number("rec ->> '最後交易日之收盤價格'") }},
        {{ clean_number("rec ->> '恢復買賣開始參考價'") }}
    from ({{ event_records('tpex_etf_split') }}) e
),

tpex_reverse_split as (
    select
        {{ roc_to_date("rec ->> '恢復買賣日期'") }},
        trim(rec ->> '證券代號'),
        'TPEx',
        'etf_reverse_split',
        {{ clean_number("rec ->> '最後交易日之收盤價格'") }},
        {{ clean_number("rec ->> '恢復買賣開始參考價'") }}
    from ({{ event_records('tpex_etf_reverse_split') }}) e
),

manual as (
    select event_date, stock_id, market, event_type, prev_close, reference_price
    from {{ ref('manual_price_adjustments') }}
),

events as (
    select * from twse_ex
    union all select * from twse_cr
    union all select * from twse_pv
    union all select * from twse_split
    union all select * from tpex_ex
    union all select * from tpex_cr
    union all select * from tpex_pv
    union all select * from tpex_split
    union all select * from tpex_reverse_split
    union all select * from manual
)

select
    event_date,
    stock_id,
    market,
    event_type,
    prev_close,
    reference_price,
    reference_price / prev_close as factor
from events
-- 價格缺漏的事件算不出係數，排除（櫃買中心無資料時用 '0.00'）
where prev_close > 0
  and reference_price > 0
