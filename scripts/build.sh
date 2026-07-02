#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

"${SCRIPT_DIR}/defconfig.sh"

make_args=("-j${JOBS}")
if [[ "${BUILD_VERBOSE}" == "1" ]]; then
  make_args+=("V=s")
fi

log "building firmware for ${DEVICE_PROFILE} with ${JOBS} jobs"
run_make "${make_args[@]}"

"${SCRIPT_DIR}/collect-output.sh"
