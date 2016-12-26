#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

cd bird-container
make build-container