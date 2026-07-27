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
firmware_dest="${dest}/firmware"

# Shared build metadata (not device images).
shared_files=(
  config.buildinfo
  feeds.buildinfo
  version.buildinfo
)

rm -rf "${firmware_dest}"
mkdir -p "${firmware_dest}"

copied=0
for name in "${shared_files[@]}"; do
  if [[ -f "${target_output}/${name}" ]]; then
    cp -a "${target_output}/${name}" "${firmware_dest}/"
    copied=$((copied + 1))
  fi
done

# Device images / manifests / bootloader artifacts named with this profile only.
# OpenWrt leaves other devices' leftovers under the same filogic/ directory;
# never rsync the whole tree into a per-device output folder.
shopt -s nullglob
device_files=("${target_output}/"*"${DEVICE_PROFILE}"*)
shopt -u nullglob

if (( ${#device_files[@]} == 0 )); then
  die "no firmware artifacts found for profile ${DEVICE_PROFILE} under ${target_output}"
fi

for src in "${device_files[@]}"; do
  [[ -e "${src}" ]] || continue
  # Skip directories accidentally matching the profile name.
  [[ -f "${src}" ]] || continue
  cp -a "${src}" "${firmware_dest}/"
  copied=$((copied + 1))
done

# Target package feed is shared across devices on the same target/arch; keep it.
if [[ -d "${target_output}/packages" ]]; then
  rsync -a "${target_output}/packages/" "${firmware_dest}/packages/"
fi

# Keep only this device in profiles.json when the file exists.
if [[ -f "${target_output}/profiles.json" ]]; then
  python3 - "${target_output}/profiles.json" "${firmware_dest}/profiles.json" "${DEVICE_PROFILE}" <<'PY'
import json
import sys

src, dst, profile = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, encoding="utf-8") as f:
    data = json.load(f)

profiles = data.get("profiles")
if isinstance(profiles, dict):
    if profile not in profiles:
        raise SystemExit(f"profile {profile!r} missing from profiles.json")
    data["profiles"] = {profile: profiles[profile]}

with open(dst, "w", encoding="utf-8") as f:
    json.dump(data, f, separators=(",", ":"), ensure_ascii=False)
    f.write("\n")
PY
fi

# Rebuild sha256sums for the files we actually collected (exclude packages/).
(
  cd "${firmware_dest}"
  # shellcheck disable=SC2035
  mapfile -t sum_targets < <(find . -maxdepth 1 -type f ! -name sha256sums | sed 's|^\./||' | LC_ALL=C sort)
  if (( ${#sum_targets[@]} > 0 )); then
    sha256sum --binary -- "${sum_targets[@]}" > sha256sums
  fi
)

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
log "output summary:"
log "  device profile: ${DEVICE_PROFILE}"
log "  firmware artifacts: ${copied} file(s) + packages/ (filtered by profile)"
log "  firmware output: ${dest}"
ls -1 "${firmware_dest}" | while IFS= read -r entry; do
  log "    ${entry}"
done
