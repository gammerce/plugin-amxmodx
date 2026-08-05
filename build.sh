#!/usr/bin/env bash

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: ./build.sh <version> <mode>"
    exit 1
fi

BUILD_VERSION=$1
MODE=${2:-watch}
DIR="$( cd "$( dirname $( dirname "${BASH_SOURCE[0]}" ) )" && pwd )"

# PREPARE
PLUGINS_DIR="$DIR/cstrike/addons/amxmodx/plugins"
SCRIPTING_DIR="$DIR/cstrike/addons/amxmodx/scripting"

mkdir -p "$PLUGINS_DIR"
chmod 777 "$PLUGINS_DIR"
rm -f $PLUGINS_DIR/*

docker run \
    --rm \
    -v "$PLUGINS_DIR":/home/builder/builds \
    -v "$SCRIPTING_DIR":/home/builder/sources \
    -v "$SCRIPTING_DIR/include/colorchat.inc":/home/builder/addons/amxmodx/scripting/include/colorchat.inc \
    -v "$SCRIPTING_DIR/include/curl.inc":/home/builder/addons/amxmodx/scripting/include/curl.inc \
    -v "$SCRIPTING_DIR/include/curl_consts.inc":/home/builder/addons/amxmodx/scripting/include/curl_consts.inc \
    -v "$SCRIPTING_DIR/include/custom_color_chat.inc":/home/builder/addons/amxmodx/scripting/include/custom_color_chat.inc \
    -v "$SCRIPTING_DIR/include/shopsms_const.inc":/home/builder/addons/amxmodx/scripting/include/shopsms_const.inc \
    -v "$SCRIPTING_DIR/include/shopsms.inc":/home/builder/addons/amxmodx/scripting/include/shopsms.inc \
    -v "$DIR/cstrike/addons/amxmodx/modules/curl_amxx_i386.so":/home/builder/addons/amxmodx/scripting/modules/curl_amxx_i386.so \
    "budziam/amxmodx-builder:${BUILD_VERSION}" \
    ${MODE}
