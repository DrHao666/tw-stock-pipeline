-- raw 層：證交所 ISIN 清單（上市＋上櫃目前掛牌的有價證券），每天一筆快照
-- 例外：這張表存的是解析後的非權證列，不是原始 HTML（原始頁面一天約 13 MB、九成是權證，原樣保存太大）
-- payload = {fields, data}，fields 依序為 證券類別、代號、名稱、ISIN、上市日、市場別、產業別、CFICode、備註

CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.twse_isin (
    snapshot_date  DATE        PRIMARY KEY,
    payload        JSONB       NOT NULL,
    fetched_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.twse_isin IS '證交所 ISIN 清單解析結果（不含權證），每天一筆快照';
