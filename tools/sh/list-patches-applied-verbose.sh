#!/bin/bash
set -o errexit
set -o pipefail

# Simple tool to list files with patches that satisfies dependencies while loading them.

# source query-patches.sh located in the same dir
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/lib/query-patches.sh"

# ignore any additional files - this way we don't even need
# a special "query-applied-pathes.sh" script
PATCHES_DIR=''

query_patches  "
with patches as (
    select array_agg( row(p, dep)::_v.graph_edges ) as graph
    from (
        select p.patch_name as p,
               coalesce(r.required, p.patch_name) as dep
        from   _v.patches p
               left join lateral unnest(p.requires) as r(required) on true
    ) w
)
select ts.node as patch,
       p.applied_ts::timestamp(0) as applied,
       case when h.revision is not null and h.branch is not null
                 then format('%s [%s]', left(h.revision, 7), h.branch)
            when h.revision is not null and h.branch is null
                 then left(h.revision, 7)
            else null
        end as revision
from   _v.topological_sort( (select graph from patches) ) ts
      left join _v.patches p on ts.node = p.patch_name
      left join _v.patch_history h on p.applied_ts = h.applied_ts
order by p.applied_ts, ts.sort_order desc;"  "--quiet --pset pager=off --pset footer=off"
