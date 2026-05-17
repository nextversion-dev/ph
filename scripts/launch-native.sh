#!/usr/bin/env bash
#
# Launch Pharo against the project image with the native System Browser
# auto-opened at session startup. Same image as launch-morphic.sh; we
# just create the marker file PNAutoStart consumes on its first
# startUp: hook.
#
# Once the image is up you have both Morphic and a native NSWindow
# rendered by PharoNativeShell.app, both looking at the same live image.

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

# PNAutoStart consumes (deletes) this file when it fires, so a successful
# launch leaves the workspace clean for the next launch-morphic.sh.
touch "${MARKER}"

echo "Launching Pharo (Morphic + native System Browser) on ${IMAGE}"
# Image path is in Pharo.app's Info.plist (stamped by install.sh), so
# a bare `open -a` is enough.
open -a "${VM}"
