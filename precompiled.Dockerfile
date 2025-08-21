ARG BUILDER_IMAGE

FROM ${BUILDER_IMAGE} AS builder

WORKDIR /work

COPY find-driver-version/ .

ENV GOTOOLCHAIN=auto
ENV CGO_ENABLED=0

RUN go mod download
RUN go build .

FROM registry.ddbuild.io/images/nvidia-cuda-base:12.9.0

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Fetch GPG keys for CUDA repo
RUN apt-key del 7fa2af80 && \
    apt-key adv --fetch-keys "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub"

RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    build-essential \
    ca-certificates \
    curl \
    kmod \
    file \
    libelf-dev \
    libglvnd-dev \
    pkg-config

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
    echo "KERNEL_VERSION=$KERNEL_VERSION" >> /versions.env

COPY --from=builder /work/find-driver-version /usr/local/bin/find-driver-version

RUN . /versions.env && \
    FULL_DRIVER_VERSION=$(find-driver-version -d $DRIVER_BRANCH -k $KERNEL_VERSION | cut -d'>' -f2 | xargs) \
    DRIVER_VERSION="${FULL_DRIVER_VERSION%%-*}" \
    MODULES_VERSION=$(apt-cache madison "linux-modules-nvidia-$DRIVER_BRANCH-server-open-$KERNEL_VERSION" | awk 'NR==1 {print $3}') && \
    echo "FULL_DRIVER_VERSION=$FULL_DRIVER_VERSION" >> /versions.env && \
    echo "DRIVER_VERSION=$DRIVER_VERSION" >> /versions.env && \
    echo "MODULES_VERSION=$MODULES_VERSION" >> /versions.env

RUN . /versions.env && \
    apt-get install -y --download-only --no-install-recommends \
    nvidia-fabricmanager-${DRIVER_BRANCH}=${DRIVER_VERSION}-1 \
    libnvidia-nscq-${DRIVER_BRANCH}=${DRIVER_VERSION}-1 \
    nvidia-driver-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    linux-modules-nvidia-${DRIVER_BRANCH}-server-${KERNEL_VERSION}=${MODULES_VERSION} \
    linux-modules-nvidia-${DRIVER_BRANCH}-server-open-${KERNEL_VERSION}=${MODULES_VERSION} \
    linux-objects-nvidia-${DRIVER_BRANCH}-server-${KERNEL_VERSION}=${MODULES_VERSION} \
    linux-signatures-nvidia-${KERNEL_VERSION}=${MODULES_VERSION} \
    # all other packages are nvidia-driver dependencies
    libnvidia-gl-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    nvidia-dkms-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    nvidia-kernel-common-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    nvidia-kernel-source-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-compute-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-extra-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    nvidia-compute-utils-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-decode-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-encode-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    nvidia-utils-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    xserver-xorg-video-nvidia-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-cfg1-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION} \
    libnvidia-fbc1-${DRIVER_BRANCH}-server=${FULL_DRIVER_VERSION}

RUN mkdir -p /opt/nvidia-driver/bin
COPY ubuntu22.04/precompiled/nvidia-driver /opt/nvidia-driver/bin/nvidia-driver
COPY nvidia-driver-wrapper.sh /usr/local/bin/nvidia-driver

WORKDIR  /drivers

# Remove cuda repository to avoid GPG errors
RUN rm -f /etc/apt/sources.list.d/cuda*

ENTRYPOINT ["nvidia-driver", "init"]
