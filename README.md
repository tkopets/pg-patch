# pg-patch

## Installation
To setup database for the first time use:

1. Create database with `psql -h 127.0.0.1 -p 5432 -U postgres -c "CREATE DATABASE demodb;"`
2. Install pg-patch to newly created db `./pg-patch install -h 127.0.0.1 -p 5432 -U postgres -d demodb`
3. List patches to be applied to database `./pg-patch list -h 127.0.0.1 -p 5432 -U postgres -d demodb`
4. Test the deployment of patches `./pg-patch deploy -h 127.0.0.1 -p 5432 -U postgres -d demodb --dry-run`
5. Install all the patches `./pg-patch deploy -h 127.0.0.1 -p 5432 -U postgres -d demodb`

## Patch
```sh
./pg-patch -h 127.0.0.1 -p 5432 -U demodb_owner -d demodb
```
