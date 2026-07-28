#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

ensure_filogic_image_file

mapfile -t devices < <("${SCRIPT_DIR}/list-devices.sh" --raw)
(( ${#devices[@]} > 0 )) || die "no Filogic devices found in $(filogic_image_file)"

filter=""
max_rows=80
page=0

device_display() {
  local row="$1"
  local profile vendor model variant display
  IFS=$'\t' read -r profile vendor model variant <<< "${row}"
  display="${vendor} ${model} ${variant}"
  display="${display#"${display%%[![:space:]]*}"}"
  display="${display%"${display##*[![:space:]]}"}"
  [[ -n "${display}" ]] || display="${profile}"
  printf '%s\t%s' "${profile}" "${display}"
}

while true; do
  printf '\nDevice profiles from upstream Filogic definitions\n'
  if [[ -n "${DEVICE_PROFILE}" ]]; then
    printf 'Current: %s\n' "${DEVICE_PROFILE}"
  else
    printf 'Current: not selected\n'
  fi
  if [[ -n "${filter}" ]]; then
    printf 'Filter: %s\n' "${filter}"
  fi
  printf '\n'

  visible=()
  filter_lower="${filter,,}"
  for row in "${devices[@]}"; do
    IFS=$'\t' read -r profile vendor model variant <<< "${row}"
    haystack="${profile} ${vendor} ${model} ${variant}"
    haystack="${haystack,,}"
    if [[ -z "${filter_lower}" || "${haystack}" == *"${filter_lower}"* ]]; then
      visible+=("${row}")
    fi
  done

  page_count=0
  page_start=0
  page_end=0
  if (( ${#visible[@]} == 0 )); then
    printf 'No matches. Use /keyword to search again, a to show all, q to return.\n'
  else
    page_count=$(( (${#visible[@]} + max_rows - 1) / max_rows ))
    (( page >= page_count )) && page=$((page_count - 1))
    page_start=$((page * max_rows))
    page_end=$((page_start + max_rows))
    (( page_end > ${#visible[@]} )) && page_end="${#visible[@]}"

    printf 'Page %d/%d (showing %d-%d of %d matches)\n\n' "$((page + 1))" "$page_count" "$((page_start + 1))" "$page_end" "${#visible[@]}"
    for ((i = page_start; i < page_end; i++)); do
      IFS=$'\t' read -r profile display <<< "$(device_display "${visible[i]}")"
      printf '%4d. %-38s %s\n' "$((i - page_start + 1))" "${profile}" "${display}"
    done
  fi

  printf '\n'
  read -r -p 'Number to select, n next, p previous, /keyword to search, a all, q return: ' input

  case "${input}" in
    q|Q)
      exit 0
      ;;
    a|A|"")
      filter=""
      page=0
      continue
      ;;
    /*)
      filter="${input#/}"
      page=0
      continue
      ;;
    n|N)
      if (( ${#visible[@]} == 0 || page + 1 >= page_count )); then
        printf 'Already on the last page.\n' >&2
      else
        page=$((page + 1))
      fi
      continue
      ;;
    p|P)
      if (( page <= 0 )); then
        printf 'Already on the first page.\n' >&2
      else
        page=$((page - 1))
      fi
      continue
      ;;
  esac

  if [[ ! "${input}" =~ ^[0-9]+$ ]]; then
    printf 'Invalid input: %s\n' "${input}" >&2
    continue
  fi

  index=$((input - 1))
  page_size=$((page_end - page_start))
  if (( index < 0 || index >= page_size )); then
    printf 'Selection out of range: %s\n' "${input}" >&2
    continue
  fi

  IFS=$'\t' read -r profile _vendor _model _variant <<< "${visible[page_start + index]}"
  verify_profile_exists "${profile}" || die "selected profile is not buildable: ${profile}"
  update_env_var DEVICE_PROFILE "${profile}"
  printf 'Selected device profile: %s\n' "${profile}"
  exit 0
done
