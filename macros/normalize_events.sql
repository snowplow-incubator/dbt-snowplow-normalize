{#
Copyright (c) 2022-present Snowplow Analytics Ltd. All rights reserved.
This program is licensed to you under the Snowplow Personal and Academic License Version 1.0,
and you may not use this file except in compliance with the Snowplow Personal and Academic License Version 1.0.
You may obtain a copy of the Snowplow Personal and Academic License Version 1.0 at https://docs.snowplow.io/personal-and-academic-license-1.0/
#}

{% macro normalize_events(event_names, flat_cols = [], sde_cols = [], sde_keys = [], sde_types = [], sde_aliases = [], context_cols = [], context_keys = [], context_types = [], context_aliases = [], remove_new_event_check = false) %}
    {{ return(adapter.dispatch('normalize_events', 'snowplow_normalize')(event_names, flat_cols, sde_cols, sde_keys, sde_types, sde_aliases, context_cols, context_keys, context_types, context_aliases, remove_new_event_check)) }}
{% endmacro %}

{% macro snowflake__normalize_events(event_names, flat_cols = [], sde_cols = [], sde_keys = [], sde_types = [], sde_aliases = [], context_cols = [], context_keys = [], context_types = [], context_aliases = [], remove_new_event_check = false) %}
{# Remove down to major version for Snowflake columns, drop 2 last _X values #}
{%- set sde_cols_clean = [] -%}
{%- for ind in range(sde_cols|length) -%}
    {% do sde_cols_clean.append('_'.join(sde_cols[ind].split('_')[:-2])) -%}
{%- endfor -%}

{%- set context_cols_clean = [] -%}
{%- for ind in range(context_cols|length) -%}
    {% do context_cols_clean.append('_'.join(context_cols[ind].split('_')[:-2])) -%}
{%- endfor -%}

select
    event_id
    , collector_tstamp
    -- Flat columns from event table
    {% if flat_cols|length > 0 %}
        {%- for col in flat_cols -%}
            , {{ col }}
        {% endfor -%}
    {%- endif -%}
    -- self describing events columns from event table
    {% if sde_cols_clean|length > 0 %}
        {%- for col, col_ind in zip(sde_cols_clean, range(sde_cols_clean|length)) -%} {# Loop over each sde column #}
            {%- for key, type in zip(sde_keys[col_ind], sde_types[col_ind]) -%} {# Loop over each key within the sde column #}
                {% if sde_aliases|length > 0 -%}
                    , {{ col }}:{{ key }}::{{ type }} as {{ sde_aliases[col_ind] }}_{{ snowplow_normalize.snakeify_case(key) }} {# Alias should align across all warehouses in snakecase #}
                {% else -%}
                    , {{ col }}:{{ key }}::{{ type }} as {{ snowplow_normalize.snakeify_case(key) }}
                {% endif -%}
            {%- endfor -%}
        {%- endfor -%}
    {%- endif %}
    -- context column(s) from the event table
    {% if context_cols_clean|length > 0 %}
        {%- for col, col_ind in zip(context_cols_clean, range(context_cols_clean|length)) -%} {# Loop over each context column #}
            {%- for key, type in zip(context_keys[col_ind], context_types[col_ind]) -%} {# Loop over each key within the context column #}
                {% if context_aliases|length > 0 -%}
                    , {{ col }}[0]:{{ key }}::{{ type }} as {{ context_aliases[col_ind] }}_{{ snowplow_normalize.snakeify_case(key) }} {# Alias should align across all warehouses in snakecase #}
                {% else -%}
                    , {{ col }}[0]:{{ key }}::{{ type }} as {{ snowplow_normalize.snakeify_case(key) }}
                {% endif -%}
            {%- endfor -%}
        {%- endfor -%}
    {%- endif %}
from
    {{ ref('snowplow_normalize_base_events_this_run') }}
where
    event_name in ('{{ event_names|join("','") }}')
    {% if not remove_new_event_check %}
        and {{ snowplow_utils.is_run_with_new_events("snowplow_normalize") }}
    {%- endif -%}
{% endmacro %}


{% macro bigquery__normalize_events(event_names, flat_cols = [], sde_cols = [], sde_keys = [], sde_types = [], sde_aliases = [], context_cols = [], context_keys = [], context_types = [], context_aliases = [], remove_new_event_check = false) %}
    {# Handle both versioned and unversioned column names #}
    {%- set re = modules.re -%}

    {# 
        This regex pattern handles column versioning in Snowplow contexts and self-describing events.
        It specifically targets three-part semantic versions (e.g., field_1_2_3) while preserving
        one-part (field_1) and two-part (field_1_2) versions.

        Pattern breakdown: '(_\\d+)_\\d+_\\d+$'
        - (_\\d+)    : Capture group that matches an underscore followed by one or more digits
                        This captures the major version number (e.g., "_1" in "field_1_2_3")
        - _\\d+      : Matches an underscore and one or more digits (minor version)
        - _\\d+      : Matches an underscore and one or more digits (patch version)
        - $          : Ensures the pattern only matches at the end of the string

        The replacement pattern '\\1' keeps only the captured major version.

        Examples:
        - field_1     -> field_1     (no change - only has major version)
        - field_1_2   -> field_1_2   (no change - has major and minor versions)
        - field_1_2_3 -> field_1     (transforms - removes minor and patch versions)
    #}
    {%- set version_pattern = '(_\\d+)_\\d+_\\d+$' -%}

    {%- set sde_cols_clean = [] -%}
    {%- for col in sde_cols -%}
        {# Get the base name for combine_column_versions to work with #}
        {%- set clean_name = re.sub(version_pattern, '\\1', col) -%}
        {% do sde_cols_clean.append(clean_name) -%}
    {%- endfor -%}

    {%- set context_cols_clean = [] -%}
    {%- for col in context_cols -%}
        {%- set clean_name = re.sub(version_pattern, '\\1', col) -%}
        {% do context_cols_clean.append(clean_name) -%}
    {%- endfor -%}
{# Replace keys with snake_case where needed #}
{%- set sde_keys_clean = [] -%}
{%- set context_keys_clean = [] -%}

{%- for ind1 in range(sde_keys|length) -%}
    {%- set sde_key_clean = [] -%}
    {%- for ind2 in range(sde_keys[ind1]|length) -%}
        {% do sde_key_clean.append(snowplow_normalize.snakeify_case(sde_keys[ind1][ind2])) -%}
    {%- endfor -%}
    {% do sde_keys_clean.append(sde_key_clean) -%}
{%- endfor -%}
{%- for ind1 in range(context_keys|length) -%}
    {%- set context_key_clean = [] -%}
    {%- for ind2 in range(context_keys[ind1]|length) -%}
        {% do context_key_clean.append(snowplow_normalize.snakeify_case(context_keys[ind1][ind2])) -%}
    {%- endfor -%}
    {% do context_keys_clean.append(context_key_clean) -%}
{%- endfor -%}



select
    event_id
    , collector_tstamp
    -- Flat columns from event table
    {% if flat_cols|length > 0 %}
        {%- for col in flat_cols -%}
            , {{ col }}
        {% endfor -%}
    {%- endif -%}
    -- self describing events columns from event table
    {% if sde_cols|length > 0 %}
        {%- for col, col_ind in zip(sde_cols_clean, range(sde_cols|length)) -%} {# Loop over each sde column, get coalesced version of keys #}
            {# Prep the alias columns #}
            {%- if sde_aliases|length > 0 -%}
                {%- set required_aliases = [] -%}
                {%- for i in range(sde_keys_clean[col_ind]|length) -%}
                    {%- do required_aliases.append(sde_aliases[col_ind] ~ '_' ~ sde_keys_clean[col_ind][i]) -%}
                {%- endfor -%}
            {%- else -%}
                {%- set required_aliases = sde_keys_clean[col_ind] -%}
            {%- endif -%}
            {%- set sde_col_list = snowplow_utils.combine_column_versions(
                relation=ref('snowplow_normalize_base_events_this_run'),
                column_prefix=col.lower(),
                required_fields = zip(sde_keys_clean[col_ind], required_aliases)
            ) -%}
            {%- for field, key_ind in zip(sde_col_list, range(sde_col_list|length)) -%} {# Loop over each key within the column, appling the bespoke alias as needed #}
                , {{field}}
            {% endfor -%}
        {%- endfor -%}
    {%- endif %}
    -- context column(s) from the event table
    {% if context_cols|length > 0 %}
        {%- for col, col_ind in zip(context_cols_clean, range(context_cols|length)) -%} {# Loop over each context column, get coalesced version of keys #}
            {# Prep the alias columns #}
            {%- if context_aliases|length > 0 -%}
                {%- set required_aliases = [] -%}
                {%- for i in range(context_keys_clean[col_ind]|length) -%}
                    {%- do required_aliases.append(context_aliases[col_ind] ~ '_' ~ context_keys_clean[col_ind][i]) -%}
                {%- endfor -%}
            {%- else -%}
                {%- set required_aliases = context_keys_clean[col_ind] -%}
            {%- endif -%}
            {%- set cont_col_list = snowplow_utils.combine_column_versions(
                                        relation=ref('snowplow_normalize_base_events_this_run'),
                                        column_prefix=col.lower(),
                                        required_fields = zip(context_keys_clean[col_ind], required_aliases)
                                        ) -%}
            {%- for field, key_ind in zip(cont_col_list, range(cont_col_list|length)) -%} {# Loop over each key within the column #}
                , {{field}}
            {% endfor -%}
        {%- endfor -%}
    {%- endif %}
from
    {{ ref('snowplow_normalize_base_events_this_run') }}
where
    event_name in ('{{ event_names|join("','") }}')
    {% if not remove_new_event_check %}
        and {{ snowplow_utils.is_run_with_new_events("snowplow_normalize") }}
    {%- endif -%}
{% endmacro %}

{% macro spark__normalize_events(event_names, flat_cols = [], sde_cols = [], sde_keys = [], sde_types = [], sde_aliases = [], context_cols = [], context_keys = [], context_types = [], context_aliases = [], remove_new_event_check = false) %}
{# Remove down to major version for Databricks columns, drop 2 last _X values #}
{%- set sde_cols_clean = [] -%}
{%- for ind in range(sde_cols|length) -%}
    {% do sde_cols_clean.append('_'.join(sde_cols[ind].split('_')[:-2])) -%}
{%- endfor -%}

{%- set context_cols_clean = [] -%}
{%- for ind in range(context_cols|length) -%}
    {% do context_cols_clean.append('_'.join(context_cols[ind].split('_')[:-2])) -%}
{%- endfor -%}

{# Replace keys with snake_case where needed #}
{%- set sde_keys_clean = [] -%}
{%- set context_keys_clean = [] -%}

{%- for ind1 in range(sde_keys|length) -%}
    {%- set sde_key_clean = [] -%}
    {%- for ind2 in range(sde_keys[ind1]|length) -%}
        {% do sde_key_clean.append(snowplow_normalize.snakeify_case(sde_keys[ind1][ind2])) -%}
    {%- endfor -%}
    {% do sde_keys_clean.append(sde_key_clean) -%}
{%- endfor -%}

{%- for ind1 in range(context_keys|length) -%}
    {%- set context_key_clean = [] -%}
    {%- for ind2 in range(context_keys[ind1]|length) -%}
        {% do context_key_clean.append(snowplow_normalize.snakeify_case(context_keys[ind1][ind2])) -%}
    {%- endfor -%}
    {% do context_keys_clean.append(context_key_clean) -%}
{%- endfor -%}

select
    event_id
    , collector_tstamp
    {% if target.type in ['databricks', 'spark'] -%}
    , DATE({{var("snowplow__partition_tstamp")}}) as {{var("snowplow__partition_tstamp")}}_date
    {%- endif %}
    -- Flat columns from event table
    {% if flat_cols|length > 0 %}
        {%- for col in flat_cols -%}
            , {{ col }}
        {% endfor -%}
    {%- endif -%}
    -- self describing events columns from event table
    {% if sde_cols_clean|length > 0 %}
        {%- for col, col_ind in zip(sde_cols_clean, range(sde_cols_clean|length)) -%} {# Loop over each sde column #}
            {%- for key in sde_keys_clean[col_ind] -%} {# Loop over each key within the sde column #}
                {% if sde_aliases|length > 0 -%}
                    , {{ col }}.{{ key }} as {{ sde_aliases[col_ind] }}_{{ key }}
                {% else -%}
                    , {{ col }}.{{ key }} as {{ key }}
                {% endif -%}
            {%- endfor -%}
        {%- endfor -%}
    {%- endif %}

    -- context column(s) from the event table
    {% if context_cols_clean|length > 0 %}
        {%- for col, col_ind in zip(context_cols_clean, range(context_cols_clean|length)) -%} {# Loop over each context column #}
            {%- for key in context_keys_clean[col_ind] -%} {# Loop over each key within the context column #}
                {% if context_aliases|length > 0 -%}
                    , {{ col }}[0].{{ key }} as {{ context_aliases[col_ind] }}_{{ key }}
                {% else -%}
                    , {{ col }}[0].{{ key }} as {{ key }}
                {% endif -%}
            {%- endfor -%}
        {%- endfor -%}
    {%- endif %}
from
    {{ ref('snowplow_normalize_base_events_this_run') }}
where
    event_name in ('{{ event_names|join("','") }}')
    {% if not remove_new_event_check %}
        and {{ snowplow_utils.is_run_with_new_events("snowplow_normalize") }}
    {%- endif -%}
{% endmacro %}
