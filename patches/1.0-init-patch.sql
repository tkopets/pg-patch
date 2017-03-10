/*
 * Do not change this code except lines containing patch name, author name
 * and lines between ## patch functionality start, functionality end.
 * DO NOT CHANGE names of variables, because there are scripts that use them.
 */

DO
LANGUAGE plpgsql $BODY$
DECLARE
    vt_patch_name CONSTANT TEXT   := '1.0-init-patch';
    vt_author     CONSTANT TEXT   := 'Anonymous <anonymous@example.com>';
    -- list required patches in array below
    va_depend_on           TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- try to register patch, skip if already applied
    IF NOT _v.register_patch(vt_patch_name, vt_author, va_depend_on) THEN
        RETURN;
    END IF;

    -- ## patch fuctionality start here  ##

    CREATE TABLE public.demo_table (
        id bigserial PRIMARY KEY,
        val1 integer,
        val2 text
    );

    -- initial data
    INSERT INTO demo_table(val1, val2) VALUES(1,'a');
    INSERT INTO demo_table(val1, val2) VALUES(2,'b');
    INSERT INTO demo_table(val1, val2) VALUES(3,'c');
    INSERT INTO demo_table(val1, val2) VALUES(4,'d');

    -- ## patch functionality ends here  ##
END;
$BODY$;
