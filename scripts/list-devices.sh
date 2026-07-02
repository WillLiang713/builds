#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

raw=0
if [[ "${1:-}" == "--raw" ]]; then
  raw=1
fi

ensure_filogic_image_file

awk -v raw="${raw}" '
  function trim(s) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    return s
  }

  function field_value(line) {
    sub(/^[^:]+:=/, "", line)
    return trim(line)
  }

  /^define Device\// {
    current = $0
    sub(/^define Device\//, "", current)
    vendor[current] = ""
    model[current] = ""
    variant[current] = ""
    next
  }

  current != "" && /^[[:space:]]*DEVICE_VENDOR[[:space:]]*:=/ {
    vendor[current] = field_value($0)
    next
  }

  current != "" && /^[[:space:]]*DEVICE_MODEL[[:space:]]*:=/ {
    model[current] = field_value($0)
    next
  }

  current != "" && /^[[:space:]]*DEVICE_VARIANT[[:space:]]*:=/ {
    variant[current] = field_value($0)
    next
  }

  current != "" && /^endef/ {
    current = ""
    next
  }

  /^[[:space:]]*TARGET_DEVICES[[:space:]]*\+=/ {
    sub(/^[^+]*\+=[[:space:]]*/, "")
    for (i = 1; i <= NF; i++) {
      profile = $i
      if (!(profile in seen)) {
        order[++count] = profile
        seen[profile] = 1
      }
    }
  }

  END {
    for (i = 1; i <= count; i++) {
      profile = order[i]
      display = trim(vendor[profile] " " model[profile] " " variant[profile])
      if (display == "") {
        display = profile
      }

      if (raw == 1) {
        printf "%s\t%s\t%s\t%s\n", profile, vendor[profile], model[profile], variant[profile]
      } else {
        printf "%4d. %-38s %s\n", i, profile, display
      }
    }
  }
' "$(filogic_image_file)"
