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
    _patch   constant text   = '<%name%>';
    _author  constant text   = '<%author%>';
    _depends constant text[] = '{<%dependencies%>}';
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
