#!/usr/bin/env bash

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: ./ci.sh <version> <mode>"
    exit 1
fi

BUILD_VERSION=$1
MODE=${2:-watch}
DIR="$( cd "$( dirname $( dirname "${BASH_SOURCE[0]}" ) )" && pwd )"

# PREPARE
mkdir -p "$DIR/plugins"
chmod 777 "$DIR/plugins"
rm -f $DIR/plugins/*

docker run --rm \
    -v "$DIR/plugins":/home/builder/builds \
    -v "$DIR/scripting":/home/builder/sources \
    -v "$DIR/scripting/include/colorchat.inc":/home/builder/addons/amxmodx/scripting/include/colorchat.inc \
    -v "$DIR/scripting/include/custom_color_chat.inc":/home/builder/addons/amxmodx/scripting/include/custom_color_chat.inc \
    -v "$DIR/scripting/include/shopsms_const.inc":/home/builder/addons/amxmodx/scripting/include/shopsms_const.inc \
    -v "$DIR/scripting/include/shopsms.inc":/home/builder/addons/amxmodx/scripting/include/shopsms.inc \
    budziam/amxmodx-builder:${BUILD_VERSION} \
    ${MODE}