#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
SOURCE_DIR="${SOURCE_DIR:-${WORKSPACE}/source}"
OUTPUT_DIR="${OUTPUT_DIR:-${WORKSPACE}/output}"
DL_DIR="${DL_DIR:-${WORKSPACE}/dl}"
CCACHE_DIR="${CCACHE_DIR:-${WORKSPACE}/ccache}"
CONFIG_SEED="${CONFIG_SEED:-${WORKSPACE}/configs/cudy_tr3000_128m.seed}"

UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/padavanonly/immortalwrt-mt798x-6.6.git}"
UPSTREAM_REF="${UPSTREAM_REF:-}"

DEVICE_PROFILE="${DEVICE_PROFILE:-}"
DEVICE_KEYWORDS="${DEVICE_KEYWORDS:-cudy,tr3000}"
DEVICE_VARIANT_KEYWORD="${DEVICE_VARIANT_KEYWORD:-128}"

NIKKI_FEED_NAME="${NIKKI_FEED_NAME:-nikki}"
NIKKI_FEED_URL="${NIKKI_FEED_URL:-https://github.com/nikkinikki-org/OpenWrt-nikki.git}"
NIKKI_FEED_BRANCH="${NIKKI_FEED_BRANCH:-main}"

JOBS="${JOBS:-$(nproc)}"
BUILD_VERBOSE="${BUILD_VERBOSE:-0}"

log() {
  printf '[tr3000] %s\n' "$*"
}

die() {
  printf '[tr3000] ERROR: %s\n' "$*" >&2
  exit 1
}

ensure_dirs() {
  mkdir -p "${SOURCE_DIR}" "${OUTPUT_DIR}" "${DL_DIR}" "${CCACHE_DIR}"
}

ensure_source_tree() {
  [[ -f "${SOURCE_DIR}/Makefile" ]] || die "source tree is missing. Run: make init"
  [[ -x "${SOURCE_DIR}/scripts/feeds" ]] || die "OpenWrt feeds helper is missing under source/scripts/feeds"
}

run_make() {
  make -C "${SOURCE_DIR}" DL_DIR="${DL_DIR}" "$@"
}

find_package_makefile() {
  local package_name="$1"
  local base

  for base in "${SOURCE_DIR}/package" "${SOURCE_DIR}/feeds"; do
    [[ -d "${base}" ]] || continue
    find "${base}" \
      \( -path '*/build_dir/*' -o -path '*/staging_dir/*' -o -path '*/tmp/*' \) -prune \
      -o -type f -path "*/${package_name}/Makefile" -print -quit
  done
}

verify_profile_exists() {
  local profile="$1"
  local image_dir="${SOURCE_DIR}/target/linux/mediatek/image"
  [[ -d "${image_dir}" ]] || die "mediatek image directory not found: ${image_dir}"

  find "${image_dir}" -type f -name '*.mk' -print0 \
    | xargs -0 awk -v wanted="${profile}" '
        $0 == "define Device/" wanted { found = 1 }
        END { exit found ? 0 : 1 }
      '
}

detect_device_profile() {
  local image_dir="${SOURCE_DIR}/target/linux/mediatek/image"
  [[ -d "${image_dir}" ]] || die "mediatek image directory not found: ${image_dir}"

  if [[ -n "${DEVICE_PROFILE}" ]]; then
    verify_profile_exists "${DEVICE_PROFILE}" || die "DEVICE_PROFILE was not found in image definitions: ${DEVICE_PROFILE}"
    printf '%s\n' "${DEVICE_PROFILE}"
    return
  fi

  local rows=()
  mapfile -t rows < <(
    find "${image_dir}" -type f -name '*.mk' -print0 \
      | xargs -0 awk -v keywords="${DEVICE_KEYWORDS}" -v variant="${DEVICE_VARIANT_KEYWORD}" '
          BEGIN {
            n = split(tolower(keywords), kw, ",")
            variant = tolower(variant)
          }
          /^define Device\// {
            profile = $0
            sub(/^define Device\//, "", profile)
            block = $0 "\n"
            in_block = 1
            next
          }
          in_block {
            block = block $0 "\n"
            if ($0 ~ /^endef/) {
              low = tolower(block)
              ok = 1
              for (i = 1; i <= n; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", kw[i])
                if (kw[i] != "" && index(low, kw[i]) == 0 && index(tolower(profile), kw[i]) == 0) {
                  ok = 0
                }
              }
              if (ok) {
                kind = "base"
                if (variant == "" || index(low, variant) > 0 || index(tolower(profile), variant) > 0) {
                  kind = "variant"
                }
                print kind "\t" profile
              }
              in_block = 0
              profile = ""
              block = ""
            }
          }
        '
  )

  local variants=()
  local bases=()
  local row kind profile
  for row in "${rows[@]}"; do
    kind="${row%%$'\t'*}"
    profile="${row#*$'\t'}"
    if [[ "${kind}" == "variant" ]]; then
      variants+=("${profile}")
    else
      bases+=("${profile}")
    fi
  done

  if (( ${#variants[@]} == 1 )); then
    printf '%s\n' "${variants[0]}"
    return
  fi

  if (( ${#variants[@]} > 1 )); then
    printf '[tr3000] Multiple Cudy TR3000 variant profiles found:\n' >&2
    printf '  %s\n' "${variants[@]}" >&2
    die "set DEVICE_PROFILE in .env to the exact profile"
  fi

  if (( ${#bases[@]} == 1 )); then
    printf '%s\n' "${bases[0]}"
    return
  fi

  if (( ${#bases[@]} > 1 )); then
    printf '[tr3000] Multiple Cudy TR3000 profiles found:\n' >&2
    printf '  %s\n' "${bases[@]}" >&2
    die "set DEVICE_PROFILE in .env to the exact profile"
  fi

  die "no Cudy TR3000 profile found. Check upstream support or set DEVICE_PROFILE manually"
}

require_config_symbol() {
  local symbol="$1"
  local config_file="${SOURCE_DIR}/.config"
  grep -Eq "^${symbol}=y$" "${config_file}" || die "required config symbol missing after defconfig: ${symbol}"
}
