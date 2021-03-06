#!/bin/bash
set -o errexit
set -o pipefail

readonly PGPATCH_PATH="$( cd "$( dirname "$( dirname "$( dirname "$0" )" )" )" && pwd )"

readonly ARGS="$@"
readonly ARGC="$#"

function grep_bin() {
    if [[ ${OSTYPE//[0-9.]} == "solaris" ]]; then
        ggrep "$@"
    else
        grep "$@"
    fi
}

function sed_bin() {
    if [[ ${OSTYPE//[0-9.]} == "solaris" ]]; then
        gsed "$@"
    else
        sed "$@"
    fi
}

function help {
    cat <<EOF
pg-patch delpoy command is used to apply patches to target database.

usage: pg-patch delpoy [-c file] [-h host] [-p port] [-U user] [-d database]
                       [-0] [-s] [-v] [-y]

For deatiled information on connection options and config file see:
  pg-patch --help

pg-patch will attempt to find repository information from git or hg repository.
If none is found script will look into file repo.info (see example repo.info.example).

Additional options:
  -0 --dry-run   rollbacks all changes in the end (for testing)
  -s --silent    silently ignore patch dependency warnings
  -v --verbose   verbose mode prints all commands sent to database
  -y --yes       disable the confirmation prompt

Usage examples:
  ./pg-patch deploy --dry-run
  ./pg-patch deploy -c test_db.conf
EOF
}

function confirm_action {
    while true; do
        read -r -p "Do you want to continue? [y/n]: " ans
        case $ans in
            [Yy]* )
                break;;
            [Nn]* )
                exit;;
            * )
                echo "Please answer yes on no."
        esac
    done
    return 0
}


function read_args() {
    local arg=

    for arg
    do
        local delim=""
        case "$arg" in
            #translate --gnu-long-options to -g (short options)
            --help)           help && exit 0;;
            --host)           args="${args}-h ";;
            --port)           args="${args}-p ";;
            --user)           args="${args}-U ";;
            --database)       args="${args}-d ";;
            --yes)            args="${args}-y ";;
            --dry-run)        args="${args}-0 ";;
            --silent)         args="${args}-s ";;
            --verbose)        args="${args}-v ";;
            #pass through anything else
            *) [[ "${arg:0:1}" == "-" ]] || delim="\""
               args="${args}${delim}${arg}${delim} ";;
        esac
    done

    # Reset the positional parameters to the short options
    eval set -- "$args"

    # read parameters
    while getopts "c:h:p:U:d:ysv0" optname
    do
        case "$optname" in
            "h") v_host=$OPTARG ;;
            "p") v_port=$OPTARG ;;
            "U") v_dbuser=$OPTARG ;;
            "d") v_db=$OPTARG ;;
            "y") v_disable_prompt=1 ;;
            "s") v_silent_flag='-s' ;;
            "0") v_dry_run_flag='-0' ;;
            "v") v_verbose_flag='-a' ;; # for psql execution
            "?") echo "Unknown option $OPTARG" ;;
            ":") echo "No argument value for option $OPTARG" ;;
            *) echo "Unknown error while processing options" ;;
        esac
    done
    return 0
}

function notify_and_confirm() {
    cat <<EOF
You are going to deploy patches to
  host:     $v_host
  port:     $v_port
  username: $v_dbuser
  database: $v_db

EOF

    [[ "$v_disable_prompt" -eq 0 ]] && confirm_action
    return 0
}

function run_actions() {
    local patch_action=''
    local dbinstall=''
    local -r action_sql="$PGPATCH_PATH/tools/sql/patch_or_install.sql"

    echo "Checking database..."
    patch_action=$(psql --tuples-only --no-psqlrc --quiet \
        --host="$v_host" --port="$v_port" --username="$v_dbuser" --dbname="$v_db" \
        --file="$action_sql" |
        tr -d '[:space:]')

    if [ "$patch_action" = 'install' ] ; then
        echo "Empty database, installing pg-patch and deploying all patches."
        dbinstall='--install'
    elif [ "$patch_action" = 'patch' ] ; then
        echo "Deploying patches."
    else
        echo "Database preconditions failed."
        exit 1
    fi
    echo "Applying changes..."

    "$PGPATCH_PATH/tools/sh/sql.sh" -h "$v_host" -p "$v_port" \
            -U "$v_dbuser" -d "$v_db" $dbinstall $v_dry_run_flag $v_silent_flag |
        PGAPPNAME='pg-patch (main)' \
        psql -X $v_verbose_flag -v ON_ERROR_STOP=1 --pset pager=off \
            -h "$v_host" -p "$v_port" -U "$v_dbuser" -d "$v_db" 2>&1 |
        if [ "$v_verbose_flag" = '-a' ]; then \
            cat; \
        else \
            grep_bin -E 'WARNING|ERROR|FATAL' | sed_bin 's/WARNING:  pg-patch://'; \
        fi

    if [[ "${PIPESTATUS[0]}" -eq 0 && "${PIPESTATUS[1]}" -eq 0 ]]
    then
        echo "Done."
    else
        echo "ERROR:  failed to deploy patches"
        if [[ "${PIPESTATUS[0]}" -ne 0 ]] ; then
            exit "${PIPESTATUS[0]}"
        else
            exit "${PIPESTATUS[1]}"
        fi
    fi

    return 0
}

function main() {
    # define variables and default values
    local v_host=''
    local v_port=''
    local v_dbuser=''
    local v_db=''
    local v_disable_prompt=0
    local v_silent_flag=''
    local v_dry_run_flag=''
    local v_verbose_flag='-q'

    # get and parse arguments
    read_args "$ARGS"

    # show destination and ask confirmation
    notify_and_confirm

    run_actions
}

main
