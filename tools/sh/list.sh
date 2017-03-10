LIST_BOTH=0
LIST_APPLIED=0
LIST_LOCAL=0
LIST_VERBOSE=0

readonly CURRENT_PATH="$( cd "$( dirname "$0" )" && pwd )"
readonly PGPATCH_PATH="$( cd "$( dirname "$( dirname "$( dirname "$0" )" )" )" && pwd )"
readonly PATCHES_LIST="$PGPATCH_PATH/patches/*.sql"

function help {
    cat <<EOF
This is help for pgpatch list command, that is used to list
local patches, applied or both local and applied.

Default options could be supplied in database.conf file.
Example file could be found in database.conf.default

List of options:
 --help              - prints this message.

Connection settings:
 -h --host <host>    - target host name
 -p --port <port>    - database server port name
 -U --user <user>    - database user
 -d --database <db>  - target database name

Behaviour flags:
 -s --silent         - silently ignore patch dependency warnings
 -v --verbose        - verbose mode with more info about the patches

Usage examples:
 pgpatch list -h localhost -p 5432 -U demodb -d demodb
 pgpatch list --local --silent -h localhost -p 5432 -U demodb -d demodb
 pgpatch list --applied -h localhost -p 5432 -U demodb -d demodb
 pgpatch list -c path/to/database.conf
 pgpatch list # assuming default config is present
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
