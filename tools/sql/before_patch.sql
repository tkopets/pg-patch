-- pg-patch before_patch.sql start --

-- function to drop recreatable objects
CREATE OR REPLACE FUNCTION pg_temp.tmp_drop_recreatable_objects()
RETURNS INTEGER AS $BODY$
DECLARE
  _sql TEXT;
  _exec_count INTEGER NOT NULL DEFAULT 0;
  BEGIN
  -- drop rules
  FOR _sql IN
        SELECT 'DROP RULE IF EXISTS '|| quote_ident(r.rulename) ||
               ' ON '|| quote_ident(ns.nspname)||'.'||quote_ident(c.relname)||';'
        FROM   pg_catalog.pg_rewrite r
               INNER JOIN pg_class c ON r.ev_class = c.oid
               INNER JOIN pg_namespace ns ON c.relnamespace = ns.oid
        WHERE  r.rulename != '_RETURN'
           AND ns.nspname NOT LIKE 'pg_%'
           AND ns.nspname NOT IN ('information_schema', '_v')
           AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE c.oid = d.objid AND d.deptype = 'e')
  LOOP
      RAISE NOTICE 'about to drop rule: %', _sql;
      EXECUTE _sql;
      _exec_count := _exec_count + 1;  -- increment number of executed statements
  END LOOP;

  -- drop views
  FOR _sql IN
        SELECT 'DROP VIEW IF EXISTS '||quote_ident(ns.nspname)||'.'||quote_ident(c.relname)||' CASCADE;'
        FROM   pg_class c
               INNER JOIN pg_namespace ns ON c.relnamespace = ns.oid
        WHERE  c.relkind = 'v'  -- views
           AND ns.nspname NOT LIKE 'pg_%'
           AND ns.nspname NOT IN ('information_schema', '_v')
           AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE c.oid = d.objid AND d.deptype = 'e')
  LOOP
      RAISE NOTICE 'about to drop view: %', _sql;
      EXECUTE _sql;
      _exec_count := _exec_count + 1;  -- increment number of executed statements
  END LOOP;

  -- drop types
  FOR _sql IN
        SELECT 'DROP TYPE IF EXISTS '||quote_ident(nspname)||'.'||quote_ident(typname)||' CASCADE;'
          FROM (
                SELECT DISTINCT t.typname, ns.nspname
                FROM   pg_proc p
                       INNER JOIN pg_type t ON p.prorettype = t.oid
                       INNER JOIN pg_namespace ns ON p.pronamespace = ns.oid
                WHERE  t.typtype IN ('c','e','d')  -- only composite, enum, domain types
                   AND ns.nspname NOT LIKE 'pg_%'
                   AND ns.nspname NOT IN ('information_schema', '_v')
                   AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE t.oid = d.objid AND d.deptype = 'e')
               ) disttyp
  LOOP
      RAISE NOTICE 'about to drop type: %', _sql;
      EXECUTE _sql;
      _exec_count := _exec_count + 1;  -- increment number of executed statements
  END LOOP;

  -- drop functions (including aggregates and triggers)
  FOR _sql IN
        SELECT CASE WHEN p.proisagg IS FALSE THEN 'DROP FUNCTION IF EXISTS '
               ELSE 'DROP AGGREGATE IF EXISTS ' END
               ||quote_ident(ns.nspname)||'.'||quote_ident(p.proname)
               ||'('||COALESCE(pg_get_function_identity_arguments(p.oid),'')||') CASCADE;'
        FROM   pg_proc p
               INNER JOIN pg_namespace ns ON p.pronamespace = ns.oid
               INNER JOIN pg_type t ON p.prorettype = t.oid
               INNER JOIN pg_language pl on p.prolang = pl.oid
        WHERE  ns.nspname NOT LIKE 'pg_%'
           AND ns.nspname NOT IN ('information_schema', '_v')
           AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE p.oid = d.objid AND d.deptype = 'e')
         ORDER BY t.typname = 'trigger', p.proisagg DESC, ns.nspname  -- triggers last, aggregates first !
  LOOP
      RAISE NOTICE 'about to drop function: %', _sql;
      EXECUTE _sql;
      _exec_count := _exec_count + 1;  -- increment number of executed statements
  END LOOP;

  DROP FUNCTION IF EXISTS pg_temp.tmp_drop_recreatable_objects();

  RETURN _exec_count;
END;
$BODY$ LANGUAGE plpgsql VOLATILE;


-- function will also delete itself
SELECT pg_temp.tmp_drop_recreatable_objects();

-- pg-patch before_patch.sql end --
