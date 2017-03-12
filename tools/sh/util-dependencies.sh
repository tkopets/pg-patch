#!/bin/bash

set -e
set -o pipefail

# Simple tool to list files with patches that satisfies dependencies while loading them.

# source query-patches.sh located in the same dir
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/lib/query-patches.sh"

# query db,
# replace spaces in filenames with dashes (in case patch files have spaces)
# replace psql pipe (|) field separator with spaces (format suitable for tsort utility)
query_patches  "
select patch_name as patch,
       case when requires <> '{}' then unnest(requires) else patch_name end as dependency
from   tmp_local_patches;" | \
  sed_bin "s/ /-/" | \
  sed_bin "s/|/ /";
