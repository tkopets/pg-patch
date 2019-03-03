#!/bin/bash
set -o errexit
set -o pipefail

# source read-db-args.sh located in lib dir
readonly DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/lib/read-db-args.sh"


function help {
    cat <<EOF
pg-patch install command is used to install pg-patch to database.

usage: pg-patch install [-c file] [-h host] [-p port] [-U user] [-d database]

For deatiled information on connection options and config file see:
  pg-patch --help

Usage examples:
 ./pg-patch install
EOF
}

function read_args() {
    unprocessed_args=()

    # debug output:
    # echo "-- all args:  $@"

    # process parameters
    for var in "$@"
    do
        if [[ $var == "--help" ]] ; then
            help
            exit 0
        else
            unprocessed_args+=("$var")
        fi
    done

    # debug output:
    # echo "-- unprocessed args: ${unprocessed_args[@]}"

    read_db_args "${unprocessed_args[@]}"

    # debug output:
    # echo "-- DBHOST:    $DBHOST"
    # echo "-- DBPORT:    $DBPORT"
    # echo "-- DBUSER:    $DBUSER"
    # echo "-- DATABASE:  $DATABASE"
    # echo "-- SILENT:    $SILENT_FLAG_SET"

    return 0
}

function run_install() {
    PGAPPNAME='pg-patch (main)' \
        psql -X -v ON_ERROR_STOP=1 --pset pager=off \
        -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DATABASE" \
        -f "$DIR/../sql/install_versioning.sql" 2>&1
    EXITCODE=$?

    if [ "$EXITCODE" -eq 0 ]
    then
      echo "Successfully installed pg-patch"
    else
      echo "Could not install pg-patch"
    fi

    exit "$EXITCODE"
}

# read args
read_args "$@"

run_install

