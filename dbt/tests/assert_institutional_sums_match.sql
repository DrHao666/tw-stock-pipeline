-- 三大法人各組加總要等於合計；櫃買中心依位置取值，如果欄位位置對錯，這裡會立刻抓到
--   自營商合計 = 自行買賣 + 避險
--   三大法人合計 = 外資(不含外資自營商) + 外資自營商 + 投信 + 自營商合計
select *
from {{ ref('stg_institutional_trades') }}
where dealer_net <> dealer_self_net + dealer_hedge_net
   or total_net <> foreign_net + foreign_dealer_net + trust_net + dealer_net
