#!/usr/bin/env bash
#
# Install the PharoNativeBridge packages into the freshly bootstrapped
# Pharo image, then save the image so the bridge persists across launches.
#
# Defaults assume the standard repo layout:
#   <repo>/pharo-vm/build/build/vm/Debug/Pharo.app   (built VM)
#   <repo>/pharo/build/bootstrap-cache/Pharo.image   (bootstrapped image)
#   <repo>/pharo-bridge/                             (this folder)
#
# Override with env vars: VM, IMAGE.

set -eu

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P)"
REPO_ROOT="$(cd "${SCRIPTS_DIR}/../.." ; pwd -P)"

VM="${VM:-${REPO_ROOT}/pharo-vm/build/build/vm/Debug/Pharo.app/Contents/MacOS/Pharo}"
IMAGE="${IMAGE:-${REPO_ROOT}/pharo/build/bootstrap-cache/Pharo.image}"

if [ ! -x "${VM}" ]; then
    echo "VM not found or not executable: ${VM}" >&2
    exit 1
fi
if [ ! -f "${IMAGE}" ]; then
    echo "Image not found: ${IMAGE}" >&2
    exit 1
fi

echo "Installing PharoNativeBridge into ${IMAGE}"
echo "  using VM: ${VM}"

PHARO_BRIDGE_REPO="${REPO_ROOT}/pharo-bridge" \
"${VM}" --headless "${IMAGE}" \
    st "${SCRIPTS_DIR}/install.st" \
    --save --quit

# Stamp the VM bundle's Info.plist with the image path so `open -a Pharo.app`
# launches straight into the image instead of putting up the "Choose an image
# file" picker. Idempotent: PlistBuddy 'Set' if present, 'Add' otherwise.
PLIST="${REPO_ROOT}/pharo-vm/build/build/vm/Debug/Pharo.app/Contents/Info.plist"
if [ -f "${PLIST}" ]; then
    echo "Stamping VM bundle Info.plist with PharoImageFile=${IMAGE}"
    /usr/libexec/PlistBuddy -c "Set :PharoImageFile ${IMAGE}" "${PLIST}" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :PharoImageFile string ${IMAGE}" "${PLIST}"
fi

echo "Done. Launch the image normally; Browse -> Native System Browser is now available."
