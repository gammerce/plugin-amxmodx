#!/usr/bin/env bash

DIR="$( cd "$( dirname $( dirname "${BASH_SOURCE[0]}" ) )" && pwd )"

# RUN
IMAGE_NAME="cs16"
docker build -t ${IMAGE_NAME} -f "$DIR/server/Dockerfile" . \
&& docker run -it ${IMAGE_NAME}
