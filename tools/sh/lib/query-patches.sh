#!/bin/bash

# Usage and options are similar to main run.sh,
# but list of files should be supplied in the end
# query-patches.sh -h localhost -p 5432 -U postgres -d demodb patches/*.sql

# source query-patches.sh located in the same dir
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/read-db-args.sh"


set -e

FILES=''


function help {
    cat <<EOF

This a helper script intended to aid executing arbitrary
queries to find out meta-information about available
local patches that are usualy stored in patches/ folder.
Meta information is available for queries in temporary
table called "tmp_local_patches".

List of options:

 --help                   - prints this message.

Connection settings:
 -h --host <host>         - target host name
 -d --database <database> - target database name
 -p --port <port>         - database server port name
 -U --user <user>         - database user
 .. list of local files to process (e.g. "patches/*.sql" )

Usage examples:
 In other script (e.g. local-patches.sh):

 ----------------- bash source -----------------
  #!/bin/bash

  # source query-patches.sh (same dir)
  DIR="${BASH_SOURCE%/*}"
  if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
  . "$DIR/query-patches.sh"

  query_patches  "select * from tmp_local_patches;"
 ----------------- bash source -----------------

 Your script will need same db connection args for execution:
 ./local-patches.sh -d demodb -h localhost -U postgres -p 5432
EOF
}

check_versioning_query="
do
'
begin
    if not exists(select 1 from pg_catalog.pg_namespace where nspname = ''_v'') then
        raise exception ''pg-patch is not installed'';
    end if;

    return;
end;
';
"


check_depend_patches_query="
do
'
declare
    _rec record;
begin

    select string_agg(patch_name, '', '') as patch_name, string_agg(dependency, '', '') as missing_dependency
    into   _rec
    from  (
            select patch_name, unnest(requires) as dependency
            from   tmp_local_patches lp
            where  requires is not null
               and requires <> ''{}''
          ) p
    where not exists (
            select 1
            from   tmp_local_patches chk
            where  p.dependency = chk.patch_name
    );
    
    if _rec is not null then
        raise exception ''missing dependent local patch(es) [%] required from [%]'', _rec.missing_dependency, _rec.patch_name
                        using ERRCODE = ''undefined_object'';
    end if;
end;
';
"

check_local_patches_query="
do
'
begin
    if exists(select 1 from tmp_local_patches) then
        return;
    end if;

exception when undefined_table then
    raise exception ''local patches not found'';
end;
';
"

function sed_bin() {
    if [[ ${OSTYPE//[0-9.]} == "solaris" ]]; then
        gsed "$@"
    else
        sed "$@"
    fi
}

function sed_strip_utf8_bom() {
    if [[ "$OSTYPE" == "darwin"*  ]]; then
        # Mac OSX
        sed_bin $'s/^\xEF\xBB\xBF//' "$@"
    else
        # others
        sed_bin 's/^\xEF\xBB\xBF//'  "$@"
    fi
}

function sed_remove_commit() {
    if [[ "$OSTYPE" == "darwin"*  ]]; then
        # Mac OSX
        sed_bin 's/^[[:space:]]*commit[[:space:]]*\;//' "$@" | sed_bin 's/COMMIT[[:space:]]*\;//'
    else
        # others
        sed_bin 's/^[[:space:]]*commit[[:space:]]*\;//i' "$@"
    fi
}

# function does some sting manipulation to arrive at following file structure, suitable for feeding into psql:
# desired structure:
# \o /dev/null                                 # ONCE: suppresses command and query output in psql
# BEGIN;                                       # ONCE: do everything in one transaction
# \set pgpatch_filename /path/file.sql         # EACH FILE: set postgresql & psql variables that are later
# set pgpatch.current_patch_file = '/p/f.sql'; # EACH FILE: used in _v.register_patch to save patch meta-info
#
# CONTENTS of file from [patches] dir          # EACH FILE: contents
#
# ..
# .. EACH FILE: section is repeated for each file
# ..
#
# \o                                           # ONCE: reset to usual psql output mode
# select patch_name                            # ONCE: query string passed as param is placed here. Temp table
# from tmp_local_patches;                      # [tmp_local_patches] available (metadata about local patches).
#
# ROLLBACK;                                    # ONCE: rollbacks transaction (started at the beginning)

# OTHER NOTES:
# There is a stong assumtion that patches do not use transaction management commands like
# BEGIN, ROLLBACK and most importantly COMMIT.
# Otherwise, this would prematurely commit/rollback our nice all in one transaction change.
# This may easily leave target DB in inconsistent state.
# Very simplistic stripping of "COMMIT" is performed by sed, however this imposes
# some risk on replacing something that was not intended.

function query_patches() {
    local query=$1
    local extra_psql_args=$2
    local query_results=''
    local sql_header_file="$DIR/../../sql/header.sql"

    # sane default
    if [[  $extra_psql_args = '' ]]
    then
        extra_psql_args="--quiet --tuples-only --no-align --pset pager=off"
    fi

    local pre_patches=$(
        echo '\o /dev/null'
        echo 'BEGIN;'
        echo
        sed_strip_utf8_bom $sql_header_file
        echo
        echo "SET client_min_messages = error;"
        echo
        echo $check_versioning_query
        echo
    )

    local patches=$(
        for i in $FILES ; do
            echo
            echo '-- setting pgpatch_filename psql variable'
            echo '\set' pgpatch_filename $i
            echo "set pgpatch.current_patch_file = :'pgpatch_filename';"
            echo
            sed_strip_utf8_bom $i | sed_remove_commit
            echo
        done
    )

    local check_local_query=''
    if [ "$FILES" != '' ] ; then
        check_local_query=$check_local_patches_query
    fi

    local check_depend_query=''
    if [ $SILENT_FLAG_SET -eq 0 ] && [ "$FILES" != '' ] ; then
        check_depend_query=$check_depend_patches_query
    fi

    local post_patches=$(
        echo
        echo '\o'
        echo "$query"
        echo
        echo 'ROLLBACK;'
        echo
    )

    query_results=$(echo "$pre_patches $patches $check_local_query $check_depend_query $post_patches" | \
        PGAPPNAME='pg-patch (query-local)' PGOPTIONS='--client-min-messages=error' psql --no-psqlrc -v ON_ERROR_STOP=1 $extra_psql_args -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DATABASE"
    )

    # on Windows trim additional "\r" from line endings ("\r\n")
    echo "$query_results" | sed_bin $'s/\r$//';
}

function read_local_args() {
    local arg=

    for arg
    do
        local delim=""
        case "$arg" in
            --help)           help && exit 0;;
        esac
    done
    
    # assign leftovers to files
    FILES="$@"

    return 0
}

function main() {
    # get db related args
    read_db_args $ARGS

    # read other args
    # variable DBARGS_LEFTOVERS defined in read-db-args.sh
    read_local_args $DBARGS_LEFTOVERS
}

main
