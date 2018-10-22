#!/bin/bash

# Simple tool to list files with patches that satisfies dependencies while loading them.

# source query-patches.sh located in the same dir
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/lib/query-patches.sh"


function sed_bin() {
    if [[ ${OSTYPE//[0-9.]} == "solaris" ]]; then
        gsed "$@"
    else
        sed "$@"
    fi
}


query_patches  "
with local_patches_raw as (
    select array_agg( row(p, dep)::_v.graph_edges ) as graph
    from (
        select p.patch_name as p,
               coalesce(r.required, p.patch_name) as dep
        from   tmp_local_patches p
               left join lateral unnest(p.requires) as r(required) on true
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
    select array_agg( row(p, dep)::_v.graph_edges ) as graph
    from (
        select p.patch_name as p,
               coalesce(r.required, p.patch_name) as dep
        from   _v.patches p
               left join lateral unnest(p.requires) as r(required) on true
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
select case when a is null     and l.filename is not null then '*   '
            when a is null     and l.filename is null     then '* ! '
            when a is not null and l.filename is null     then '+ ! '
            else                                               '+   '
       end  ||
       patch as patch
from   applied_patches a
       full outer join local_patches l USING (patch)
order  by a is null, a.applied_ts, coalesce(a.install_order, l.install_order);"
