{#-
  證交所／櫃買中心的數字都是字串：有千分位逗號，沒成交時是 '--'、'---' 或 '----'。
  去掉逗號與空白後轉成 numeric；佔位符號或空字串轉成 NULL。
-#}
{% macro clean_number(expr) -%}
    case
        when trim({{ expr }}) in ('', '--', '---', '----') then null
        else replace(trim({{ expr }}), ',', '')::numeric
    end
{%- endmacro %}
