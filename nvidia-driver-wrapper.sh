#!/usr/bin/env bash

set -exo pipefail

export DRIVER_VERSION=$(awk '/^DRIVER_VERSIONS/ {print $NF}' /versions.mk)
export DRIVER_BRANCH=$(echo "$DRIVER_VERSION" | cut -d. -f1)

/opt/nvidia-driver/bin/nvidia-driver $@
