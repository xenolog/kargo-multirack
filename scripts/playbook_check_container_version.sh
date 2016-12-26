#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

function check_container_version {
    if [ "$TRAVIS_PULL_REQUEST_BRANCH" == "" ]; then
         echo "This check only for PR allowed, not for push."
         exit 0
    fi

    local branch=$TRAVIS_BRANCH

    for TAG in $(cat cluster.yaml  | grep bgpd_container_tag | awk '{print $2}' | sort | uniq) ; do
        if [ $branch == "master" ]; then
            if [ $TAG != 'latest' ]; then
              echo "cluster.yaml should contains 'bgpd_container_tag: latest', instead '$TAG' for branch '$branch'"
              exit 1
            fi
        elif [ "${branch:0:8}" == "release-" ]; then
            if [ $TAG != $branch ]; then
              echo "cluster.yaml should contains 'bgpd_container_tag: $branch', instead '$TAG' for branch '$branch'"
              exit 1
            fi
        fi
    done
}

check_container_version
