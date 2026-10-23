-- raw 層：集保股權分散表開放資料，每週一筆
-- 開放資料只有最新一週，這張表從開始抓的那週往後累積；payload 是 CSV 轉成的 {fields, data}，值都是原始字串

CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.tdcc_shareholding (
    data_date   DATE        PRIMARY KEY,
    payload     JSONB       NOT NULL,
    fetched_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.tdcc_shareholding IS '集保開放資料 1-5 股權分散表原始內容，每個資料日期（每週）一筆';
