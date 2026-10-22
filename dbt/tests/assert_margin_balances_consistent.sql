-- 融資融券餘額恆等式；兩邊都依位置取值，欄位位置對錯這裡會立刻抓到
--   融資今日餘額 = 前日餘額 + 買進 - 賣出 - 現金償還
--   融券今日餘額 = 前日餘額 + 賣出 - 買進 - 現券償還
select *
from {{ ref('stg_margin_trades') }}
where margin_balance <> margin_prev_balance + margin_buy - margin_sell - margin_cash_repay
   or short_balance <> short_prev_balance + short_sell - short_buy - short_stock_repay
