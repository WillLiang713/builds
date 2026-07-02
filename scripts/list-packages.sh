#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

ensure_source_tree

scan_feeds_index() {
  [[ -x "${SOURCE_DIR}/scripts/feeds" ]] || return 0
  (
    cd "${SOURCE_DIR}"
    ./scripts/feeds list 2>/dev/null || true
  ) | awk '
    /^[^[:space:]]+[[:space:]]/ {
      print $1
    }
  '
}

scan_base() {
  local base="$1"
  [[ -d "${base}" ]] || return 0
  find "${base}" \
    \( -path '*/build_dir/*' -o -path '*/staging_dir/*' -o -path '*/tmp/*' \) -prune \
    -o -type f \( -name Makefile -o -name '*.mk' \) -print
}

{
  scan_feeds_index
  scan_base "${SOURCE_DIR}/package"
  scan_base "${SOURCE_DIR}/feeds"
} | while IFS= read -r makefile; do
  if [[ -f "${makefile}" ]]; then
    awk '
      /^define Package\// {
        name = $0
        sub(/^define Package\//, "", name)
        sub(/[[:space:]].*$/, "", name)
        if (name !~ /\$/ && name !~ /\// && name != "") {
          print name
        }
      }

      /^define KernelPackage\// {
        name = $0
        sub(/^define KernelPackage\//, "", name)
        sub(/[[:space:]].*$/, "", name)
        if (name !~ /\$/ && name !~ /\// && name != "") {
          print "kmod-" name
        }
      }
    ' "${makefile}"
  else
    printf '%s\n' "${makefile}"
  fi
done | sort -u
