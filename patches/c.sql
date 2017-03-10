/*
 * It is *VERY IMPORTANT* that code below does not do anything
 * if function _v.register_patch returned false!
 */

do
language plpgsql
$body$
declare
    -- change patch name, author and list of required patches
    _patch   text   = 'c';
    _author  text   = 'Taras Kopets <tkopets@gmail.com>';
    _depends text[] = '{a,b}';
begin
    -- try to register patch but do nothing if is not registered
    if not _v.register_patch(_patch, _author, _depends) then
        return;
    end if;

    -- ## patch fuctionality start here  ##

    --  here goes your changes to db structure!

    -- ## patch functionality ends here  ##
end;
$body$;
