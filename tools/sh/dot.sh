#!/bin/bash

set -e
set -o pipefail

readonly CURRENT_PATH="$( cd "$( dirname "$0" )" && pwd )"
readonly PGPATCH_PATH="$( cd "$( dirname "$( dirname "$( dirname "$0" )" )" )" && pwd )"
readonly PATCHES_LIST="$PGPATCH_PATH/patches/*.sql"

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
        if [[ $var == "--help" ]] ; then
            help
            exit 0
        # elif [[ $var == "--both" ]] || [[ $var == "-b" ]] ; then
        #     LIST_BOTH=1
        # elif [[ $var == "--local" ]] || [[ $var == "-l" ]] ; then
        #     LIST_LOCAL=1
        # elif [[ $var == "--applied" ]] || [[ $var == "-a" ]] ; then
        #     LIST_APPLIED=1
        # elif [[ $var == "--verbose" ]] || [[ $var == "-v" ]] ; then
        #     LIST_VERBOSE=1
        else
            unprocessed_args+=("$var")
        fi
    done

    local patch_dependencies=
    patch_dependencies=$($CURRENT_PATH/util-dependencies.sh "${unprocessed_args[@]}" $PATCHES_LIST)


    if [[ -n $patch_dependencies ]] ; then
        echo "digraph { "
        echo "$patch_dependencies" |
        sed 's/^/"/g' |
        sed 's/ /" -> "/g' |
        sed 's/$/";/g'
        echo "}"
    else
        echo "digraph { "
        echo "}"
    fi
}

run_dot "$@"
