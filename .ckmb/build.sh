#!/usr/bin/env bash

set -exo pipefail

### Build find-driver-version script ###
export GOTOOLCHAIN=auto
cd find-driver-version/
go mod download
go build -o find-driver-version .
cp find-driver-version /usr/local/bin/find-driver-version
cd -


### Install dependencies ###
export DEBIAN_FRONTEND=noninteractive
echo "debconf debconf/frontend select Noninteractive" | debconf-set-selections
TARGETARCH="$(dpkg --print-architecture)"
source /etc/os-release
UBUNTU_VERSION="ubuntu${VERSION_ID//./}"
UBUNTU_VERSION_CODENAME="${VERSION_CODENAME}"

# Configure CUDA repository
if [ "$TARGETARCH" = "amd64" ]; then
    NVARCH=x86_64
else
    NVARCH=sbsa
fi
curl -fsSLO "https://developer.download.nvidia.com/compute/cuda/repos/${UBUNTU_VERSION}/${NVARCH}/cuda-keyring_1.1-1_all.deb"
dpkg -i cuda-keyring_1.1-1_all.deb

apt-get update && apt-get install -y --no-install-recommends \
    apt-rdepends \
    apt-utils \
    build-essential \
    ca-certificates \
    curl \
    dpkg-dev \
    file \
    libelf-dev \
    libglvnd-dev \
    pkg-config


### Create config ###
# At this point 2 variables are available:
# - $CKMB_KERNEL_FULL_VERSION (e.g. `6.8.0-1032-aws`)
# - $CKMB_VERSION (e.g. `580`)
mkdir -p /ckmb

KERNEL_VERSION=$CKMB_KERNEL_FULL_VERSION
DRIVER_BRANCH=$CKMB_VERSION
echo "KERNEL_VERSION=$KERNEL_VERSION" > /ckmb/versions.env
echo "DRIVER_BRANCH=$DRIVER_BRANCH" >> /ckmb/versions.env

echo "TARGETARCH=$TARGETARCH" >> /ckmb/versions.env

FULL_DRIVER_VERSION=$(find-driver-version -d "$DRIVER_BRANCH" -k "$KERNEL_VERSION" -u "$UBUNTU_VERSION_CODENAME")
echo "FULL_DRIVER_VERSION=$FULL_DRIVER_VERSION" >> /ckmb/versions.env

DRIVER_VERSION="${FULL_DRIVER_VERSION%%-*}"
echo "DRIVER_VERSION=$DRIVER_VERSION" >> /ckmb/versions.env

MODULES_VERSION=$(apt-cache madison "linux-modules-nvidia-$DRIVER_BRANCH-server-open-$KERNEL_VERSION" | awk 'NR==1 {print $3}')
echo "MODULES_VERSION=$MODULES_VERSION" >> /ckmb/versions.env


### Download driver and related packages ###
# Download apt packages
BASE_PACKAGES="nvidia-utils-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    nvidia-headless-no-dkms-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-decode-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-extra-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-encode-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-fbc1-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    linux-modules-nvidia-${DRIVER_BRANCH}-server-${KERNEL_VERSION}=${MODULES_VERSION} \
    linux-modules-nvidia-${DRIVER_BRANCH}-server-open-${KERNEL_VERSION}=${MODULES_VERSION} \
    linux-objects-nvidia-${DRIVER_BRANCH}-server-${KERNEL_VERSION}=${MODULES_VERSION} \
    linux-signatures-nvidia-${KERNEL_VERSION}=${MODULES_VERSION} \
    infiniband-diags \
    nvlsm \
    perl \
    nvidia-fabricmanager-${DRIVER_BRANCH}=${FULL_DRIVER_VERSION} \
    libnvidia-nscq-${DRIVER_BRANCH}=${FULL_DRIVER_VERSION} \
    nvidia-imex=${DRIVER_VERSION}-1ubuntu1 \
    nvidia-kernel-common-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    nvidia-kernel-source-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-compute-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    nvidia-compute-utils-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-cfg1-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    pciutils"
if [ "$TARGETARCH" = "amd64" ]; then
    BASE_PACKAGES="$BASE_PACKAGES libnvsdm=${DRIVER_VERSION}-1ubuntu1"
fi
if [[ "$KERNEL_VERSION" == 6.* ]]; then
    # On old kernels, not all kernel modules are available in the linux-modules package
    BASE_PACKAGES="$BASE_PACKAGES linux-modules-extra-${KERNEL_VERSION}"
fi
if [ "${KERNEL_VERSION##*-}" = "azure" ]; then \
    # Download GRID driver and its dependencies: kernel headers, dkms, linux-modules (for video.ko) — Azure only
    # linux-modules contains video.ko which nvidia-modeset depends on for __acpi_video_get_backlight_type symbol
    BASE_PACKAGES="$BASE_PACKAGES linux-headers-${KERNEL_VERSION} linux-modules-${KERNEL_VERSION} dkms python3-minimal build-essential"
fi
BASE_PACKAGES_NAMES=$(echo "$BASE_PACKAGES" | sed -E 's/=([^ ]+)//g')
DEP_PACKAGES=$(apt-rdepends $BASE_PACKAGES_NAMES | grep -v "^ " | grep -v "^debconf-2.0$" | grep -v "^linux-image-unsigned-")
mkdir -p /ckmb/apt-cache/pool/partial
apt-get install -y --download-only --no-install-recommends --reinstall -o Dir::Cache::archives="/ckmb/apt-cache/pool" $BASE_PACKAGES $DEP_PACKAGES

# Create local apt repository
cd /ckmb/apt-cache
dpkg-scanpackages pool /dev/null > Packages
sed -i 's|^Filename: /ckmb/apt-cache/|Filename: |' Packages
gzip -9c Packages > Packages.gz
cd -

# Download Azure GRID drivers
cp dd_scripts/grid-driver /ckmb/grid-driver
if [ "${KERNEL_VERSION##*-}" = "azure" ]; then
    # TODO: Azure supports only several GRID driver versions. Temporary hardcode the version.
    ./dd_scripts/download_azure_grid_driver.sh "570.195.03";
fi


### Copy nvidia-driver executable ###
cp dd_scripts/nvidia-driver /ckmb/nvidia-driver
