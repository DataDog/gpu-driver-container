#!/usr/bin/env bash

set -exo pipefail

source /versions.env
export MODULES_VERSION DRIVER_BRANCH FULL_DRIVER_VERSION DRIVER_VERSION TARGETARCH

/opt/nvidia-driver/bin/nvidia-driver $@
