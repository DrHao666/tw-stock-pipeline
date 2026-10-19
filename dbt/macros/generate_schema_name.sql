{#-
  dbt 預設會把 schema 組成「<target schema>_<自訂 schema>」，例如 public_staging。
  這裡改成直接用自訂的 schema 名稱（staging、marts），沒指定時才用 target schema。
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
