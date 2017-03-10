/*
 * Do not change this code except lines containing patch name, author name
 * and lines between ## patch functionality start, functionality end.
 * DO NOT CHANGE names of variables, because there are scripts that use them.
 */

DO
LANGUAGE plpgsql $BODY$
DECLARE

    /*
     * CHANGE PATCH NAME AND AUTHOR
     */
     -- patch name should be the same as file name
    vt_patch_name CONSTANT TEXT   := '1.2-add-audit';
    vt_author     CONSTANT TEXT   := 'Author Name (author@email.net)';  -- Patch author

    -- ! PUT REQUIRED PATCHES HERE
    va_depend_on           TEXT[] := ARRAY['1.1-add-table-demo-table2']::TEXT[];
    -- ! PUT CONFLICTING PATCHES HERE
    --va_conflict_with       TEXT[] -- reserved for future

BEGIN

    -- try to register patch, skip if already applied
    IF NOT _v.register_patch(vt_patch_name, vt_author, va_depend_on) THEN
        RETURN;
    END IF;

    -- ## patch fuctionality start here  ##
    CREATE TABLE public.logged_actions (
        event_id serial primary key,
        event_data text
    );

    -- ## patch functionality ends here  ##

END;
$BODY$;
