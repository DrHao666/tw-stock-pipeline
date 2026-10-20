{#-
  把除權息／減資 raw 表攤開成一列一個事件，rec 是「正規化欄位名 → 值」的 jsonb。
  證交所的 fields/data 在最外層，櫃買中心放在 tables[] 裡，兩種都處理。
  沒資料的月份（證交所 stat 不是 OK、櫃買中心 data 為空）攤開後自然沒有資料列。
-#}
{% macro event_records(source_table) -%}
    with event_tables as (
        select r.payload as tbl
        from {{ source('raw', source_table) }} r
        where r.payload ? 'data'
        union all
        select t.tbl
        from {{ source('raw', source_table) }} r
        cross join lateral jsonb_array_elements(coalesce(r.payload -> 'tables', '[]'::jsonb)) as t(tbl)
    )
    select
        (
            select jsonb_object_agg(
                regexp_replace(f.name, '<br>|\s', '', 'g'),
                d.row_values -> (f.pos - 1)::int
            )
            from jsonb_array_elements_text(e.tbl -> 'fields') with ordinality as f(name, pos)
        ) as rec
    from event_tables e
    cross join lateral jsonb_array_elements(coalesce(e.tbl -> 'data', '[]'::jsonb)) as d(row_values)
{%- endmacro %}
