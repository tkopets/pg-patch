#!/bin/bash
set -o errexit
set -o pipefail

readonly CURRENT_PATH="$( cd "$( dirname "$0" )" && pwd )"
readonly PATCH_LIST_SCRIPT="$CURRENT_PATH/util-dependencies.sh"
readonly PATCH_FILES="$PWD/patches/*.sql"

function help {
    cat <<EOF
pg-patch dot command is used to output local patches in Graphviz dot format.

usage: pg-patch dot [-c file] [-h host] [-p port] [-U user] [-d database] [-s]

For deatiled information on connection options and config file see:
  pg-patch --help

Additional options:
 -s --silent   silently ignore patch dependency warnings

Usage examples:
 ./pg-patch dot
EOF
}

function run_dot() {
    unprocessed_args=()

    # process parameters
    for var in "$@"
    do
        if [[ "$var" == "--help" ]] ; then
            help
            exit 0
        else
            unprocessed_args+=("$var")
        fi
    done

    local patches_list=
    patches_list=$("$PATCH_LIST_SCRIPT" "${unprocessed_args[@]}" $PATCH_FILES)


    if [[ -n "$patches_list" ]] ; then
        echo "digraph { "
        echo "$patches_list" |  \
        sed 's/^/"/g' |  \
        sed 's/ /" -> "/g' |  \
        sed 's/$/";/g'
        echo "}"
    else
        echo "digraph { "
        echo "}"
    fi
}

run_dot "$@"
