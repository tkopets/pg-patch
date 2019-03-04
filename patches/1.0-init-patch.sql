/*
 * It is *VERY IMPORTANT* that code below does not do anything
 * if the function _v.register_patch returned false!
 */

do
language plpgsql
$body$
declare
    -- change patch name, author and list of required patches
    _patch   text   = '1.0-init-patch';
    _author  text   = 'John Doe <john.doe@example.com>';
    _depends text[] = '{}';
begin
    -- try to register patch but do nothing if is not registered
    if not _v.register_patch(_patch, _author, _depends) then
        return;
    end if;

    -- ## patch fuctionality starts here  ##

    create table public.demo_table (
        id serial primary key,
        val1 integer,
        val2 text
    );

    -- initial data
    insert into demo_table(val1, val2) values(1,'a');
    insert into demo_table(val1, val2) values(2,'b');
    insert into demo_table(val1, val2) values(3,'c');
    insert into demo_table(val1, val2) values(4,'d');

    -- ## patch functionality ends here  ##
end;
$body$;
