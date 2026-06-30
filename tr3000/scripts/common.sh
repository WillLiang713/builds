#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
SOURCE_DIR="${SOURCE_DIR:-${WORKSPACE}/source}"
OUTPUT_DIR="${OUTPUT_DIR:-${WORKSPACE}/output}"
DL_DIR="${DL_DIR:-${WORKSPACE}/dl}"
CCACHE_DIR="${CCACHE_DIR:-${WORKSPACE}/ccache}"
CONFIG_SEED="${CONFIG_SEED:-${WORKSPACE}/configs/cudy_tr3000_128m.seed}"
BASE_DEFCONFIG="${BASE_DEFCONFIG:-${SOURCE_DIR}/defconfig/mt7981-ax3000.config}"

UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/padavanonly/immortalwrt-mt798x-6.6.git}"
UPSTREAM_REF="${UPSTREAM_REF:-}"

DEVICE_PROFILE="${DEVICE_PROFILE:-cudy_tr3000-v1-ubootmod}"
DEVICE_KEYWORDS="${DEVICE_KEYWORDS:-cudy,tr3000}"
DEVICE_VARIANT_KEYWORD="${DEVICE_VARIANT_KEYWORD:-128}"

NIKKI_FEED_NAME="${NIKKI_FEED_NAME:-nikki}"
NIKKI_FEED_URL="${NIKKI_FEED_URL:-https://github.com/nikkinikki-org/OpenWrt-nikki.git}"
NIKKI_FEED_BRANCH="${NIKKI_FEED_BRANCH:-main}"
NIKKI_MIHOMO_PROVIDER="${NIKKI_MIHOMO_PROVIDER:-mihomo-meta}"

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

select_nikki_mihomo_provider() {
  case "${NIKKI_MIHOMO_PROVIDER}" in
    mihomo-meta|mihomo-alpha) ;;
    *) die "unsupported NIKKI_MIHOMO_PROVIDER: ${NIKKI_MIHOMO_PROVIDER}" ;;
  esac

  local package_dir="${SOURCE_DIR}/package/feeds/${NIKKI_FEED_NAME}"
  [[ -d "${package_dir}" ]] || return 0

  local changed=0
  local provider
  for provider in mihomo-meta mihomo-alpha; do
    [[ "${provider}" == "${NIKKI_MIHOMO_PROVIDER}" ]] && continue

    if [[ -e "${package_dir}/${provider}" || -L "${package_dir}/${provider}" ]]; then
      log "disabling nikki mihomo provider: ${provider}"
      rm -f "${package_dir}/${provider}"
      rm -f "${SOURCE_DIR}/tmp/info/.packageinfo-feeds_${NIKKI_FEED_NAME}_${provider}"
      changed=1
    fi
  done

  if (( changed )); then
    rm -f "${SOURCE_DIR}/tmp/.config-package.in"
  fi
}

patch_tr3000_ubootmod_itb_profile() {
  local image_file="${SOURCE_DIR}/target/linux/mediatek/image/filogic.mk"
  [[ -f "${image_file}" ]] || die "mediatek filogic image definitions not found: ${image_file}"

  local tmp rc
  tmp="$(mktemp)"
  rc=0
  awk '
    $0 == "define Device/cudy_tr3000-v1-ubootmod" {
      found = 1
      in_block = 1

      print "define Device/cudy_tr3000-v1-ubootmod"
      print "  DEVICE_VENDOR := Cudy"
      print "  DEVICE_MODEL := TR3000"
      print "  DEVICE_VARIANT := v1 (OpenWrt U-Boot layout)"
      print "  DEVICE_DTS := mt7981b-cudy-tr3000-v1-ubootmod"
      print "  DEVICE_DTS_DIR := ../dts"
      print "  SUPPORTED_DEVICES += R47"
      print "  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount"
      print "  UBINIZE_OPTS := -E 5"
      print "  BLOCKSIZE := 128k"
      print "  PAGESIZE := 2048"
      print "  IMAGE_SIZE := 114688k"
      print "  KERNEL_IN_UBI := 1"
      print "  UBOOTENV_IN_UBI := 1"
      print "  IMAGES := sysupgrade.itb"
      print "  KERNEL_INITRAMFS_SUFFIX := -recovery.itb"
      print "  KERNEL := kernel-bin | gzip"
      print "  KERNEL_INITRAMFS := kernel-bin | lzma | \\"
      print "\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k"
      print "  IMAGE/sysupgrade.itb := append-kernel | \\"
      print "\tfit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | append-metadata"
      print "  ARTIFACTS := preloader.bin bl31-uboot.fip"
      print "  ARTIFACT/preloader.bin := mt7981-bl2 cudy-tr3000-v1"
      print "  ARTIFACT/bl31-uboot.fip := mt7981-bl31-uboot cudy_tr3000-v1"
      next
    }

    in_block && $0 == "endef" {
      in_block = 0
      print
      next
    }

    in_block {
      next
    }

    {
      print
    }

    END {
      if (!found) {
        exit 42
      }
    }
  ' "${image_file}" > "${tmp}" || rc=$?

  if (( rc != 0 )); then
    rm -f "${tmp}"
    if (( rc == 42 )); then
      die "Cudy TR3000 ubootmod profile was not found in image definitions"
    fi
    die "failed to patch Cudy TR3000 ubootmod image definition"
  fi

  if cmp -s "${tmp}" "${image_file}"; then
    rm -f "${tmp}"
  else
    mv "${tmp}" "${image_file}"
    log "patched Cudy TR3000 ubootmod profile to emit sysupgrade.itb"
  fi
}

clean_device_output_artifacts() {
  local target_output="${SOURCE_DIR}/bin/targets/mediatek/filogic"
  [[ -d "${target_output}" ]] || return 0

  local prefix="immortalwrt-mediatek-filogic-${DEVICE_PROFILE}"
  local removed=0
  local artifact

  shopt -s nullglob
  for artifact in "${target_output}/${prefix}-"* "${target_output}/${prefix}.manifest"; do
    rm -f "${artifact}"
    removed=1
  done
  shopt -u nullglob

  if (( removed )); then
    rm -f "${target_output}/profiles.json" "${target_output}/sha256sums"
    log "removed stale firmware artifacts for ${DEVICE_PROFILE}"
  fi
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
