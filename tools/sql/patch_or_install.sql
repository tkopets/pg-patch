-- pg-patch patch_or_install.sql start --

set pgpatch.db_check_result = '';

do language plpgsql
$body$
declare
    va_schemas text[];
begin
    -- versioning schema present ?
    if exists (select 1
                 from pg_catalog.pg_namespace n
                where n.nspname !~ '^pg_'
                  and n.nspname <> 'information_schema'
                  and n.nspname = '_v')
    then
        perform set_config('pgpatch.db_check_result', 'patch', false);
    else
        -- No versioning? any schemas?
        select array_agg(n.nspname::text)
          into va_schemas
          from pg_catalog.pg_namespace n
         where n.nspname !~ '^pg_'
           and n.nspname <> 'information_schema';

        if array_length(va_schemas, 1) = 1 and va_schemas[1] = 'public' then
            -- only public? any tables?
            if exists ( select 1
                          from pg_catalog.pg_class c
                          join pg_catalog.pg_namespace n
                            on c.relnamespace = n.oid
                           and n.nspname = 'public'
                           and c.relkind IN ('r', 'v', 'f', 'S')
                         where not exists (select 1 from pg_depend d where c.oid = d.objid and d.deptype = 'e'))
            then
                raise exception 'Database % is not empty', current_database();
            else
                -- install versioning
                perform set_config('pgpatch.db_check_result', 'install', false);
            end if;
        elsif array_length(va_schemas, 1) >= 1 then
            raise exception 'Database % is not empty and pg-patch is not installed', current_database();
        end if;
    end if;

    return;
end;
$body$;

select current_setting('pgpatch.db_check_result');

-- pg-patch patch_or_install.sql end --
