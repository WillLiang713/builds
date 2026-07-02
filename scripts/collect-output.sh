#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

ensure_dirs
ensure_source_tree
require_device_profile
verify_profile_exists "${DEVICE_PROFILE}" || die "DEVICE_PROFILE was not found in upstream Filogic targets: ${DEVICE_PROFILE}"

if [[ -z "${BASE_DEFCONFIG}" ]]; then
  BASE_DEFCONFIG="$(detect_base_defconfig "${DEVICE_PROFILE}")"
fi

target_output="${SOURCE_DIR}/bin/targets/mediatek/filogic"
[[ -d "${target_output}" ]] || die "target output not found: ${target_output}"

short_sha="$(git -C "${SOURCE_DIR}" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
stamp="${OUTPUT_STAMP:-$(date +%F)-${short_sha}}"
dest="${OUTPUT_DIR}/${DEVICE_PROFILE}/${stamp}"

mkdir -p "${dest}/firmware"
rsync -a --delete "${target_output}/" "${dest}/firmware/"

if [[ -f "${SOURCE_DIR}/.config" ]]; then
  cp "${SOURCE_DIR}/.config" "${dest}/full.config"
fi

if [[ -x "${SOURCE_DIR}/scripts/diffconfig.sh" ]]; then
  (cd "${SOURCE_DIR}" && ./scripts/diffconfig.sh) > "${dest}/diffconfig"
fi

{
  printf 'upstream_repo=%s\n' "${UPSTREAM_REPO}"
  printf 'upstream_ref=%s\n' "${UPSTREAM_REF}"
  printf 'source_commit=%s\n' "${short_sha}"
  printf 'device_profile=%s\n' "${DEVICE_PROFILE}"
  printf 'base_defconfig=%s\n' "${BASE_DEFCONFIG}"
  printf 'seed_files='
  first=1
  while IFS= read -r seed_file; do
    if (( first )); then
      first=0
    else
      printf ','
    fi
    printf '%s' "${seed_file}"
  done < <(selected_seed_files)
  printf '\n'
  printf 'output_created_at=%s\n' "$(date -Iseconds)"
} > "${dest}/build-info.txt"

log "output copied to: ${dest}"
