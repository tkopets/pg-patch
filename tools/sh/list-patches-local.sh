#!/bin/bash

# Simple tool to list files with patches that satisfies dependencies while loading them.

# source query-patches.sh located in the same dir
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/lib/query-patches.sh"

query_patches  "
with patches as (
    select array_agg( row(p, dep)::_v.graph_edges ) as graph from (
      select patch_name as p, case when requires <> '{}' then unnest(requires) else patch_name end as dep
      from tmp_local_patches
    ) w
)
select case when p is null
            then '  ! '
            else '    '
       end ||
       ts.node as patch
from   _v.topological_sort( (select graph from patches) ) ts
      left join tmp_local_patches p on ts.node = p.patch_name
order by sort_order desc;"
