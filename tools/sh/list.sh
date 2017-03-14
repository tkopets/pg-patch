LIST_BOTH=0
LIST_APPLIED=0
LIST_LOCAL=0
LIST_VERBOSE=0

readonly CURRENT_PATH="$( cd "$( dirname "$0" )" && pwd )"
readonly PGPATCH_PATH="$( cd "$( dirname "$( dirname "$( dirname "$0" )" )" )" && pwd )"
readonly PATCHES_LIST="$PGPATCH_PATH/patches/*.sql"

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

    # process parameters
    for var in "$@"
    do
        if [[ $var == "--help" ]] ; then
            help
            exit 0
        elif [[ $var == "--both" ]] || [[ $var == "-b" ]] ; then
            LIST_BOTH=1
        elif [[ $var == "--local" ]] || [[ $var == "-l" ]] ; then
            LIST_LOCAL=1
        elif [[ $var == "--applied" ]] || [[ $var == "-a" ]] ; then
            LIST_APPLIED=1
        elif [[ $var == "--verbose" ]] || [[ $var == "-v" ]] ; then
            LIST_VERBOSE=1
        else
            unprocessed_args+=("$var")
        fi
    done

    # debug output:
    # echo "-- all args:  $@"
    # echo "-- unprocessed args: ${unprocessed_args[@]}"

    if [[ $LIST_APPLIED -eq 1 ]] ; then
        if [[ $LIST_VERBOSE -eq 1 ]] ; then
            $CURRENT_PATH/list-patches-applied-verbose.sh "${unprocessed_args[@]}"
        else
            $CURRENT_PATH/list-patches-applied.sh "${unprocessed_args[@]}"
        fi
    elif [[ $LIST_LOCAL -eq 1 ]] ; then
        if [[ $LIST_VERBOSE -eq 1 ]] ; then
            $CURRENT_PATH/list-patches-local-verbose.sh "${unprocessed_args[@]}" $PATCHES_LIST
        else
            $CURRENT_PATH/list-patches-local.sh "${unprocessed_args[@]}" $PATCHES_LIST
        fi
    else
        # default, if none specified
        if [[ $LIST_VERBOSE -eq 1 ]] ; then
            $CURRENT_PATH/list-patches-both-verbose.sh "${unprocessed_args[@]}" $PATCHES_LIST
        else
            $CURRENT_PATH/list-patches-both.sh "${unprocessed_args[@]}" $PATCHES_LIST
        fi
    fi

    return 0
}

run_list "$@"
