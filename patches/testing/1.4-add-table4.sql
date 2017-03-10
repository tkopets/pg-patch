/*
 * It is *very important* that code below does not do anything,
 * if function _v.register_patch returned false!
 */

DO
LANGUAGE plpgsql $BODY$
DECLARE
    vt_patch_name CONSTANT TEXT   := '1.4-add-table4';
    vt_author     CONSTANT TEXT   := 'Anonymous <anonymous@example.com>';
    -- list required patches in array below
    va_depend_on           TEXT[] := ARRAY['1.3-add-table3']::TEXT[];
BEGIN
    -- try to register patch, skip if already applied
    IF NOT _v.register_patch(vt_patch_name, vt_author, va_depend_on) THEN
        RETURN;
    END IF;

    -- ## patch fuctionality start here  ##

    CREATE TABLE public.demo_table4 (
        id serial PRIMARY KEY
    );

    -- ## patch functionality ends here  ##
END;
$BODY$;
