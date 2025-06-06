ARG BUILDER_IMAGE

FROM ${BUILDER_IMAGE} AS build

WORKDIR /build
COPY . .

RUN cd vgpu/src && go build -o vgpu-util && mv vgpu-util /build

FROM registry.ddbuild.io/images/nvidia-cuda-base:12.9.0

LABEL maintainers="Compute"

ARG BASE_URL=https://us.download.nvidia.com/tesla
ARG TARGETARCH
ENV TARGETARCH=$TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

# Arg to indicate if driver type is either of passthrough(baremetal) or vgpu
ARG DRIVER_TYPE=passthrough
ENV DRIVER_TYPE=$DRIVER_TYPE
ARG VGPU_LICENSE_SERVER_TYPE=NLS
ENV VGPU_LICENSE_SERVER_TYPE=$VGPU_LICENSE_SERVER_TYPE
# Enable vGPU version compability check by default
ARG DISABLE_VGPU_VERSION_CHECK=true
ENV DISABLE_VGPU_VERSION_CHECK=$DISABLE_VGPU_VERSION_CHECK
ENV NVIDIA_VISIBLE_DEVICES=void

USER root
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

RUN echo "TARGETARCH=$TARGETARCH"

ADD ubuntu22.04/install.sh /tmp

RUN /tmp/install.sh reposetup && /tmp/install.sh depinstall && \
    curl -fsSL -o /usr/local/bin/donkey https://github.com/3XX0/donkey/releases/download/v1.1.0/donkey && \
    chmod +x /usr/local/bin/donkey

COPY ubuntu22.04/nvidia-driver /usr/local/bin
COPY versions.mk /versions.mk

COPY --from=build /build/vgpu-util /usr/local/bin

ADD ubuntu22.04/drivers drivers/

# Fetch the installer automatically for passthrough/baremetal types
RUN if [ "$DRIVER_TYPE" != "vgpu" ]; then \
    cd drivers && \
    DRIVER_VERSION=$(awk '/^DRIVER_VERSIONS/ {print $NF}' /versions.mk) \
    DRIVER_BRANCH=$(echo "$DRIVER_VERSION" | cut -d. -f1) \
    /tmp/install.sh download_installer; fi

# Fabric manager packages are not available for arm64
RUN if [ "$DRIVER_TYPE" != "vgpu" ] && [ "$TARGETARCH" != "arm64" ]; then \
    DRIVER_VERSION=$(awk '/^DRIVER_VERSIONS/ {print $NF}' /versions.mk) && \
    DRIVER_BRANCH=$(echo "$DRIVER_VERSION" | cut -d. -f1) && \
    apt-get update && \
    apt-get install -y --no-install-recommends nvidia-fabricmanager-${DRIVER_BRANCH}=${DRIVER_VERSION}-1 \
    libnvidia-nscq-${DRIVER_BRANCH}=${DRIVER_VERSION}-1; fi

WORKDIR /drivers

COPY ubuntu22.04/empty kernel/pubkey.x509

# Install the gcc-12 package in Ubuntu 22.04 as Kernels with versions 5.19.x and 6.5.x need gcc 12.3.0 for compilation
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc-12 g++-12 && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 12 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 12 && \
    rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["nvidia-driver", "init"]
