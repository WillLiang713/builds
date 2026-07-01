#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

ensure_dirs
ensure_source_tree

target_output="${SOURCE_DIR}/bin/targets/mediatek/filogic"
[[ -d "${target_output}" ]] || die "target output not found: ${target_output}"

short_sha="$(git -C "${SOURCE_DIR}" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
stamp="${OUTPUT_STAMP:-$(date +%F)-${short_sha}}"
dest="${OUTPUT_DIR}/${stamp}"

mkdir -p "${dest}/firmware"
rsync -a --delete "${target_output}/" "${dest}/firmware/"

if [[ -f "${SOURCE_DIR}/.config" ]]; then
  cp "${SOURCE_DIR}/.config" "${dest}/full.config"
fi

if [[ -x "${SOURCE_DIR}/scripts/diffconfig.sh" ]]; then
  (cd "${SOURCE_DIR}" && ./scripts/diffconfig.sh) > "${dest}/diffconfig"
fi

cat > "${dest}/build-info.txt" <<EOF
upstream_repo=${UPSTREAM_REPO}
upstream_ref=${UPSTREAM_REF}
source_commit=${short_sha}
device_profile=$(detect_device_profile)
output_created_at=$(date -Iseconds)
EOF

log "output copied to: ${dest}"
