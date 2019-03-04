This directory contains patch scripts.

Sample patch script below:

```
/*
 * It is *VERY IMPORTANT* that code below does not do anything
 * if the function _v.register_patch returned false!
 */

do
language plpgsql
$body$
declare
    -- change patch name, author and list of required patches
    _patch   text   = '1.0-init-patch';  -- same as filename
    _author  text   = 'John Doe <john.doe@example.com>';
    _depends text[] = '{dependency1,dependency2}';
begin
    -- try to register patch but do nothing if is not registered
    if not _v.register_patch(_patch, _author, _depends) then
        return;
    end if;

    -- ## patch fuctionality starts here  ##

    --  here goes your changes to db structure!

    -- ## patch functionality ends here  ##
end;
$body$;
```
