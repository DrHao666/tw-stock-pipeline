-- 除權息與減資事件：四個來源整理成同一格式，一列一個事件
-- 每個事件都有「事件前收盤價」和「參考價」，係數 = 參考價 / 前收盤價，
-- 現金股利、股票股利、減資換股都已反映在參考價裡，不需要另外拆公式
-- 做成 table：資料量小，但 view 每次被測試或下游讀取都要重新解析 raw JSON

{{ config(materialized='table') }}

with twse_ex as (
    select
        {{ roc_to_date("rec ->> '資料日期'") }}           as event_date,
        trim(rec ->> '股票代號')                          as stock_id,
        'TWSE'::text                                      as market,
        'ex_rights'::text                                 as event_type,
        {{ clean_number("rec ->> '除權息前收盤價'") }}    as prev_close,
        {{ clean_number("rec ->> '除權息參考價'") }}      as reference_price
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

tpex_ex as (
    select
        {{ roc_to_date("rec ->> '除權息日期'") }},
        trim(rec ->> '代號'),
        'TPEx',
        'ex_rights',
        {{ clean_number("rec ->> '除權息前收盤價'") }},
        {{ clean_number("rec ->> '除權息參考價'") }}
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

events as (
    select * from twse_ex
    union all select * from twse_cr
    union all select * from tpex_ex
    union all select * from tpex_cr
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
