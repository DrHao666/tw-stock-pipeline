-- 上市和上櫃同一天的開市狀態必須一致；不一致代表其中一邊抓壞了（例如抓到空回應卻當成休市）
select trade_date, twse_open, tpex_open
from {{ ref('stg_trading_calendar') }}
where twse_open is not null
  and tpex_open is not null
  and twse_open <> tpex_open
