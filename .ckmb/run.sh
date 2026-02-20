#!/usr/bin/env bash

set -exo pipefail

# Prepare apt cache
echo "deb [trusted=yes] file:/ckmb/apt-cache ./" > /etc/apt/sources.list
rm -rf /etc/apt/sources.list.d/*
sed -i 's/^\(.*DPkg::Post-Invoke.*\)$/\/\/ \1/' /etc/apt/apt.conf.d/*
apt-get update
apt-get install -y --no-install-recommends pciutils

source /ckmb/versions.env
export MODULES_VERSION DRIVER_BRANCH FULL_DRIVER_VERSION DRIVER_VERSION TARGETARCH

/ckmb/nvidia-driver $@
