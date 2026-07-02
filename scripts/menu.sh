#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

run_target() {
  make --no-print-directory "$@"
}

reload_state() {
  load_env
  DEVICE_PROFILE="${DEVICE_PROFILE:-}"
}

source_ready() {
  [[ -f "$(filogic_image_file)" ]]
}

ensure_ready_for_menu() {
  if source_ready; then
    return 0
  fi

  printf 'Preparing upstream source and feeds for the first run...\n'
  run_target init
}

custom_package_count() {
  [[ -f "${CUSTOM_SEED}" ]] || {
    printf '0'
    return
  }
  grep -Ec '^CONFIG_PACKAGE_[^=]+=y$' "${CUSTOM_SEED}" || true
}

show_status() {
  reload_state
  printf '\nCurrent configuration\n'
  printf 'Device profile: %s\n' "${DEVICE_PROFILE:-not selected}"
  printf 'Optional packages: %s\n' "$(custom_package_count)"
  printf 'Source directory: %s\n' "${SOURCE_DIR}"
  printf 'Output directory: %s\n' "${OUTPUT_DIR}"
  if [[ -d "${SOURCE_DIR}/.git" ]]; then
    printf 'Source commit: '
    git -C "${SOURCE_DIR}" rev-parse --short HEAD 2>/dev/null || printf 'unknown\n'
  fi
}

build_selected_device() {
  reload_state
  if [[ -z "${DEVICE_PROFILE}" ]]; then
    printf 'No device selected. Opening device selection first.\n'
    "${SCRIPT_DIR}/select-device.sh"
    reload_state
  fi

  [[ -n "${DEVICE_PROFILE}" ]] || {
    printf 'Build cancelled: no device selected.\n'
    return 0
  }

  run_target build
}

ensure_ready_for_menu

while true; do
  reload_state
  printf '\nImmortalWrt Builder\n'
  printf 'Device: %s | Optional packages: %s\n' "${DEVICE_PROFILE:-not selected}" "$(custom_package_count)"
  printf '\n'
  printf '1. Select device profile\n'
  printf '2. Select optional packages\n'
  printf '3. Build firmware\n'
  printf '4. Show current configuration\n'
  printf '5. Update upstream source and feeds\n'
  printf '6. Clean build cache\n'
  printf '7. Open builder shell\n'
  printf '0. Exit\n'
  printf '\n'

  read -r -p 'Choose: ' choice
  case "${choice}" in
    1)
      "${SCRIPT_DIR}/select-device.sh"
      ;;
    2)
      "${SCRIPT_DIR}/select-packages.sh"
      ;;
    3)
      build_selected_device
      ;;
    4)
      show_status
      ;;
    5)
      run_target init
      ;;
    6)
      run_target clean
      ;;
    7)
      run_target shell
      ;;
    0|q|Q)
      exit 0
      ;;
    *)
      printf 'Unknown choice: %s\n' "${choice}" >&2
      ;;
  esac
done
