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
TRIGGER="${TRIGGER:-/tmp/pn-trigger}"

if [ ! -d "${VM}" ]; then
    echo "VM bundle not found: ${VM}" >&2
    exit 1
fi
if [ ! -f "${IMAGE}" ]; then
    echo "Image not found: ${IMAGE}" >&2
    exit 1
fi

# Two distinct cases. PNAutoStart's #startUp: only fires on a fresh
# image launch, so when Pharo is already running we have to nudge the
# image's running trigger-file watcher instead.
if pgrep -f "${VM}/Contents/MacOS/" >/dev/null; then
    echo "Pharo already running; firing native browser via trigger file"
    touch "${TRIGGER}"
    open -a "${VM}"   # bring focus
else
    echo "Launching Pharo (Morphic + native System Browser) on ${IMAGE}"
    touch "${MARKER}"
    # Image path is in Pharo.app's Info.plist (stamped by install.sh)
    # so a bare `open -a` is enough.
    open -a "${VM}"
fi
