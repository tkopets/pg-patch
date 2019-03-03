#!/bin/bash
set -o errexit
set -o pipefail

readonly CURRENT_PATH="$( cd "$( dirname "$0" )" && pwd )"
readonly PATCHES_LIST="$PWD/patches/*.sql"

function help {
    cat <<EOF
pg-patch list command is used to list local patches, applied or both
local and applied patches (default).

usage: pg-patch list [-c file] [-h host] [-p port] [-U user] [-d database]
                     [ [-b] | [-l] | [-a] ] [-v] [-s]

For deatiled information on connection options and config file see:
  pg-patch --help

Additional options:
  -b --both      list both local and applied patches (default)
  -l --local     list local patches in install order
  -a --applied   list already applied patches
  -v --verbose   verbose mode will print more info about the patches
  -s --silent    silently ignore patch dependency warnings

Applied patches denoted by '+', local not yet applied patches denoted by '*'.

list will exit with error if patch is applied and respective local patch is
missing or local patch is referencing non-existing patch unless '-s' is set.

If '-s' is set then missing patches are marked with '!' (exclamation mark) in
short format and filename is empty in verbose output ('-v' or '--verbose').

Usage examples:
  ./pg-patch list
  ./pg-patch list --local
  ./pg-patch list --applied
EOF
}

function run_list() {
    unprocessed_args=()
    local list_both=0
    local list_local=0
    local list_applied=0
    local list_verbose=0

    # process parameters
    for var in "$@"
    do
        if [[ $var == "--help" ]] ; then
            help
            exit 0
        elif [[ $var == "--both" ]] || [[ $var == "-b" ]] ; then
            list_both=1
        elif [[ $var == "--local" ]] || [[ $var == "-l" ]] ; then
            list_local=1
        elif [[ $var == "--applied" ]] || [[ $var == "-a" ]] ; then
            list_applied=1
        elif [[ $var == "--verbose" ]] || [[ $var == "-v" ]] ; then
            list_verbose=1
        else
            unprocessed_args+=("$var")
        fi
    done

    # debug output:
    # echo "-- all args:  $@"
    # echo "-- unprocessed args: ${unprocessed_args[@]}"

    if [[ "$list_applied" -eq 1 ]] ; then
        if [[ "$list_verbose" -eq 1 ]] ; then
            "$CURRENT_PATH/list-patches-applied-verbose.sh" "${unprocessed_args[@]}"
        else
            "$CURRENT_PATH/list-patches-applied.sh" "${unprocessed_args[@]}"
        fi
    elif [[ "$list_local" -eq 1 ]] ; then
        if [[ "$list_verbose" -eq 1 ]] ; then
            "$CURRENT_PATH/list-patches-local-verbose.sh" "${unprocessed_args[@]}" $PATCHES_LIST
        else
            "$CURRENT_PATH/list-patches-local.sh" "${unprocessed_args[@]}" $PATCHES_LIST
        fi
    else
        # default, if none specified
        if [[ "$list_verbose" -eq 1 ]] ; then
            "$CURRENT_PATH/list-patches-both-verbose.sh" "${unprocessed_args[@]}" $PATCHES_LIST
        else
            "$CURRENT_PATH/list-patches-both.sh" "${unprocessed_args[@]}" $PATCHES_LIST
        fi
    fi

    return 0
}

run_list "$@"
