#!/usr/bin/env bash

set -exo pipefail

source /versions.env
export DRIVER_VERSION DRIVER_BRANCH

/opt/nvidia-driver/bin/nvidia-driver $@
