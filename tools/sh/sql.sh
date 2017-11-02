#!/bin/bash

set -e

# source read-db-args.sh located in lib dir
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/lib/read-db-args.sh"


readonly DB_PATH="$( cd "$( dirname "$( dirname "$( dirname "$0" )" )" )" && pwd )"

LOAD_BASE=0;
DRY_RUN=0;


function help {
    cat <<EOF
pg-patch sql command is used to generate SQL for patching DB
the output could be applied using psql to any DB.

usage: pg-patch sql [-c file] [-h host] [-p port] [-U user] [-d database]
                    [-i] [-0] [-s]

For deatiled information on connection options and config file see:
  pg-patch --help

Additional options:
  -i --install   install pg-patch, SQL will contain both pg-patch and patches
  -0 --dry-run   SQL will contain rollback at the end (for testing)
  -s --silent    silently ignore patch dependency warnings

Usage examples:
  ./pg-patch sql
  ./pg-patch sql --dry-run
  ./pg-patch sql --install
EOF
}


# Functions ========================================

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

function grep_bin() {
    if [[ ${OSTYPE//[0-9.]} == "solaris" ]]; then
        ggrep "$@"
    else
        grep "$@"
    fi
}

function get_recreatable_objects_path {
    local CODE_PATH=''
    if [[ -d "$PWD/code/types/" ]] ; then
        CODE_PATH="$CODE_PATH $PWD/code/types/"
    fi
    if [[ -d "$PWD/code/functions/" ]] ; then
        CODE_PATH="$CODE_PATH $PWD/code/functions/"
    fi
    if [[ -d "$PWD/code/views/" ]] ; then
        CODE_PATH="$CODE_PATH $PWD/code/views/"
    fi
    if [[ -d "$PWD/code/rules/" ]] ; then
        CODE_PATH="$CODE_PATH $PWD/code/rules/"
    fi
    if [[ -d "$PWD/code/triggers/" ]] ; then
        CODE_PATH="$CODE_PATH $PWD/code/triggers/"
    fi

    echo $CODE_PATH
}

function load_versioning() {
    sed_strip_utf8_bom $DB_PATH/tools/sql/install_versioning.sql
}

function get_patches_install_order() {
    local SILENT_FLAG=''

    if [[ $SILENT_FLAG_SET -eq 1 ]] ; then
        SILENT_FLAG=' -s '
    fi

    $DIR/util-patch-files.sh -h $DBHOST -p $DBPORT -U $DBUSER -d $DATABASE $SILENT_FLAG $PWD/patches/*.sql
}

function lock_for_patch(){

    sed_strip_utf8_bom $DB_PATH/tools/sql/header.sql

    # get repository revision global ID and branch name
    #if git
    if hash git 2> /dev/null &&  git rev-parse --git-dir > /dev/null 2>&1 ; then
        REVISION=`git rev-parse HEAD`
        BRANCH=`git rev-parse --abbrev-ref HEAD`
        #if hg
    elif hash hg 2> /dev/null && hg root > /dev/null 2>&1 ; then
        REVISION==`hg id -i`
        BRANCH=`hg id -b`
    elif [ -f repo.info ] ; then
        . repo.info
        REVISION=$B_REVISION
        BRANCH=$B_BRANCH
    else
        REVISION='Unknown. No version control info found'
        BRANCH='Unknown. No version control info found'
    fi

    # start transaction
    echo "BEGIN;"
    echo

    if [[ $LOAD_BASE -eq 1 ]] ; then
        load_versioning
    fi

    # Thanks to this we know only one patch will be applied at a time
    echo "LOCK TABLE _v.patches IN EXCLUSIVE MODE;"
    echo

    echo "INSERT INTO _v.patch_history(revision, branch) VALUES('$REVISION','$BRANCH');"
    echo

}

function load_patches() {
    # before patch. drop recreatable objects
    sed_strip_utf8_bom $DB_PATH/tools/sql/before_patch.sql

    echo
    echo "-- apply patches --"
    echo
    # apply incremental changes
    echo "$@" | xargs -I{} cat {} | sed_strip_utf8_bom

    #$DB_PATH/tools/sh/list-dependencies-from-patches.sh $PWD/patches/*.sql \
    #     | xargs -I{} cat {}

    #$DB_PATH/tools/sh/list-dependencies-from-patches.sh $PWD/patches/*.sql \
    #    | tsort \
    #    | sed_bin '1!G;h;$!d' \
    #    | xargs -I{} cat $PWD/patches/{}.sql

    # after patch
    sed_strip_utf8_bom $DB_PATH/tools/sql/after_patch.sql
}


function install_recreatable_objects {

    local MODULE_PATH=''

    MODULE_PATH="$(get_recreatable_objects_path)"

    export -f sed_bin
    export -f sed_strip_utf8_bom
    find $MODULE_PATH -name '*.sql' -type f -print0 | sort -z \
        | xargs -0 -I{} bash -c 'sed_strip_utf8_bom {}'

}


function run_user_after_patch_sql {
    local USER_AFTER_PATCH_FILE="$PWD/patches/util/after_patch.sql"
    if [[ -f "$USER_AFTER_PATCH_FILE" ]] ; then
        sed_strip_utf8_bom "$USER_AFTER_PATCH_FILE"
    fi
}


function commit_or_rollback() {
    # finalize
    if [[ $DRY_RUN -eq 1 ]] ; then
        echo
        echo "ROLLBACK;"
        echo
    else
        echo
        echo "COMMIT;"
        echo
    fi
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
        elif [[ $var == "--install" ]] || [[ $var == "-i" ]] ; then
            LOAD_BASE=1
        elif [[ $var == "--dry-run" ]] || [[ $var == "-0" ]] ; then
            DRY_RUN=1
        else
            unprocessed_args+=("$var")
        fi
    done

    # debug output:
    # echo "-- unprocessed args: ${unprocessed_args[@]}"

    read_db_args "${unprocessed_args[@]}"

    # debug output:
    # echo "-- LOAD_BASE: $LOAD_BASE"
    # echo "-- DRY_RUN:   $DRY_RUN"
    # echo "-- DBHOST:    $DBHOST"
    # echo "-- DBPORT:    $DBPORT"
    # echo "-- DBUSER:    $DBUSER"
    # echo "-- DATABASE:  $DATABASE"
    # echo "-- SILENT:    $SILENT_FLAG_SET"

    return 0
}

function run_all() {
    # run queries to find out patches order before locking tables
    # DON'T MAKE patch_list_ordered LOCAL AND ASSING RESULT OF get_patches_install_order
    # RIGHT AWAY, OTHERWISE ERROR REPORTING AND RETURN CODES DOES NOT WORK
    # http://stackoverflow.com/questions/20157938/bash-exit-code-of-variable-assignment-to-command-substitution
    # local patch_list_ordered=$(get_patches_install_order) # THIS IS THE WRONG WAY!!!
    local patch_list_ordered=''
    patch_list_ordered=$(get_patches_install_order)

    # get version information and lock patch table
    lock_for_patch

    # load patches. drop recreatable obejcts and make schema/data changes
    load_patches "$patch_list_ordered"

    # restore recreatable objects
    install_recreatable_objects

    # run user after patch sql code
    run_user_after_patch_sql

    commit_or_rollback
}
# ======================================== Functions

# read args
read_args "$@"

run_all
