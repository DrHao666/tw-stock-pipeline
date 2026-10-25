-- 完成條件「每天每檔股票都有訊號紀錄」：indicators 有的每一列（有成交的一天一檔），signals 都要有
select i.trade_date, i.stock_id
from {{ ref('indicators') }} i
left join {{ ref('signals') }} s
    on s.trade_date = i.trade_date and s.stock_id = i.stock_id
where s.stock_id is null
