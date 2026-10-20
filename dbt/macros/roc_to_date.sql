{#-
  民國年日期轉 date。來源有三種寫法：'115年01月02日'、'115/01/12'、'1150112'，
  去掉非數字後都是「民國年 + 月 2 碼 + 日 2 碼」，年份位數不固定（99 年是 2 碼）。
-#}
{% macro roc_to_date(expr) -%}
    make_date(
        left(regexp_replace({{ expr }}, '\D', '', 'g'), -4)::int + 1911,
        substr(right(regexp_replace({{ expr }}, '\D', '', 'g'), 4), 1, 2)::int,
        right(regexp_replace({{ expr }}, '\D', '', 'g'), 2)::int
    )
{%- endmacro %}
