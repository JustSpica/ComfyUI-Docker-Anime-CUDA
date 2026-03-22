#!/usr/bin/env bash
set -euo pipefail

# Optional first arg overrides default models.conf path.
CONF_FILE="${1:-models.conf}"

# Keep parser behavior aligned with init scripts.
trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

strip_comment_and_trim() {
  local line="$1"
  line="${line%%#*}"
  line="${line%%;*}"
  trim "${line}"
}

if [ ! -f "${CONF_FILE}" ]; then
  printf 'Config file not found: %s\n' "${CONF_FILE}" >&2
  exit 1
fi

extract_url() {
  local entry="$1"
  local left=""
  local right=""

  # URL|filename or relative/path|URL
  if [[ "${entry}" == *"|"* ]]; then
    left="$(trim "${entry%%|*}")"
    right="$(trim "${entry#*|}")"

    if [[ "${left}" =~ ^https?:// ]]; then
      printf '%s\n' "${left}"
      return
    fi

    if [[ "${right}" =~ ^https?:// ]]; then
      printf '%s\n' "${right}"
      return
    fi
  fi

  # URL only
  if [[ "${entry}" =~ ^https?:// ]]; then
    printf '%s\n' "${entry}"
    return
  fi

  # relative/path:URL (CUSTOM/GIT_REPOS style)
  if [[ "${entry}" == *":"* ]]; then
    right="$(trim "${entry#*:}")"
    if [[ "${right}" =~ ^https?:// ]]; then
      printf '%s\n' "${right}"
    fi
  fi
}

ok_count=0
failed_count=0

while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
  # Ignore empty lines and section headers.
  line="$(strip_comment_and_trim "${raw_line}")"

  [ -z "${line}" ] && continue
  [[ "${line}" =~ ^\[.*\]$ ]] && continue

  url="$(extract_url "${line}" || true)"
  [ -z "${url}" ] && continue

  if curl -fsIL --connect-timeout 15 --max-time 30 "${url}" >/dev/null; then
    printf '[OK]    %s\n' "${url}"
    ok_count=$((ok_count + 1))
  else
    printf '[FAIL]  %s\n' "${url}"
    failed_count=$((failed_count + 1))
  fi
done < "${CONF_FILE}"

printf '\nChecked URLs: %d ok, %d failed\n' "${ok_count}" "${failed_count}"

if [ "${failed_count}" -gt 0 ]; then
  exit 1
fi
