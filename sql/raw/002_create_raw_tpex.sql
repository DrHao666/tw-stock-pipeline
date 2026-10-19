-- raw 層：櫃買中心（上櫃）每日收盤行情原始回應
-- 注意：休市日 stat 仍是 'ok'，只是 tables[0].data 為空，休市判斷留給 staging

CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.tpex_otc_quotes (
    trade_date  DATE        PRIMARY KEY,          -- 查詢的日期（Asia/Taipei）
    stat        TEXT        NOT NULL,             -- 櫃買中心回的 stat（交易日、休市日都是 'ok'）
    payload     JSONB       NOT NULL,             -- 完整回應 JSON
    fetched_at  TIMESTAMPTZ NOT NULL DEFAULT now() -- 最後一次抓取時間
);

COMMENT ON TABLE raw.tpex_otc_quotes IS '櫃買中心 afterTrading/otc (type=EW) 原始回應，每個日期一筆';
