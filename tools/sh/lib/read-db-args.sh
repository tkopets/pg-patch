#!/bin/bash
set -o errexit
set -o pipefail

readonly ARGS="$@"
readonly ARGC="$#"

DBARGS_LEFTOVERS=''
DBHOST=''
DBPORT=''
DBUSER=''
DATABASE=''
SILENT_FLAG_SET=0

function read_db_args() {
    local arg=

    local dbhost_ok=false
    local dbport_ok=false
    local dbuser_ok=false
    local database_ok=false

    for arg
    do
        local delim=""
        case "$arg" in
            #translate --gnu-long-options to -g (short options)
            --host)           args="${args}-h ";;
            --port)           args="${args}-p ";;
            --user)           args="${args}-U ";;
            --database)       args="${args}-d ";;
            --silent)         args="${args}-s ";;
            #pass through anything else
            *) [[ "${arg:0:1}" == "-" ]] || delim="\""
               args="${args}${delim}${arg}${delim} ";;
        esac
    done

    # Reset the positional parameters to the short options
    eval set -- $args

    # read parameters
    while getopts ":h:p:U:d:s" optname
    do
        case "$optname" in
            "H") help && exit 0 ;;
            "h") dbhost_ok=true;   DBHOST=$OPTARG ;;
            "p") dbport_ok=true;   DBPORT=$OPTARG ;;
            "U") dbuser_ok=true;   DBUSER=$OPTARG ;;
            "d") database_ok=true; DATABASE=$OPTARG ;;
            "s") SILENT_FLAG_SET=1 ;;
            "?") echo "Unknown option -$OPTARG" 1>&2; exit 1 ;;
            ":") echo "No argument value for option $OPTARG" 1>&2; exit 1 ;;
            *) echo "Unknown error while processing options" 1>&2; exit 1 ;;
        esac
    done
    shift $((OPTIND -1))

    if [[ "$dbhost_ok" = false ]] ; then
        echo "ERROR:  DB hostname -h (--host) is not specified" 1>&2; exit 1;
    fi

    if [[ "$dbport_ok" = false ]] ; then
        echo "ERROR:  DB port -p (--port) is not specified" 1>&2; exit 1;
    fi

    if [[ "$dbuser_ok" = false ]] ; then
        echo "ERROR:  DB user -U (--user) is not specified" 1>&2; exit 1;
    fi

    if [[ "$database_ok" = false ]] ; then
        echo "ERROR:  DB name -d (--database) is not specified" 1>&2; exit 1;
    fi

    DBARGS_LEFTOVERS="$@"

    return 0
}
