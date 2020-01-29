#!/usr/bin/env bash

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: ./run.sh <version>"
    exit 1
fi

declare -A BASE_VERSIONS=(
	["1.8.2"]="https://www.amxmodx.org/release/amxmodx-1.8.2-base-linux.tar.gz"
	["1.8.3"]="https://www.amxmodx.org/amxxdrop/1.8/amxmodx-1.8.3-dev-git5201-base-linux.tar.gz"
	["1.9.0"]="https://www.amxmodx.org/amxxdrop/1.9/amxmodx-1.9.0-git5241-base-linux.tar.gz"
)

declare -A CSTRKE_VERSIONS=(
	["1.8.2"]="https://www.amxmodx.org/release/amxmodx-1.8.2-cstrike-linux.tar.gz"
	["1.8.3"]="https://www.amxmodx.org/amxxdrop/1.8/amxmodx-1.8.3-dev-git5201-cstrike-linux.tar.gz"
	["1.9.0"]="https://www.amxmodx.org/amxxdrop/1.9/amxmodx-1.9.0-git5241-cstrike-linux.tar.gz"
)

BUILD_VERSION=$1

if [ -v ${BASE_VERSIONS[${BUILD_VERSION}]} ]; then
	echo "Invalid version"
	exit 1
fi

DIR="$( cd "$( dirname $( dirname "${BASH_SOURCE[0]}" ) )" && pwd )"
BASE_URL="${BASE_VERSIONS[${BUILD_VERSION}]}"
CSTRIKE_URL="${CSTRKE_VERSIONS[${BUILD_VERSION}]}"

# RUN
IMAGE_NAME="cs16"
docker build -t ${IMAGE_NAME} --build-arg BASE_URL="${BASE_URL}" --build-arg CSTRIKE_URL="${CSTRIKE_URL}" -f "$DIR/server/Dockerfile" . \
&& docker run --rm -it -p 27015:27015 --network sklepsms_default --name sklepsms_cs16 ${IMAGE_NAME}
