-- This file adds versioning support to database it will be loaded to.
-- It requires that PL/pgSQL is already loaded - will raise exception otherwise.
-- All versioning "stuff" (tables, functions) is in "_v" schema.

-- All functions are defined as 'RETURNS SETOF INT4' to be able to make them to RETURN literaly nothing (0 rows).
-- >> RETURNS VOID<< IS similar, but it still outputs "empty line" in psql when calling.

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
    PRIMARY KEY (applied_ts, revision)
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
    COMMENT ON COLUMN _v.patches.requires    IS 'list of patches that are required for given patch';
    COMMENT ON COLUMN _v.patches.conflicts   IS 'list of patches that conflict with given patch';

    CREATE OR REPLACE FUNCTION _v.register_patch( IN in_patch_name TEXT, IN in_author TEXT, IN in_requirements TEXT[], in_conflicts TEXT[]) RETURNS boolean AS $$
    DECLARE
        t_text   TEXT;
        t_text_a TEXT[];
        i INT4;
    BEGIN
        -- locking _v.patches table is also done in main bash script
        -- nevertheless, it is locked here as well (in case patches would be installed manually)

        -- thanks to this we know only one patch will be applied at a time
        LOCK TABLE _v.patches IN EXCLUSIVE MODE;

        -- RAISE WARNING 'pg-patch: Checking patch   %', in_patch_name;

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
                raise warning 'pg-patch: Reported meta-information for patch %...', in_patch_name;
                return false;
            end if;
        exception when undefined_object then -- i.e. current_setting raises exception
            null; -- do, nothing i.e proceed with patch
        end;

        -- if patch has been already applied, return false
        -- IMPORTANT: it is the caller's responsibility to stop installing the current patch if false is returned
        SELECT patch_name INTO t_text FROM _v.patches WHERE patch_name = in_patch_name;
        IF FOUND THEN
            RAISE WARNING 'pg-patch:  + already applied: %', in_patch_name;
            RETURN FALSE;
        END IF;

        t_text_a := ARRAY( SELECT patch_name FROM _v.patches WHERE patch_name = any( in_conflicts ) );
        IF array_upper( t_text_a, 1 ) IS NOT NULL THEN
            RAISE EXCEPTION 'Versioning patches conflict. Conflicting patche(s) installed: %.', array_to_string( t_text_a, ', ' );
        END IF;

        IF array_upper( in_requirements, 1 ) IS NOT NULL THEN
            t_text_a := '{}';
            FOR i IN array_lower( in_requirements, 1 ) .. array_upper( in_requirements, 1 ) LOOP
                SELECT patch_name INTO t_text FROM _v.patches WHERE patch_name = in_requirements[i];
                IF NOT FOUND THEN
                    t_text_a := t_text_a || in_requirements[i];
                END IF;
            END LOOP;
            IF array_upper( t_text_a, 1 ) IS NOT NULL THEN
                RAISE EXCEPTION 'Missing prerequisite(s): %.', array_to_string( t_text_a, ', ' );
            END IF;
        END IF;

        RAISE WARNING 'pg-patch:  * applying patch:  %', in_patch_name;
        INSERT INTO _v.patches (patch_name, applied_ts, author, applied_by, applied_from, requires, conflicts )
               VALUES ( in_patch_name, now(), in_author, current_user, COALESCE(inet_client_addr(),'0.0.0.0'::inet), coalesce( in_requirements, '{}' ), coalesce( in_conflicts, '{}' ) );
        RETURN TRUE;
    END;
    $$ language plpgsql;
    COMMENT ON FUNCTION _v.register_patch( TEXT, TEXT, TEXT[], TEXT[] ) IS 'Function to register a patch in database. Returns false if given patch is already installed. Raises exception if prerequisite patches are not installed or there are conflicting patches.';

    -- without conflicts
    CREATE OR REPLACE FUNCTION _v.register_patch( TEXT, TEXT, TEXT[] ) RETURNS boolean AS $$
        SELECT _v.register_patch( $1, $2, $3, NULL );
    $$ language sql;
    COMMENT ON FUNCTION _v.register_patch( TEXT, TEXT, TEXT[] ) IS 'Wrapper to allow registration of patch without conflicts.';

    -- without conflicts, with single required patch
    CREATE OR REPLACE FUNCTION _v.register_patch( TEXT, TEXT, TEXT ) RETURNS boolean AS $$
        SELECT _v.register_patch( $1, $2, ARRAY[$3], NULL );
    $$ language sql;
    COMMENT ON FUNCTION _v.register_patch( TEXT, TEXT, TEXT ) IS 'Wrapper to allow registration of patch with single required patch and without conflicts.';

    -- without required patches and confilcts
    CREATE OR REPLACE FUNCTION _v.register_patch( TEXT, TEXT ) RETURNS boolean AS $$
        SELECT _v.register_patch( $1, $2, NULL, NULL );
    $$ language sql;
    COMMENT ON FUNCTION _v.register_patch( TEXT, TEXT ) IS 'Wrapper to allow registration of patch without requirements and conflicts.';

    -- remove patch
    CREATE OR REPLACE FUNCTION _v.unregister_patch( IN in_patch_name TEXT ) RETURNS boolean AS $$
    DECLARE
        i        INT4;
        t_text_a TEXT[];
    BEGIN
        -- Thanks to this we know only one patch will be applied at a time
        LOCK TABLE _v.patches IN EXCLUSIVE MODE;

        t_text_a := ARRAY( SELECT patch_name FROM _v.patches WHERE in_patch_name = ANY( requires ) );
        IF array_upper( t_text_a, 1 ) IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot uninstall patch %, as it is required by: %.', in_patch_name, array_to_string( t_text_a, ', ' );
        END IF;

        DELETE FROM _v.patches WHERE patch_name = in_patch_name;
        GET DIAGNOSTICS i = ROW_COUNT;
        IF i < 1 THEN
            RAISE EXCEPTION 'Patch % is not installed, so it can''t be uninstalled!', in_patch_name;
        END IF;

        RETURN true;
    END;
    $$ language plpgsql;
    COMMENT ON FUNCTION _v.unregister_patch( TEXT ) IS 'Function to unregister a patch in database. Raises exception if the patch is not registered or if unregistering it would break dependencies.';

    -- -------------------------------------------------------
    -- topological sort related functionality
    -- -------------------------------------------------------

    create type _v.graph_edges as (
      node_from text,
      node_to text
    );


    -- Determines a topological ordering or reports that the graph is not a DAG.
    CREATE OR REPLACE FUNCTION _v.topological_sort(_graph _v.graph_edges[])
    returns table (
      node text,
      sort_order int
    ) as
    $BODY$
    declare
        _current_node text;
        _counter int not null default 0;
    begin

        -- Create a temporary table for building the topological ordering
        CREATE temporary TABLE tmp_topological_sort_order
        (
            node text PRIMARY KEY,  -- The Node
            ordinal int NULL        -- Defines the topological ordering. NULL for nodes that are
        );                          -- not yet processed. Will be set as nodes are processed in topological order.

        -- Create a temporary copy of the edges in the graph that we can work on.
        CREATE temporary TABLE tmp_graph_edges
        (
            node_from text,  -- From Node
            node_to text,    -- To Node
            PRIMARY KEY (node_from, node_to)
        );
        -- expand all graph nodes from input array
        INSERT INTO tmp_graph_edges (node_from, node_to)
        SELECT g.node_from, g.node_to
        FROM unnest(_graph) g
        where g.node_from is not null
          and g.node_to is not null
          and g.node_from != g.node_to;

        -- Create a temporary copy of the edges in the graph that we can work on.
        CREATE temporary TABLE tmp_nodes
        (
            node  text not null,     -- node
            PRIMARY KEY (node)
        );
        -- get all unique nodes from edges
        INSERT INTO tmp_nodes (node)
        SELECT distinct g.node_from FROM unnest(_graph) g where g.node_from is not null
        union
        SELECT distinct g.node_to FROM unnest(_graph) g where g.node_to is not null;


        -- Create a temporary copy of the edges in the graph that we can work on.
        CREATE temporary TABLE tmp_temp_graph_edges
        (
            node_from text,  -- From Node
            node_to text,    -- To Node
            PRIMARY KEY (node_from, node_to)
        );

        -- Grab a copy of all the edges in the graph, as we will
        -- be deleting edges as the algorithm runs.
        INSERT INTO tmp_temp_graph_edges (node_from, node_to)
        SELECT e.node_from, e.node_to
        FROM tmp_graph_edges e;

        -- Start by inserting all the nodes that have no incoming edges, is it
        -- is guaranteed that no other nodes should come before them in the ordering.
        -- Insert with NULL for Ordinal, as we will set this when we process the node.
        INSERT INTO tmp_topological_sort_order (node, ordinal)
        SELECT n.node, NULL as ordinal
        FROM tmp_nodes n
        WHERE NOT EXISTS (
            SELECT 1 FROM tmp_graph_edges e WHERE e.node_to = n.node limit 1
        );

        -- DECLARE @CurrentNode int,    -- The current node being processed.
        --      @Counter int = 0    -- Counter to assign values to the Ordinal column.

        -- Loop until we are done.
        LOOP
            -- Reset the variable, so we can detect getting no records in the next step.
            _current_node = NULL;

            -- Select any node with [ordinal IS NULL] that is currently in our
            -- tmp_topological_sort_order table, as all nodes with [ordinal IS NULL] in this table has either
            -- no incoming edges or any nodes with edges to it have already been processed.
            SELECT tso.node
            into   _current_node
            FROM   tmp_topological_sort_order tso
            WHERE  tso.ordinal IS NULL
            order  by tso.node
            limit  1;

            -- If there are no more such nodes, we are done
            IF _current_node IS NULL THEN
                EXIT;
            END IF;

            -- We are processing this node, so set the Ordinal column of this node to the
            -- counter value and increase the counter.
            UPDATE tmp_topological_sort_order tso
            SET    ordinal = _counter
            WHERE  tso.node = _current_node;

            _counter = _counter + 1;

            -- This is the complex part. Select all nodes that has exactly ONE incoming
            -- edge - the edge from @CurrentNode. Those nodes can follow @CurrentNode
            -- in the topological ordering because the must not come after any other nodes,
            -- or those nodes have already been processed and inserted earlier in the
            -- ordering and had their outgoing edges removed in the next step.
            INSERT INTO tmp_topological_sort_order (node, ordinal)
            SELECT n.node, NULL
            FROM tmp_nodes n
            JOIN tmp_temp_graph_edges e1 ON n.node = e1.node_to -- Join on edge destination
            WHERE e1.node_from = _current_node AND  -- Edge starts in @CurrentNode
                NOT EXISTS (                            -- Make sure there are no edges to this node
                    SELECT 1 FROM tmp_temp_graph_edges e2   -- other then the one from @CurrentNode.
                    WHERE e2.node_to = n.node AND e2.node_from <> _current_node
                    limit 1
                );

            -- Last step. We are done with @CurrentNode, so remove all outgoing edges from it.
            -- This will "free up" any nodes it has edges into to be inserted into the topological ordering.
            DELETE FROM tmp_temp_graph_edges WHERE node_from = _current_node;
        END LOOP;

        -- If there are edges left in our graph after the algorithm is done, it
        -- means that it could not reach all nodes to eliminate all edges, which
        -- means that the graph must have cycles and no topological ordering can be produced.
        IF EXISTS (SELECT 1 FROM tmp_temp_graph_edges limit 1) then
            raise exception 'the graph contains cycles and no topological ordering can be produced';
            -- SELECT node_from, node_to FROM tmp_temp_graph_edges
        ELSE
            -- Select the nodes ordered by the topological ordering we produced.
            RETURN QUERY
            SELECT n.node, o.ordinal as sort_order
            FROM tmp_nodes n
            JOIN tmp_topological_sort_order o ON n.node = o.node
            ORDER BY o.ordinal;
        END IF;

        -- clean up, return.
        DROP TABLE tmp_temp_graph_edges;
        DROP TABLE tmp_topological_sort_order;
        DROP TABLE tmp_graph_edges;
        DROP TABLE tmp_nodes;

        RETURN;
    END;
    $BODY$ language plpgsql volatile;

END;
$BODYPGPATCH$;
