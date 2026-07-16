#!/usr/bin/env bash

set -eu

GRID_INSTALLER_DIR=${GRID_INSTALLER_DIR:-/ckmb/nvidia-grid-install}

# Available Azure GRID driver versions
AVAILABLE_VERSIONS="550.144.06, 535.161.08, 525.105.17"

print_usage() {
    echo "Usage: $0 <driver_version>"
    echo "Available versions: $AVAILABLE_VERSIONS"
}

get_grid_azure_url() {
    local version="$1"

    # Azure GRID driver version mapping
    case "$version" in
        570.195.03*)
            echo "https://download.microsoft.com/download/0541e1a5-dff2-4b8c-a79c-96a7664b1d49/NVIDIA-Linux-x86_64-570.195.03-grid-azure.run"
            ;;
        550.144.06*)
            echo "https://download.microsoft.com/download/c5319e92-672e-4067-8d85-ab66a7a64db3/NVIDIA-Linux-x86_64-550.144.06-grid-azure.run"
            ;;
        535.161.08*)
            echo "https://download.microsoft.com/download/8/d/a/8da4fb8e-3a9b-4e6a-bc9a-72ff64d7a13c/NVIDIA-Linux-x86_64-535.161.08-grid-azure.run"
            ;;
        525.105.17*)
            echo "https://download.microsoft.com/download/6/b/d/6bd2850f-5883-4e2a-9a35-edbd3dd6808c/NVIDIA-Linux-x86_64-525.105.17-grid-azure.run"
            ;;
        *)
            echo ""
            return 1
            ;;
    esac
    return 0
}

fetch_grid_azure_installer() {
    local driver_version="$1"

    if [ -z "$driver_version" ]; then
        echo "ERROR: Driver version must be provided as an argument"
        print_usage
        exit 1
    fi

    mkdir -p "$GRID_INSTALLER_DIR"
    cd "$GRID_INSTALLER_DIR"

    local download_url=$(get_grid_azure_url "$driver_version")

    if [ -z "$download_url" ]; then
        echo "ERROR: No Azure GRID driver URL found for version $driver_version"
        print_usage
        exit 1
    fi

    local filename=$(basename "$download_url")
    echo "Downloading GRID driver from: $download_url"

    curl -fSsl -o "$filename" "$download_url"
    chmod +x "$filename"

    echo "GRID installer downloaded successfully to $GRID_INSTALLER_DIR/$filename"
}

fetch_grid_azure_installer "$@"
