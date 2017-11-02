#!/bin/bash
 
CURRENT_DIR="$( cd "$( dirname "$0" )" && pwd )"

function help {
    cat <<EOF
pg-patch add command is used to create a new patch from a template.

usage: pg-patch add <patch> [<dependency> <dependency2> ...]

Arguments:
  patch        name of new patch to be added in patches folder (mandatory)
  dependency   name of patch which is a dependency for <patch> (optional)

Usage examples:
  ./pg-patch add initial
  ./pg-patch add second initial
  ./pg-patch add user-permissions users permissions
EOF
}

function sed_bin() {
    if [[ ${OSTYPE//[0-9.]} == "solaris" ]]; then
        gsed "$@"
    else
        sed "$@"
    fi
}

get_git_user() {
    if hash git 2>/dev/null; then
        local git_user_name=
        local git_user_email=
        git_user_name=$(git config user.name)
        git_user_name=${git_user_name:-'Unknown'}
        git_user_email=$(git config user.email)
        
        git_user="$git_user_name"
        if [ -n "$git_user_email" ]; then
            git_user="$git_user_name <$git_user_email>"
        fi
    fi
}

function process_args() {
    # process parameters
    for var in "$@"
    do
        if [[ "$var" == "--help" ]] ; then
            help
            exit
        fi
    done

    if [[ -z $1 ]] ; then
        echo "ERROR:  patch name is not specified. See 'pgpatch add --help'." 1>&2
        exit 1
    fi

    return 0
}

function main() {
    process_args "$@"
    
    local patch_name=$1
    local tmp_dep_array=("${@:2}") # copy second to last args
    local patch_dependencies=$(IFS=,; echo "${tmp_dep_array[*]}")
    local git_user=

    get_git_user
    git_user=${git_user:-'Unknown'}

    # create new patch
    cat $CURRENT_DIR/../sql/patch_template.sql | \
        sed_bin "s/<%name%>/$patch_name/" | \
        sed_bin "s/<%author%>/$git_user/" | \
        sed_bin "s/<%dependencies%>/$patch_dependencies/" | \
        tee $PWD/patches/$patch_name.sql
}

main "$@"