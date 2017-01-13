#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

if [ "$TRAVIS_PULL_REQUEST_BRANCH" != "" ]; then
     echo "Build of container skipped for PR. Container will be builded and uploaded after merge."
     exit 0
fi

cd bird-container
make build-container