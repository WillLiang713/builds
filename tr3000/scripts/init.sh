#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

ensure_dirs

if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
  if find "${SOURCE_DIR}" -mindepth 1 -maxdepth 1 | read -r _; then
    die "source directory exists but is not a git checkout: ${SOURCE_DIR}"
  fi

  log "cloning upstream: ${UPSTREAM_REPO}"
  git clone "${UPSTREAM_REPO}" "${SOURCE_DIR}"
else
  log "using existing source checkout: ${SOURCE_DIR}"
  origin_url="$(git -C "${SOURCE_DIR}" remote get-url origin || true)"
  if [[ -n "${origin_url}" && "${origin_url}" != "${UPSTREAM_REPO}" ]]; then
    log "source origin differs from UPSTREAM_REPO: ${origin_url}"
  fi
  git -C "${SOURCE_DIR}" fetch --tags origin
fi

if [[ -n "${UPSTREAM_REF}" ]]; then
  log "checking out upstream ref: ${UPSTREAM_REF}"
  git -C "${SOURCE_DIR}" checkout "${UPSTREAM_REF}"
fi

ensure_source_tree

pushd "${SOURCE_DIR}" >/dev/null

if [[ ! -f feeds.conf ]]; then
  [[ -f feeds.conf.default ]] || die "feeds.conf.default not found"
  cp feeds.conf.default feeds.conf
fi

feed_line="src-git ${NIKKI_FEED_NAME} ${NIKKI_FEED_URL};${NIKKI_FEED_BRANCH}"
if ! grep -Eq "^src-git[[:space:]]+${NIKKI_FEED_NAME}[[:space:]]" feeds.conf; then
  log "adding nikki feed: ${NIKKI_FEED_URL};${NIKKI_FEED_BRANCH}"
  printf '\n%s\n' "${feed_line}" >> feeds.conf
else
  log "nikki feed already present in feeds.conf"
fi

log "updating feeds"
./scripts/feeds update -a

log "installing feeds"
./scripts/feeds install -a

popd >/dev/null

select_nikki_mihomo_provider

profile="$(detect_device_profile)"
log "detected device profile: ${profile}"

missing=()
for package_name in luci-app-nikki luci-theme-argon luci-app-turboacc-mtk luci-app-ttyd luci-app-upnp; do
  if [[ -z "$(find_package_makefile "${package_name}")" ]]; then
    missing+=("${package_name}")
  fi
done

if (( ${#missing[@]} > 0 )); then
  printf '[tr3000] Missing package directories after feeds install:\n' >&2
  printf '  %s\n' "${missing[@]}" >&2
  die "check feeds.conf, nikki feed URL, or package names"
fi

log "init complete"
