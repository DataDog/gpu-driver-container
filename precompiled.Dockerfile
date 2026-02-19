ARG BUILDER_IMAGE

FROM ${BUILDER_IMAGE} AS builder

WORKDIR /work

COPY find-driver-version/ .

ENV GOTOOLCHAIN=auto
ENV CGO_ENABLED=0

RUN go mod download
RUN go build .

FROM registry.ddbuild.io/images/nvidia-cuda-base:12.9.0

ARG TARGETARCH

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Fetch GPG keys for CUDA repo
RUN apt-key del 7fa2af80 && \
    apt-key adv --fetch-keys "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub"

RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-rdepends \
    apt-utils \
    build-essential \
    ca-certificates \
    curl \
    kmod \
    file \
    libelf-dev \
    libglvnd-dev \
    pkg-config \
    pciutils

# Prevent apt from cleaning its cache after each invocation
RUN sed -i 's/^\(.*DPkg::Post-Invoke.*\)$/\/\/ \1/' /etc/apt/apt.conf.d/*

RUN curl -fsSL -o /usr/local/bin/donkey https://github.com/3XX0/donkey/releases/download/v1.1.0/donkey && \
    chmod +x /usr/local/bin/donkey

# Expected value is <major>-<kernel version>-<distro>
# Example: 570-6.8.0-1032-aws-ubuntu22.04
ARG VERSION
ENV VERSION=${VERSION}

RUN DRIVER_BRANCH="${VERSION%%-*}" \
    KERNEL_DISTRO_VERSION="${VERSION#*-}" \
    KERNEL_VERSION="${KERNEL_DISTRO_VERSION%-*}" && \
    echo "DRIVER_BRANCH=$DRIVER_BRANCH" > /versions.env && \
    echo "TARGETARCH=$TARGETARCH" >> /versions.env && \
    echo "KERNEL_VERSION=$KERNEL_VERSION" >> /versions.env

COPY --from=builder /work/find-driver-version /usr/local/bin/find-driver-version

RUN echo 'skip docker cache 3'

RUN . /versions.env && apt-get update && \
    FULL_DRIVER_VERSION=$(find-driver-version -d $DRIVER_BRANCH -k $KERNEL_VERSION | cut -d'>' -f2 | xargs) \
    DRIVER_VERSION="${FULL_DRIVER_VERSION%%-*}" \
    MODULES_VERSION=$(apt-cache madison "linux-modules-nvidia-$DRIVER_BRANCH-server-open-$KERNEL_VERSION" | awk 'NR==1 {print $3}') && \
    echo "FULL_DRIVER_VERSION=$FULL_DRIVER_VERSION" >> /versions.env && \
    echo "DRIVER_VERSION=$DRIVER_VERSION" >> /versions.env && \
    echo "MODULES_VERSION=$MODULES_VERSION" >> /versions.env

RUN . /versions.env && \
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
    linux-modules-extra-${KERNEL_VERSION} \
    infiniband-diags \
    nvlsm \
    nvidia-fabricmanager-${DRIVER_BRANCH}=${FULL_DRIVER_VERSION} \
    libnvidia-nscq-${DRIVER_BRANCH}=${FULL_DRIVER_VERSION} \
    nvidia-imex-${DRIVER_BRANCH}=${FULL_DRIVER_VERSION} \
    nvidia-kernel-common-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    nvidia-kernel-source-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-compute-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    nvidia-compute-utils-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-cfg1-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION}" && \
    BASE_AMD_PACKAGES="libnvsdm=${DRIVER_VERSION}-1" && \
    [ "$TARGETARCH" = "amd64" ] && BASE_PACKAGES="$BASE_PACKAGES $BASE_AMD_PACKAGES" || true && \
    BASE_PACKAGES_NAMES=$(echo "$BASE_PACKAGES" | sed -E 's/=([^ ]+)//g') && \
    DEP_PACKAGES=$(apt-rdepends $BASE_PACKAGES_NAMES | grep -v "^ " | grep -v "^debconf-2.0$" | grep -v "^linux-image-unsigned-") && \
    apt-get install -y --download-only --no-install-recommends --reinstall $BASE_PACKAGES $DEP_PACKAGES

# Remove cuda repository before downloading dkms to avoid version conflicts
# CUDA repo has dkms 1:3.3.0 but Ubuntu has 2.8.7 - we need Ubuntu version for runtime
# Note: We remove repo files but don't run apt-get update to preserve package cache
# for runtime installation of precompiled driver packages
RUN rm -f /etc/apt/sources.list.d/cuda*

# Download kernel headers, dkms, linux-modules (for video.ko) for GRID driver support
# linux-modules contains video.ko which nvidia-modeset depends on for __acpi_video_get_backlight_type symbol
RUN . /versions.env && \
    apt-get install -y --download-only --no-install-recommends \
        linux-headers-${KERNEL_VERSION} \
        linux-modules-${KERNEL_VERSION} \
        dkms

RUN mkdir -p /opt/nvidia-driver/bin
COPY ubuntu22.04/precompiled/nvidia-driver /opt/nvidia-driver/bin/nvidia-driver
COPY nvidia-driver-wrapper.sh /usr/local/bin/nvidia-driver

ADD download_azure_grid_driver.sh /tmp
# TODO: Azure support only several GRID driver versions. Temporary hardcode the version.
# RUN . /versions.env && /tmp/download_azure_grid_driver.sh "$DRIVER_VERSION"
RUN /tmp/download_azure_grid_driver.sh "550.144.06"

WORKDIR  /drivers

ENTRYPOINT ["nvidia-driver", "init"]
