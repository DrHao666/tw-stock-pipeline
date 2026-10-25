-- 技術指標的基本性質，任何一列違反都代表計算有錯：
--   1. 均線落在同一視窗的最低價與最高價之間（收盤價一定介於當天高低之間）
--   2. 資料不足 N 天時是 NULL，足夠時不是 NULL
with checked as (
    select
        i.*,
        row_number() over (partition by stock_id order by trade_date) as nth_trade
    from {{ ref('indicators') }} i
)

select trade_date, stock_id, nth_trade, ma5, ma20, ma60, low_20, high_20, low_60, high_60
from checked
where ma20 not between low_20 * 0.9999 and high_20 * 1.0001
   or ma60 not between low_60 * 0.9999 and high_60 * 1.0001
   or (nth_trade < 5)  <> (ma5 is null)
   or (nth_trade < 20) <> (ma20 is null)
   or (nth_trade < 60) <> (ma60 is null)
