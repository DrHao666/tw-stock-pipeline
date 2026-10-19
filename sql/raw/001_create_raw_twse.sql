-- raw 層：證交所 MI_INDEX 每日回應原封不動保存
-- 一個日期一筆（含休市日），parser 寫錯時可以從這裡重跑，不必再打證交所

CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.twse_mi_index (
    trade_date  DATE        PRIMARY KEY,          -- 查詢的日期（Asia/Taipei）
    stat        TEXT        NOT NULL,             -- 證交所回的 stat：'OK' 或休市訊息原文
    payload     JSONB       NOT NULL,             -- 完整回應 JSON
    fetched_at  TIMESTAMPTZ NOT NULL DEFAULT now() -- 最後一次抓取時間
);

COMMENT ON TABLE raw.twse_mi_index IS '證交所 MI_INDEX (type=ALLBUT0999) 原始回應，每個日期一筆';
