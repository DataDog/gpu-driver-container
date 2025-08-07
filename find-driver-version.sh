#!/usr/bin/env bash

set -eo pipefail

# Expected value is `<driver major>`
# Example: 570
if [ -z "$DRIVER_BRANCH" ]; then
    echo "error: DRIVER_BRANCH variable must be set" >&2
    exit 1
fi

# Expected value is `<kernel semver>-<kernel patch>-<cloud-provider>`
# Example: 6.8.0-1032-aws
if [ -z "$KERNEL_VERSION" ]; then
    echo "error: KERNEL_VERSION variable must be set" >&2
    exit 1
fi

NVIDIA_REPOS=(jammy-updates/restricted jammy-security/restricted)
nvidia_package_repos=()
for repo in "${NVIDIA_REPOS[@]}"; do
    repo_url=http://archive.ubuntu.com/ubuntu/dists/$repo/binary-amd64/Packages.gz
    nvidia_package_repos+=("$(curl -sL "$repo_url" | gzip -d)")
done

get_package() {
    echo "$1" | awk -v RS= "{ if (\$0 ~ /Package: $2/) print }"
}

linux_modules_packages=()
nvidia_driver_versions=()
for package_repo in "${nvidia_package_repos[@]}"; do
    linux_modules_package="$(get_package "$package_repo" "linux-modules-nvidia-$DRIVER_BRANCH-server-open-$KERNEL_VERSION")"
    if [ -n "$linux_modules_package" ]; then
        linux_modules_packages+=("$linux_modules_package")
    fi

    nvidia_driver_version="$(get_package "$package_repo" "nvidia-driver-$DRIVER_BRANCH-server-open" | awk '/^Version:/ { print $2 }' || true)"
    if [ -n "$nvidia_driver_version" ]; then
        nvidia_driver_versions+=("$nvidia_driver_version")
    fi
done

for linux_modules_package in "${linux_modules_packages[@]}"; do
    target_version=$(echo "$linux_modules_package" | \
        grep 'Depends: ' | \
        awk -F'nvidia-kernel-common-570-server' '{split($2, a, "[()]"); print a[2]}' | \
        sed -E 's/^.* ([0-9]+\.[0-9]+\.[0-9]+).*$/\1/')

    for version in "${nvidia_driver_versions[@]}"; do
        version_short=$(echo "$version" | cut -d'-' -f1)
        if [ "$target_version" == "$version_short" ]; then
            echo "$version"
            exit 0
        fi
    done
done

echo "no available driver from branch $DRIVER_BRANCH for kernel $KERNEL_VERSION" >&2
