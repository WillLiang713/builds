#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

mode="${1:-clean}"
ensure_source_tree

case "${mode}" in
  clean)
    log "running OpenWrt clean"
    run_make clean
    ;;
  distclean)
    log "removing generated build state under source/"
    for name in build_dir staging_dir tmp bin logs .config .config.old; do
      target="${SOURCE_DIR}/${name}"
      case "${target}" in
        "${SOURCE_DIR}"/*) rm -rf "${target}" ;;
        *) die "refusing to remove path outside source: ${target}" ;;
      esac
    done
    ;;
  *)
    die "unknown clean mode: ${mode}"
    ;;
esac
