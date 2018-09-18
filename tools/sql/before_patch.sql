-- pg-patch before_patch.sql start --

-- function to drop code objects
create or replace function pg_temp.tmp_drop_code_objects()
returns integer
as $body$
declare
    _is_dropped boolean;
    _object_type text;
    _object_reference text;
    _drop_sql text;
    _exec_count integer not null default 0;
begin
    for _is_dropped, _object_type, _object_reference, _drop_sql in
        with recursive candidates_to_drop as (
            select drop_order,
                   object_oid,
                   object_type,
                   object_reference,
                   format(drop_template, object_reference) as drop_sql
            from (
                select 1 as drop_order,
                       r.oid as object_oid,
                       'rule' as object_type,
                       format('%I on %I.%I', r.rulename, ns.nspname, c.relname) as object_reference,
                       'drop rule if exists %s cascade;' as drop_template
                from   pg_catalog.pg_rewrite r
                       inner join pg_class c on r.ev_class = c.oid
                       inner join pg_namespace ns on c.relnamespace = ns.oid
                where  ns.nspname not like 'pg_%'
                   and ns.nspname not in ('information_schema', '_v')
                   and not exists (select 1 from pg_depend d where c.oid = d.objid and d.deptype = 'e')
                   and r.rulename != '_RETURN'
                --
                union all
                --
                select 2 as drop_order,
                       c.oid as object_oid,
                       'view' as object_type,
                       format('%I.%I', ns.nspname, c.relname) as object_reference,
                       'drop view if exists %s cascade;' as drop_template
                from   pg_class c
                       inner join pg_namespace ns on c.relnamespace = ns.oid
                where  ns.nspname not like 'pg_%'
                   and ns.nspname not in ('information_schema', '_v')
                   and not exists (select 1 from pg_depend d where c.oid = d.objid and d.deptype = 'e')
                   and c.relkind = 'v'  -- views
                --
                union all
                --
                select 3 as drop_order,
                       t.oid as object_oid,
                       'type' as object_type,
                       format('%I.%I', ns.nspname, t.typname) as object_reference,
                       'drop type if exists %s cascade;' as drop_template
                from   pg_type t
                       inner join pg_namespace ns on t.typnamespace = ns.oid
                where  ns.nspname not like 'pg_%'
                   and ns.nspname not in ('information_schema', '_v')
                   and not exists (select 1 from pg_depend d where t.oid = d.objid and d.deptype = 'e')
                   and not exists (select 1 from pg_class c where c.relname = t.typname and c.relnamespace = t.typnamespace and c.relkind != 'c')
                   and t.typtype in ('c', 'e', 'd')  -- only composite, enum, domain types
                --
                union all
                --
                select case when p.proisagg then 4
                            when t.typname = 'trigger' then 6
                            else 5
                       end as drop_order,
                       p.oid as object_oid,
                       case when p.proisagg then 'aggregate'
                            else 'function'
                       end as object_type,
                       format('%I.%I(%s)', ns.nspname, p.proname, pg_get_function_identity_arguments(p.oid)) as object_reference,
                       case when p.proisagg is false
                            then 'drop function if exists %s cascade;'
                            else 'drop aggregate if exists %s cascade;'
                       end as drop_template
                from   pg_proc p
                       inner join pg_namespace ns on p.pronamespace = ns.oid
                       inner join pg_type t on p.prorettype = t.oid
                       inner join pg_language pl on p.prolang = pl.oid
                where  ns.nspname not like 'pg_%'
                   and ns.nspname not in ('information_schema', '_v')
                   and not exists (select 1 from pg_depend d where p.oid = d.objid and d.deptype = 'e')
            ) objects
        ),
        dependency_pair as (
            select dep.objid as object_oid,
                   obj.type as object_type,
                   obj.identity as object_identity,
                   refobjid as ref_object_oid,
                   refobj.type as ref_object_type,
                   refobj.identity as ref_object_identity,
                   dep.deptype as dependency_type
            from   pg_depend dep,
                   lateral pg_identify_object(dep.classid, objid, 0) as obj,
                   lateral pg_identify_object(dep.refclassid, refobjid, 0) as refobj
            where  classid <> 0   -- ERROR:  unrecognized object class: 0
        ),
        dependency_hierarchy AS (
            select distinct
                   root.ref_object_oid as root_object_oid,
                   root.ref_object_type as root_object_type,
                   root.ref_object_identity as root_object_identity,
                   1 as level,
                   root.object_oid,
                   root.object_type,
                   root.object_identity,
                   root.ref_object_oid,
                   root.ref_object_type,
                   root.ref_object_identity,
                   root.dependency_type,
                   array[root.ref_object_oid] as dependency_chain,
                   root.object_type in ('view', 'type', 'composite type', 'function', 'rule', 'trigger', 'aggregate') as is_code
            from   dependency_pair root
                   join candidates_to_drop drp on root.ref_object_oid = drp.object_oid
            where  root.ref_object_type in ('view', 'type', 'composite type', 'function', 'rule', 'trigger', 'aggregate')
            union all
            select parent.root_object_oid,
                   parent.root_object_type,
                   parent.root_object_identity,
                   parent.level + 1 as level,
                   child.object_oid,
                   child.object_type,
                   child.object_identity,
                   child.ref_object_oid,
                   child.ref_object_type,
                   child.ref_object_identity,
                   child.dependency_type,
                   parent.dependency_chain || child.object_oid,
                   child.object_type in ('view', 'type', 'composite type', 'function', 'rule', 'trigger', 'aggregate') as is_code
            from   dependency_pair child
                   join dependency_hierarchy parent on (parent.object_oid = child.ref_object_oid)
            where  not (child.object_oid = any(parent.dependency_chain)) -- prevent circular referencing
        ),
        do_not_drop as (
            select root_object_oid as object_oid,
                   root_object_type as object_type,
                   root_object_identity as object_identity,
                   bool_and(is_code) filter(where dependency_type = ANY('{n,a}')) as is_code_only
            from   dependency_hierarchy
            group  by 1, 2, 3
            having bool_and(is_code) = false
        )
        select coalesce(no_drop.is_code_only, true) as is_dropped,
               o.object_type,
               o.object_reference,
               o.drop_sql
        from   candidates_to_drop o
               left join do_not_drop no_drop on o.object_oid = no_drop.object_oid
        order  by is_dropped, o.drop_order, o.object_reference, o.object_oid desc
    loop
        if _is_dropped = false then
            raise warning '% % is not dropped as non-code objects depend on it', _object_type, _object_reference;
            continue;
        end if;

        raise notice 'dropping % %', _object_type, _object_reference;
        execute _drop_sql;

        _exec_count := _exec_count + 1;  -- increment number of executed statements
  end loop;

  drop function if exists pg_temp.tmp_drop_code_objects();

  return _exec_count;
end;
$body$ language plpgsql volatile;


-- function will also delete itself
select pg_temp.tmp_drop_code_objects();

-- pg-patch before_patch.sql end --
