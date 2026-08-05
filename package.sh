#!/usr/bin/env bash

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: ./package.sh <version>"
    exit 1
fi

BUILD_VERSION=$1
DIR="$( cd "$( dirname $( dirname "${BASH_SOURCE[0]}" ) )" && pwd )"

mkdir -p "$DIR/out"
rm -f "$DIR"/out/amxmodx-*.zip

(cd "$DIR" && zip -r "out/amxmodx-${BUILD_VERSION}.zip" cstrike)
