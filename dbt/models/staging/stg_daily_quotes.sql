-- 上市＋上櫃每日收盤行情，欄位已在兩個來源 model 對齊；之後 marts 一律從這裡讀
-- 同一個代號不會同時在兩個市場交易，(trade_date, stock_id) 仍然唯一（由 test 保證）

select * from {{ ref('stg_twse_quotes') }}
union all
select * from {{ ref('stg_tpex_quotes') }}
