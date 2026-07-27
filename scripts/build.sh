#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

"${SCRIPT_DIR}/defconfig.sh"

# defconfig already synced the overlay; refresh again in case files/ changed mid-session.
sync_rootfs_overlay
disable_nikki_distfeed_config

make_args=("-j${JOBS}")
if [[ "${BUILD_VERBOSE}" == "1" ]]; then
  make_args+=("V=s")
fi

log "building firmware for ${DEVICE_PROFILE} with ${JOBS} jobs"
run_make "${make_args[@]}"

"${SCRIPT_DIR}/collect-output.sh"
log "build complete for ${DEVICE_PROFILE}"
