FROM registry.ddbuild.io/images/nvidia-cuda-base:12.9.0

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Fetch GPG keys for CUDA repo
RUN apt-key del 7fa2af80 && \
    apt-key adv --fetch-keys "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub"

RUN apt-get update && apt-get install -y --no-install-recommends curl

RUN curl -fsSL -o /usr/local/bin/donkey https://github.com/3XX0/donkey/releases/download/v1.1.0/donkey && \
    chmod +x /usr/local/bin/donkey

# Expected value is <major>.<minor>.<patch>-<kernel version>-<distro>
# Example: 570.133.20-6.8.0-1032-aws-ubuntu22.04
ARG VERSION
ENV VERSION=${VERSION}

RUN DRIVER_VERSION="${VERSION%%-*}" \
    DRIVER_BRANCH="${DRIVER_VERSION%%.*}" \
    KERNEL_DISTRO_VERSION="${VERSION#*-}" \
    KERNEL_VERSION="${KERNEL_DISTRO_VERSION%-*}" && \
    echo "DRIVER_VERSION=$DRIVER_VERSION" > /versions.env && \
    echo "DRIVER_BRANCH=$DRIVER_BRANCH" >> /versions.env && \
    echo "KERNEL_VERSION=$KERNEL_VERSION" >> /versions.env

# update pkg cache and install pkgs for userspace driver libs
RUN . /versions.env && \
    apt-get install -y --download-only --no-install-recommends nvidia-driver-${DRIVER_BRANCH}-server \
    nvidia-fabricmanager-${DRIVER_BRANCH}=${DRIVER_VERSION}-1 \
    libnvidia-nscq-${DRIVER_BRANCH}=${DRIVER_VERSION}-1

# update pkg cache and download pkgs for driver module installation during runtime.
# this is done to avoid shipping .ko files.
# avoid cleaning the cache after this to retain these packages during runtime.
RUN . /versions.env && \
    apt-get install --download-only --no-install-recommends -y linux-objects-nvidia-${DRIVER_BRANCH}-server-${KERNEL_VERSION} \
    linux-signatures-nvidia-${KERNEL_VERSION} \
    linux-modules-nvidia-${DRIVER_BRANCH}-server-${KERNEL_VERSION} \
    # add support for nvidia open source driver packages during runtime
    linux-modules-nvidia-${DRIVER_BRANCH}-server-open-${KERNEL_VERSION}

RUN mkdir -p /opt/nvidia-driver/bin
COPY ubuntu22.04/precompiled/nvidia-driver /opt/nvidia-driver/bin/nvidia-driver
COPY nvidia-driver-wrapper.sh /usr/local/bin/nvidia-driver

WORKDIR  /drivers

# Remove cuda repository to avoid GPG errors
RUN rm -f /etc/apt/sources.list.d/cuda*

ENTRYPOINT ["nvidia-driver", "init"]
