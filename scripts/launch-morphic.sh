#!/usr/bin/env bash
#
# Launch Pharo in plain Morphic-only mode against the project image.
# The same image as launch-native.sh; the only difference is whether
# PNAutoStart finds its marker file on startup.

set -eu

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P)"
REPO_ROOT="$(cd "${SCRIPTS_DIR}/.." ; pwd -P)"

VM="${VM:-${REPO_ROOT}/pharo-vm/build/build/vm/Debug/Pharo.app}"
IMAGE="${IMAGE:-${REPO_ROOT}/pharo/build/bootstrap-cache/Pharo.image}"
MARKER="${MARKER:-/tmp/pn-launch-native}"

if [ ! -d "${VM}" ]; then
    echo "VM bundle not found: ${VM}" >&2
    exit 1
fi
if [ ! -f "${IMAGE}" ]; then
    echo "Image not found: ${IMAGE}" >&2
    exit 1
fi

# Make sure no stale marker triggers an unexpected native window.
rm -f "${MARKER}"

echo "Launching Pharo (plain Morphic) on ${IMAGE}"
# The image path is baked into Pharo.app/Contents/Info.plist by
# pharo-bridge/scripts/install.sh, so a bare `open -a` is enough --
# Pharo reads PharoImageFile from the bundle and finds the image
# without any "Choose an image file" picker.
open -a "${VM}"
