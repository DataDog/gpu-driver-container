#!/usr/bin/env bash

set -eu

# GRID_INSTALLER_DIR is provided by Dockerfile ENV
GRID_INSTALLER_DIR=${GRID_INSTALLER_DIR:-/opt/nvidia-grid-install}

get_grid_azure_url() {
    local version="$1"

    # Azure GRID driver version mapping
    case "$version" in
        550.144.06*)
            echo "https://download.microsoft.com/download/c5319e92-672e-4067-8d85-ab66a7a64db3/NVIDIA-Linux-x86_64-550.144.06-grid-azure.run"
            ;;
        550.144.03*)
            echo "https://download.microsoft.com/download/c/3/4/c3484f19-fe76-4495-a65d-a5222ead9517/NVIDIA-Linux-x86_64-550.144.03-grid-azure.run"
            ;;
        535.161.08*)
            echo "https://download.microsoft.com/download/8/d/a/8da4fb8e-3a9b-4e6a-bc9a-72ff64d7a13c/NVIDIA-Linux-x86_64-535.161.08-grid-azure.run"
            ;;
        535.154.05*)
            echo "https://download.microsoft.com/download/1/4/4/14450d0e-a3f2-4b0a-9bb4-a8e729e986c4/NVIDIA-Linux-x86_64-535.154.05-grid-azure.run"
            ;;
        535.54.03*)
            echo "https://download.microsoft.com/download/2/e/8/2e85b622-d376-4166-be95-38fd60f18eda/NVIDIA-Linux-x86_64-535.54.03-grid-azure.run"
            ;;
        525.105.17*)
            echo "https://download.microsoft.com/download/6/b/d/6bd2850f-5883-4e2a-9a35-edbd3dd6808c/NVIDIA-Linux-x86_64-525.105.17-grid-azure.run"
            ;;
        525.85.05*)
            echo "https://download.microsoft.com/download/c/e/9/ce913061-ccf1-4c88-94ff-294e48c55439/NVIDIA-Linux-x86_64-525.85.05-grid-azure.run"
            ;;
        525.60.13*)
            echo "https://download.microsoft.com/download/1/e/8/1e82a212-9e77-4d74-9455-828d430a39f1/NVIDIA-Linux-x86_64-525.60.13-grid-azure.run"
            ;;
        *)
            echo ""
            return 1
            ;;
    esac
    return 0
}

fetch_grid_azure_installer() {
    mkdir -p "$GRID_INSTALLER_DIR"
    cd "$GRID_INSTALLER_DIR"

    local download_url=$(get_grid_azure_url "$DRIVER_VERSION")

    if [ -z "$download_url" ]; then
        echo "ERROR: No Azure GRID driver URL found for version $DRIVER_VERSION"
        echo "Available versions: 550.144.06, 550.144.03, 535.161.08, 535.154.05, 535.54.03, 525.105.17, 525.85.05, 525.60.13"
        exit 1
    fi

    local filename=$(basename "$download_url")
    echo "Downloading GRID driver from: $download_url"

    curl -fSsl -o "$filename" "$download_url"
    chmod +x "$filename"

    echo "GRID installer downloaded successfully to $GRID_INSTALLER_DIR/$filename"
}

fetch_grid_azure_installer
