#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${PROJECT_ROOT}/.env}"

load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
  fi
}

load_env

WORKSPACE="${WORKSPACE:-${PROJECT_ROOT}}"
SOURCE_DIR="${SOURCE_DIR:-${WORKSPACE}/source}"
OUTPUT_DIR="${OUTPUT_DIR:-${WORKSPACE}/output}"
DL_DIR="${DL_DIR:-${WORKSPACE}/dl}"
CCACHE_DIR="${CCACHE_DIR:-${WORKSPACE}/ccache}"
BASE_DEFCONFIG="${BASE_DEFCONFIG:-}"

UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/padavanonly/immortalwrt-mt798x-6.6.git}"
UPSTREAM_REF="${UPSTREAM_REF:-}"

DEVICE_PROFILE="${DEVICE_PROFILE:-}"

DEFAULT_SEED="${DEFAULT_SEED:-${WORKSPACE}/configs/default.seed}"
CUSTOM_SEED="${CUSTOM_SEED:-${WORKSPACE}/configs/custom.seed}"
DEVICE_SEED_DIR="${DEVICE_SEED_DIR:-${WORKSPACE}/configs/devices}"

NIKKI_FEED_NAME="${NIKKI_FEED_NAME:-nikki}"
NIKKI_FEED_URL="${NIKKI_FEED_URL:-https://github.com/nikkinikki-org/OpenWrt-nikki.git}"
NIKKI_FEED_BRANCH="${NIKKI_FEED_BRANCH:-main}"
NIKKI_MIHOMO_PROVIDER="${NIKKI_MIHOMO_PROVIDER:-mihomo-meta}"
# Official signed binary repo used on-device by opkg (not the compile-time Git feed).
NIKKI_OPKG_REPO="${NIKKI_OPKG_REPO:-https://nikkinikki.pages.dev}"
ROOTFS_FILES_DIR="${ROOTFS_FILES_DIR:-${WORKSPACE}/files}"

# LuCI app: Tokisaki-Galaxy community panel; daemon still comes from packages feed.
TAILSCALE_LUCI_URL="${TAILSCALE_LUCI_URL:-https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community.git}"
TAILSCALE_LUCI_BRANCH="${TAILSCALE_LUCI_BRANCH:-master}"
# On-device opkg host for upgrading luci-app-tailscale-community (not the daemon).
TAILSCALE_OPKG_REPO="${TAILSCALE_OPKG_REPO:-https://Tokisaki-Galaxy.github.io/luci-app-tailscale-community}"

# USB shared-/64 IPv6 defaults (docs/f50-ipv6.md). Enabled by default for TR3000 (eth2/USB).
USB_IPV6_ENABLE="${USB_IPV6_ENABLE:-1}"
USB_DEVICE="${USB_DEVICE:-eth2}"
USB_IPV4_IFACE="${USB_IPV4_IFACE:-USB}"
USB_IPV6_IFACE="${USB_IPV6_IFACE:-USB6}"

JOBS="${JOBS:-$(nproc 2>/dev/null || printf '1')}"
BUILD_VERBOSE="${BUILD_VERBOSE:-0}"

log() {
  printf '[builder] %s\n' "$*"
}

die() {
  printf '[builder] ERROR: %s\n' "$*" >&2
  exit 1
}

ensure_dirs() {
  mkdir -p "${SOURCE_DIR}" "${OUTPUT_DIR}" "${DL_DIR}" "${CCACHE_DIR}" "${DEVICE_SEED_DIR}"
}

ensure_source_tree() {
  [[ -f "${SOURCE_DIR}/Makefile" ]] || die "source tree is missing. Run: make"
  [[ -x "${SOURCE_DIR}/scripts/feeds" ]] || die "OpenWrt feeds helper is missing under source/scripts/feeds"
  sync_bundled_dl_archives
}

sync_bundled_dl_archives() {
  local bundled_dl="${SOURCE_DIR}/dl"
  [[ -d "${bundled_dl}" ]] || return 0

  mkdir -p "${DL_DIR}"

  local bundled_real dl_real file base missing=0
  bundled_real="$(readlink -f "${bundled_dl}")"
  dl_real="$(readlink -f "${DL_DIR}")"
  [[ "${bundled_real}" == "${dl_real}" ]] && return 0

  while IFS= read -r -d '' file; do
    base="$(basename "${file}")"
    [[ -e "${DL_DIR}/${base}" ]] || missing=1
  done < <(find "${bundled_dl}" -maxdepth 1 -type f -print0)

  (( missing )) || return 0

  log "copying bundled source archives from ${bundled_dl} to ${DL_DIR}"
  while IFS= read -r -d '' file; do
    base="$(basename "${file}")"
    [[ -e "${DL_DIR}/${base}" ]] && continue
    cp -p "${file}" "${DL_DIR}/${base}"
  done < <(find "${bundled_dl}" -maxdepth 1 -type f -print0)
}

filogic_image_file() {
  printf '%s\n' "${SOURCE_DIR}/target/linux/mediatek/image/filogic.mk"
}

ensure_filogic_image_file() {
  local file
  file="$(filogic_image_file)"
  [[ -f "${file}" ]] || die "Filogic device definitions not found. Run: make"
}

require_device_profile() {
  [[ -n "${DEVICE_PROFILE}" ]] || die "no device selected. Run: make and choose a device profile"
}

run_make() {
  make -C "${SOURCE_DIR}" DL_DIR="${DL_DIR}" "$@"
}

update_env_var() {
  local key="$1"
  local value="$2"
  local tmp

  touch "${ENV_FILE}"
  tmp="$(mktemp)"
  awk -v key="${key}" -v value="${value}" '
    BEGIN { done = 0 }
    $0 ~ "^[[:space:]]*" key "=" {
      print key "=" value
      done = 1
      next
    }
    { print }
    END {
      if (!done) {
        print key "=" value
      }
    }
  ' "${ENV_FILE}" > "${tmp}"
  mv "${tmp}" "${ENV_FILE}"
}

verify_profile_exists() {
  local profile="$1"
  local image_file
  image_file="$(filogic_image_file)"
  [[ -f "${image_file}" ]] || die "Filogic device definitions not found: ${image_file}"

  awk -v wanted="${profile}" '
    /^[[:space:]]*TARGET_DEVICES[[:space:]]*\+=/ {
      sub(/^[^+]*\+=[[:space:]]*/, "")
      for (i = 1; i <= NF; i++) {
        if ($i == wanted) {
          found = 1
        }
      }
    }
    END { exit found ? 0 : 1 }
  ' "${image_file}"
}

device_dts_for_profile() {
  local profile="$1"
  local image_file
  image_file="$(filogic_image_file)"
  [[ -f "${image_file}" ]] || die "Filogic device definitions not found: ${image_file}"

  awk -v wanted="${profile}" '
    $0 == "define Device/" wanted {
      in_block = 1
      next
    }
    in_block && /^[[:space:]]*DEVICE_DTS[[:space:]]*:=/ {
      value = $0
      sub(/^[^:]+:=[[:space:]]*/, "", value)
      split(value, parts, /[[:space:]]+/)
      print parts[1]
      found = 1
      exit
    }
    in_block && /^endef/ {
      exit
    }
    END {
      exit found ? 0 : 1
    }
  ' "${image_file}"
}

detect_base_defconfig() {
  local profile="$1"
  local dts
  local candidates=()
  local candidate

  dts="$(device_dts_for_profile "${profile}")" || die "unable to detect DEVICE_DTS for profile: ${profile}"

  case "${dts}" in
    mt7981*)
      candidates=("mt7981-ax3000.config")
      ;;
    mt7986*)
      candidates=("mt7986-ax6000.config" "mt7986-ax4200-bpir3_mini.config")
      ;;
    mt7988*)
      candidates=("mt7988-ax*.config")
      ;;
    *)
      die "unsupported Filogic DTS for automatic BASE_DEFCONFIG: ${dts}"
      ;;
  esac

  for candidate in "${candidates[@]}"; do
    for path in "${SOURCE_DIR}"/defconfig/${candidate}; do
      if [[ -f "${path}" ]]; then
        printf '%s\n' "${path}"
        return 0
      fi
    done
  done

  die "no suitable BASE_DEFCONFIG found for ${profile} (${dts}); set BASE_DEFCONFIG in .env"
}

selected_seed_files() {
  local device_seed="${DEVICE_SEED_DIR}/${DEVICE_PROFILE}.seed"

  [[ -f "${DEFAULT_SEED}" ]] && printf '%s\n' "${DEFAULT_SEED}"
  [[ -n "${DEVICE_PROFILE}" && -f "${device_seed}" ]] && printf '%s\n' "${device_seed}"
  [[ -f "${CUSTOM_SEED}" ]] && printf '%s\n' "${CUSTOM_SEED}"
}

require_config_symbol() {
  local symbol="$1"
  local config_file="${SOURCE_DIR}/.config"
  grep -Eq "^${symbol}=y$" "${config_file}" || die "required config symbol missing after defconfig: ${symbol}"
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
      rm -f "${package_dir:?}/${provider}"
      rm -f "${SOURCE_DIR}/tmp/info/.packageinfo-feeds_${NIKKI_FEED_NAME}_${provider}"
      changed=1
    fi
  done

  if (( changed )); then
    rm -f "${SOURCE_DIR}/tmp/.config-package.in"
  fi
}

# OpenWrt copies $(TOPDIR)/files onto the rootfs. Keep SOURCE_DIR/files in sync
# with the project overlay (signed opkg keys + first-boot feed setup).
sync_rootfs_overlay() {
  local src="${ROOTFS_FILES_DIR}"
  local dst="${SOURCE_DIR}/files"
  local feed_script

  [[ -d "${src}" ]] || return 0

  log "syncing rootfs overlay: ${src} -> ${dst}"
  mkdir -p "${dst}"
  # Refresh managed tree without deleting unrelated files under source/files.
  (cd "${src}" && tar cf - .) | (cd "${dst}" && tar xf -)

  if [[ -d "${dst}/etc/uci-defaults" ]]; then
    find "${dst}/etc/uci-defaults" -type f -exec chmod +x {} +
  fi

  # Allow overriding feed hosts without editing the overlay templates.
  feed_script="${dst}/etc/uci-defaults/99_nikki_opkg_feed"
  if [[ -f "${feed_script}" && "${NIKKI_OPKG_REPO}" != "https://nikkinikki.pages.dev" ]]; then
    sed -i "s|https://nikkinikki.pages.dev|${NIKKI_OPKG_REPO}|g" "${feed_script}"
  fi

  feed_script="${dst}/etc/uci-defaults/99_tailscale_community_opkg_feed"
  if [[ -f "${feed_script}" && "${TAILSCALE_OPKG_REPO}" != "https://Tokisaki-Galaxy.github.io/luci-app-tailscale-community" ]]; then
    sed -i "s|https://Tokisaki-Galaxy.github.io/luci-app-tailscale-community|${TAILSCALE_OPKG_REPO}|g" "${feed_script}"
  fi

  apply_usb_ipv6_overlay "${dst}"
}

# Bake or strip the USB IPv6 first-boot defaults under the synced rootfs overlay.
apply_usb_ipv6_overlay() {
  local dst="$1"
  local script="${dst}/etc/uci-defaults/99_f50_ipv6"

  case "${USB_IPV6_ENABLE}" in
    1|yes|true|on|ON|Yes|True) ;;
    *)
      if [[ -f "${script}" ]]; then
        log "USB_IPV6_ENABLE=${USB_IPV6_ENABLE}: removing ${script}"
        rm -f "${script}"
      fi
      return 0
      ;;
  esac

  [[ -f "${script}" ]] || return 0

  log "enabling USB IPv6 defaults: device=${USB_DEVICE} ipv4=${USB_IPV4_IFACE} ipv6=${USB_IPV6_IFACE}"
  # Rewrite the three shell assignments near the top of the uci-defaults script.
  sed -i \
    -e "s|^USB_DEVICE=.*|USB_DEVICE=\"${USB_DEVICE}\"|" \
    -e "s|^USB_IPV4_IFACE=.*|USB_IPV4_IFACE=\"${USB_IPV4_IFACE}\"|" \
    -e "s|^USB_IPV6_IFACE=.*|USB_IPV6_IFACE=\"${USB_IPV6_IFACE}\"|" \
    "${script}"
  chmod +x "${script}"
}

# Prevent base-files from writing VERSION_REPO/.../nikki into distfeeds.conf.
disable_nikki_distfeed_config() {
  local config_file="${SOURCE_DIR}/.config"
  [[ -f "${config_file}" ]] || return 0

  if grep -Eq '^CONFIG_FEED_nikki=y$' "${config_file}"; then
    log "disabling CONFIG_FEED_nikki (avoids broken ImmortalWrt mirror nikki distfeed)"
  fi

  sed -i \
    -e '/^CONFIG_FEED_nikki=/d' \
    -e '/^# CONFIG_FEED_nikki /d' \
    "${config_file}"
  printf '# CONFIG_FEED_nikki is not set\n' >> "${config_file}"
}

# Sync Tokisaki-Galaxy/luci-app-tailscale-community into package/.
# Upstream layout is repo/luci-app-tailscale-community/Makefile (not repo-root Makefile).
ensure_luci_app_tailscale() {
  local url="${TAILSCALE_LUCI_URL}"
  local branch="${TAILSCALE_LUCI_BRANCH}"
  local clone_dir="${SOURCE_DIR}/.package-src/luci-app-tailscale-community"
  local dest="${SOURCE_DIR}/package/luci-app-tailscale-community"
  local pkg_src
  local old_dest="${SOURCE_DIR}/package/luci-app-tailscale"

  mkdir -p "${SOURCE_DIR}/package" "${SOURCE_DIR}/.package-src"

  # Drop the previous asvow package path if it remains from older builder configs.
  if [[ -e "${old_dest}" ]]; then
    log "removing legacy package path: ${old_dest}"
    rm -rf "${old_dest}"
  fi

  if [[ -d "${clone_dir}/.git" ]]; then
    log "updating luci-app-tailscale-community: ${url} (${branch})"
    git -C "${clone_dir}" fetch --tags origin
    git -C "${clone_dir}" checkout "${branch}"
    if git -C "${clone_dir}" rev-parse --verify "origin/${branch}" >/dev/null 2>&1; then
      git -C "${clone_dir}" merge --ff-only "origin/${branch}"
    fi
  elif [[ -e "${clone_dir}" ]]; then
    die "luci-app-tailscale-community clone path exists but is not a git checkout: ${clone_dir}"
  else
    log "cloning luci-app-tailscale-community: ${url} (${branch})"
    git clone --depth 1 --branch "${branch}" "${url}" "${clone_dir}"
  fi

  if [[ -f "${clone_dir}/luci-app-tailscale-community/Makefile" ]]; then
    pkg_src="${clone_dir}/luci-app-tailscale-community"
  elif [[ -f "${clone_dir}/Makefile" ]]; then
    pkg_src="${clone_dir}"
  else
    die "could not find luci-app-tailscale-community Makefile under ${clone_dir}"
  fi

  log "installing package tree: ${pkg_src} -> ${dest}"
  rm -rf "${dest}"
  mkdir -p "${dest}"
  # Prefer tar over rsync so the builder image needs no extra packages.
  (cd "${pkg_src}" && tar cf - --exclude='.git' .) | (cd "${dest}" && tar xf -)

  [[ -f "${dest}/Makefile" ]] || die "luci-app-tailscale-community Makefile missing under ${dest}"
}
