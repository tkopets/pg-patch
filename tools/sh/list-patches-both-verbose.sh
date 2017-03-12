#!/bin/bash

# Simple tool to list files with patches that satisfies dependencies while loading them.

# source query-patches.sh located in the same dir
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/lib/query-patches.sh"

query_patches  "
with local_patches_raw as (
    select array_agg( row(p, dep)::_v.graph_edges ) as graph from (
      select patch_name as p, case when requires <> '{}' then unnest(requires) else patch_name end as dep
      from tmp_local_patches
    ) w
),
local_patches as (
    select ts.node as patch,
           regexp_replace(p.filename, '^.+[/\\\\]', '') as filename,
           row_number() over (order by sort_order desc) as install_order
    from   _v.topological_sort( (select graph from local_patches_raw) ) ts
          left join tmp_local_patches p on ts.node = p.patch_name
    order by sort_order desc
),
applied_patches_raw as (
    select array_agg( row(p, dep)::_v.graph_edges ) as graph from (
      select patch_name as p, case when requires <> '{}' then unnest(requires) else patch_name end as dep
      from _v.patches
    ) w
),
applied_patches as (
    select ts.node as patch,
           p.applied_ts,
           row_number() over (order by sort_order desc) as install_order
    from   _v.topological_sort( (select graph from applied_patches_raw) ) ts
           left join _v.patches p on ts.node = p.patch_name
    order by sort_order desc
)
select patch as patch,
       a.applied_ts::timestamptz(0) as applied,
       l.filename as filename
from   applied_patches a
       full outer join local_patches l USING (patch)
order  by a is null, a.applied_ts, coalesce(a.install_order, l.install_order);" "--quiet --pset pager=off --pset footer=off"
