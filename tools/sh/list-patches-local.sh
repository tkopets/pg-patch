#!/bin/bash
set -o errexit
set -o pipefail

# Simple tool to list files with patches that satisfies dependencies while loading them.

# source query-patches.sh located in the same dir
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/lib/query-patches.sh"

query_patches  "
with patches as (
    select array_agg( row(p, dep)::_v.graph_edges ) as graph
    from (
        select p.patch_name as p,
               coalesce(r.required, p.patch_name) as dep
        from   tmp_local_patches p
               left join lateral unnest(p.requires) as r(required) on true
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
