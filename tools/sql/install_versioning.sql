-- pg-patch install_versioning.sql start --

-- This file adds versioning support to the database it will be loaded to.
-- It requires that PL/pgSQL is already loaded - will raise exception otherwise.
-- All versioning "stuff" (tables, functions) is in "_v" schema.

DO
LANGUAGE PLPGSQL
$BODYPGPATCH$
BEGIN

    if exists(select 1 from pg_catalog.pg_namespace where nspname = '_v') then
        return;  -- do nothing, if pg-patch is already installed
    end if;

    CREATE SCHEMA _v;
    COMMENT ON SCHEMA _v IS 'Schema for versioning data and functionality.';

    CREATE TABLE _v.patch_history (
        applied_ts timestamptz NOT NULL DEFAULT now(),
        revision   text,
        branch     text,
        PRIMARY KEY (applied_ts)
    );
    COMMENT ON TABLE _v.patch_history             IS 'Contains history of dates and revisions of applied pathces';
    COMMENT ON COLUMN _v.patch_history.applied_ts IS 'date when pach was applied';
    COMMENT ON COLUMN _v.patch_history.revision   IS 'patch revision';
    COMMENT ON COLUMN _v.patch_history.branch     IS 'branch name';

    CREATE TABLE _v.patches (
        patch_name  TEXT        PRIMARY KEY,
        applied_ts  TIMESTAMPTZ NOT NULL DEFAULT now(),
        author      TEXT        NOT NULL,
        applied_by  TEXT        NOT NULL,
        applied_from INET       NOT NULL,
        requires    TEXT[],
        conflicts   TEXT[]
    );
    COMMENT ON TABLE _v.patches              IS 'Contains information about what patches are currently applied on database.';
    COMMENT ON COLUMN _v.patches.patch_name  IS 'name of patch, has to be unique for every patch';
    COMMENT ON COLUMN _v.patches.applied_ts  IS 'when the patch was applied';
    COMMENT ON COLUMN _v.patches.applied_by  IS 'who applied this patch (PostgreSQL username)';
    COMMENT ON COLUMN _v.patches.applied_from IS 'client IP who applied this patch';
    COMMENT ON COLUMN _v.patches.requires    IS 'list of patches that are required for given patch';
    COMMENT ON COLUMN _v.patches.conflicts   IS 'list of patches that conflict with given patch';

    CREATE OR REPLACE FUNCTION _v.register_patch(in_patch_name TEXT, in_author TEXT,
                                                 in_requirements TEXT[] default null,
                                                 in_conflicts TEXT[] default null
    )
    RETURNS boolean
    AS $$
    DECLARE
        t_text   TEXT;
        t_text_a TEXT[];
        i INT4;
        _output_reported constant text := 'pg-patch: Reported meta-information for patch %...';
        _output_applied  constant text := 'pg-patch:  + already applied: %';
        _output_progress constant text := 'pg-patch:  * applying patch:  %';
    BEGIN
        -- locking _v.patches table is also done in main bash script
        -- nevertheless, it is locked here as well (in case patches would be installed manually)

        -- thanks to this we know only one patch will be applied at a time
        LOCK TABLE _v.patches IN EXCLUSIVE MODE;

        IF in_patch_name IS NULL OR TRIM(in_patch_name) = '' THEN
            RAISE EXCEPTION 'Cannot register patch. Name is null or empty.';
        END IF;

        IF in_author IS NULL OR TRIM(in_author) = '' THEN
            RAISE EXCEPTION 'Cannot register patch. Author is not specified.';
        END IF;

        -- special case: only patch meta-information is collected and false is returned
        -- to prevent further patch instalation
        -- IMPORTANT: it is the caller's responsibility to stop installing the current patch if false is returned
        begin
            if current_setting('pgpatch.current_patch_file') != '' then
                create temp table if not exists tmp_local_patches(patch_name text primary key, author text not null, requires text[], filename text not null);
                insert into tmp_local_patches values(in_patch_name, in_author, in_requirements, current_setting('pgpatch.current_patch_file'));
                raise warning _output_reported, in_patch_name;
                return false;
            end if;
        exception when undefined_object then -- i.e. current_setting raises exception
            null; -- do, nothing i.e proceed with patch
        end;

        -- if patch has been already applied, return false
        -- IMPORTANT: it is the caller's responsibility to stop installing the current patch if false is returned
        SELECT patch_name INTO t_text FROM _v.patches WHERE patch_name = in_patch_name;
        IF FOUND THEN
            RAISE WARNING _output_applied, in_patch_name;
            RETURN FALSE;
        END IF;

        t_text_a := ARRAY(SELECT patch_name FROM _v.patches WHERE patch_name = any(in_conflicts));
        IF array_upper(t_text_a, 1) IS NOT NULL THEN
            RAISE EXCEPTION 'Versioning patches conflict. Conflicting patche(s) installed: %.', array_to_string(t_text_a, ', ');
        END IF;

        IF array_upper(in_requirements, 1) IS NOT NULL THEN
            t_text_a := '{}';
            FOR i IN array_lower(in_requirements, 1) .. array_upper(in_requirements, 1) LOOP
                SELECT patch_name INTO t_text FROM _v.patches WHERE patch_name = in_requirements[i];
                IF NOT FOUND THEN
                    t_text_a := t_text_a || in_requirements[i];
                END IF;
            END LOOP;
            IF array_upper(t_text_a, 1) IS NOT NULL THEN
                RAISE EXCEPTION 'Missing prerequisite(s): %.', array_to_string(t_text_a, ', ');
            END IF;
        END IF;

        RAISE WARNING _output_progress, in_patch_name;
        INSERT INTO _v.patches (patch_name, applied_ts, author, applied_by, applied_from, requires, conflicts)
               VALUES (in_patch_name, now(), in_author, current_user, COALESCE(inet_client_addr(),'0.0.0.0'::inet), coalesce(in_requirements, '{}'), coalesce(in_conflicts, '{}'));
        RETURN TRUE;
    END;
    $$ language plpgsql;
    COMMENT ON FUNCTION _v.register_patch(TEXT, TEXT, TEXT[], TEXT[]) IS 'Function to register a patch in database. Returns false if given patch is already installed. Raises exception if prerequisite patches are not installed or there are conflicting patches.';

    -- without conflicts, with single required patch
    CREATE OR REPLACE FUNCTION _v.register_patch(TEXT, TEXT, TEXT) RETURNS boolean AS $$
        SELECT _v.register_patch($1, $2, ARRAY[$3], NULL);
    $$ language sql;
    COMMENT ON FUNCTION _v.register_patch(TEXT, TEXT, TEXT) IS 'Wrapper to allow registration of patch with single required patch and without conflicts.';

    -- remove patch
    CREATE OR REPLACE FUNCTION _v.unregister_patch(IN in_patch_name TEXT) RETURNS boolean AS $$
    DECLARE
        i        INT4;
        t_text_a TEXT[];
    BEGIN
        -- Thanks to this we know only one patch will be applied at a time
        LOCK TABLE _v.patches IN EXCLUSIVE MODE;

        t_text_a := ARRAY(SELECT patch_name FROM _v.patches WHERE in_patch_name = ANY(requires));
        IF array_upper(t_text_a, 1) IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot uninstall patch %, as it is required by: %.', in_patch_name, array_to_string(t_text_a, ', ');
        END IF;

        DELETE FROM _v.patches WHERE patch_name = in_patch_name;
        GET DIAGNOSTICS i = ROW_COUNT;
        IF i < 1 THEN
            RAISE EXCEPTION 'Patch % is not installed, so it can''t be uninstalled!', in_patch_name;
        END IF;

        RETURN true;
    END;
    $$ language plpgsql;
    COMMENT ON FUNCTION _v.unregister_patch(TEXT) IS 'Function to unregister a patch in database. Raises exception if the patch is not registered or if unregistering it would break dependencies.';


    CREATE OR REPLACE FUNCTION _v.assert_patch_is_applied(in_patch_name TEXT) RETURNS TEXT as $$
    DECLARE
        t_text TEXT;
    BEGIN
        SELECT patch_name INTO t_text FROM _v.patches WHERE patch_name = in_patch_name;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Patch % is not applied!', in_patch_name;
        END IF;
        RETURN format('Patch %s is applied.', in_patch_name);
    END;
    $$ language plpgsql;
    COMMENT ON FUNCTION _v.assert_patch_is_applied(TEXT) IS 'Function that can be used to make sure that patch has been applied.';


    CREATE OR REPLACE FUNCTION _v.assert_user_is_superuser() RETURNS TEXT as $$
    DECLARE
        v_super bool;
    BEGIN
        SELECT usesuper INTO v_super FROM pg_user WHERE usename = current_user;
        IF v_super THEN
            RETURN 'assert_user_is_superuser: OK';
        END IF;
        RAISE EXCEPTION 'Current user is not superuser - cannot continue.';
    END;
    $$ language plpgsql;
    COMMENT ON FUNCTION _v.assert_user_is_superuser() IS 'Function that can be used to make sure that patch is being applied using superuser account.';


    CREATE OR REPLACE FUNCTION _v.assert_user_is_not_superuser() RETURNS TEXT as $$
    DECLARE
        v_super bool;
    BEGIN
        SELECT usesuper INTO v_super FROM pg_user WHERE usename = current_user;
        IF v_super THEN
            RAISE EXCEPTION 'Current user is superuser - cannot continue.';
        END IF;
        RETURN 'assert_user_is_not_superuser: OK';
    END;
    $$ language plpgsql;
    COMMENT ON FUNCTION _v.assert_user_is_not_superuser() IS 'Function that can be used to make sure that patch is being applied using normal (not superuser) account.';


    CREATE OR REPLACE FUNCTION _v.assert_user_is_one_of(VARIADIC p_acceptable_users TEXT[]) RETURNS TEXT as $$
    DECLARE
    BEGIN
        IF current_user = any(p_acceptable_users) THEN
            RETURN 'assert_user_is_one_of: OK';
        END IF;
        RAISE EXCEPTION 'User is not one of: % - cannot continue.', p_acceptable_users;
    END;
    $$ language plpgsql;
    COMMENT ON FUNCTION _v.assert_user_is_one_of(TEXT[]) IS 'Function that can be used to make sure that patch is being applied by one of defined users.';


    -- -------------------------------------------------------
    -- topological sort related functionality
    -- -------------------------------------------------------

    create type _v.graph_edges as (
      node_from text,
      node_to text
    );


    -- Determines a topological ordering or reports that the graph is not a DAG.
    create or replace function _v.topological_sort(_graph _v.graph_edges[])
    returns table (
      node text,
      sort_order int
    )
    as $body$
    declare
        _nodes text[];
        _edges _v.graph_edges[];
        _ordered_nodes text[] default '{}';
        _next_nodes text[];
        _cur_node_from text;
        _all_nodes_to text[];
        _cur_node_to text;
        _n_m_edges text[];
    begin
        _edges = array(
            select row(g.node_from, g.node_to)::_v.graph_edges
            from unnest(_graph) g
            where g.node_from is not null
              and g.node_to is not null
              and g.node_from != g.node_to
        );

        _nodes = array(
            select nodes
            from (
                select distinct node_from as nodes from unnest(_graph) where node_from is not null
                union
                select distinct node_to as nodes from unnest(_graph) where node_to is not null
            ) x
            order by 1
        );

        _next_nodes = array(
            select n.nodes
            from   unnest(_nodes) n (nodes)
            where not exists (
                select 1 from unnest(_edges) e where e.node_to = n.nodes
            )
            order by n.nodes
        );

        -- no top level node, just return all nodes
        if array_length(_next_nodes, 1) is null then
            return query
                select ordered_nodes, (row_number() over ())::int as sort_order
                from  (
                   select unnest(_nodes) as ordered_nodes
                   order by 1
                ) x;
            return;
        end if;

        while array_length(_next_nodes, 1) is not null loop
            _cur_node_from := _next_nodes[1];
            _next_nodes := _next_nodes[2:];

            _ordered_nodes := array_append(_ordered_nodes, _cur_node_from);
            _all_nodes_to = array(
                select e.node_to
                from   unnest(_edges) e
                where  e.node_from = _cur_node_from
                order by 1
            );

            foreach _cur_node_to in array _all_nodes_to loop
                _n_m_edges = array(
                    select e.node_from
                    from   unnest(_edges) e
                    where  e.node_to = _cur_node_to
                    order by 1
                );

                if _n_m_edges = array[_cur_node_from] then
                    _next_nodes := array_append(_next_nodes, _cur_node_to);
                    _edges = array(
                        select row(e.node_from, e.node_to)::_v.graph_edges
                        from   unnest(_edges) e
                        where  e.node_to <> _cur_node_to
                        order by 1
                    );
                else
                    _edges = array(
                        select row(e.node_from, e.node_to)::_v.graph_edges
                        from   unnest(_edges) e
                        where  not (e.node_to = _cur_node_to and e.node_from = _cur_node_from)
                        order by 1
                    );
                end if;
            end loop;
        end loop;
        if _edges <> '{}' then
            raise exception 'input graph contains cycles';
        end if;

        return query
          select ordered_nodes, (row_number() over ())::int as sort_order
          from  (
             select unnest(_ordered_nodes) as ordered_nodes
          ) x;
    end
    $body$ language plpgsql immutable strict;

END;
$BODYPGPATCH$;

-- pg-patch install_versioning.sql end --
