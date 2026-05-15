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

is_civitai_url() {
  local url="$1"
  [[ "${url}" =~ ^https?://([^/]+\.)?civitai\.(com|red)(/|$) ]]
}

http_success() {
  local http_code="$1"
  [[ "${http_code}" =~ ^[23][0-9][0-9]$ ]]
}

load_env_file() {
  local env_file="${1:-.env}"
  local raw_line=""
  local line=""
  local key=""
  local value=""

  [ -f "${env_file}" ] || return 0

  while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
    line="$(strip_comment_and_trim "${raw_line}")"
    [ -z "${line}" ] && continue
    [[ "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue

    key="${line%%=*}"
    value="${line#*=}"

    if [[ "${value}" =~ ^\"(.*)\"$ ]]; then
      value="${BASH_REMATCH[1]}"
    elif [[ "${value}" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi

    if [ -z "${!key+x}" ]; then
      export "${key}=${value}"
    fi
  done < "${env_file}"
}

get_civitai_api_key() {
  if [ -n "${CIVITAI_API_KEY:-}" ]; then
    printf '%s' "${CIVITAI_API_KEY}"
  fi
}

urlencode() {
  local value="$1"
  local encoded=""
  local char=""
  local index=0

  for ((index = 0; index < ${#value}; index++)); do
    char="${value:index:1}"
    case "${char}" in
      [a-zA-Z0-9.~_-]) encoded+="${char}" ;;
      *) printf -v encoded '%s%%%02X' "${encoded}" "'${char}" ;;
    esac
  done

  printf '%s' "${encoded}"
}

append_query_param() {
  local url="$1"
  local key="$2"
  local value="$3"
  local separator="?"

  [[ "${url}" == *"?"* ]] && separator="&"

  printf '%s%s%s=%s' "${url}" "${separator}" "${key}" "$(urlencode "${value}")"
}

civitai_authenticated_url() {
  local url="$1"
  local api_key=""

  api_key="$(get_civitai_api_key)"

  if [ -z "${api_key}" ] || [[ "${url}" =~ (^|[?\&])token= ]]; then
    printf '%s' "${url}"
    return 0
  fi

  append_query_param "${url}" "token" "${api_key}"
}

civitai_auth_failure_message() {
  local http_code="$1"

  if [ -z "$(get_civitai_api_key)" ]; then
    printf 'HTTP %s; Civitai requires login/token. Set CIVITAI_API_KEY for restricted assets' "${http_code}"
  else
    printf 'HTTP %s; Civitai denied access with a Civitai API key. Check account access for this asset' "${http_code}"
  fi
}

load_env_file ".env"

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

check_url() {
  local url="$1"
  local request_url="${url}"
  local http_code=""
  local curl_status=0
  local curl_auth_args=()
  local curl_location_args=(--location)
  local api_key=""

  api_key="$(get_civitai_api_key)"

  if is_civitai_url "${url}" && [ -n "${api_key}" ]; then
    request_url="$(civitai_authenticated_url "${url}")"
    curl_auth_args=(-H "Authorization: Bearer ${api_key}")
  fi

  if is_civitai_url "${url}"; then
    curl_location_args=()
  fi

  http_code="$(curl --silent "${curl_location_args[@]}" --head \
    --connect-timeout 15 \
    --max-time 30 \
    "${curl_auth_args[@]}" \
    --output /dev/null \
    --write-out '%{http_code}' \
    "${request_url}")" || curl_status=$?

  if http_success "${http_code}"; then
    printf 'ok'
    return 0
  fi

  if is_civitai_url "${url}" && { [ "${http_code}" = "401" ] || [ "${http_code}" = "403" ]; }; then
    civitai_auth_failure_message "${http_code}"
    return 1
  fi

  # Some hosts reject HEAD but accept GET. Request only one byte and cap payload.
  curl_status=0
  http_code="$(curl --silent "${curl_location_args[@]}" --request GET \
    --range 0-0 \
    --connect-timeout 15 \
    --max-time 30 \
    --max-filesize 1048576 \
    "${curl_auth_args[@]}" \
    --output /dev/null \
    --write-out '%{http_code}' \
    "${request_url}")" || curl_status=$?

  if http_success "${http_code}"; then
    printf 'ok'
    return 0
  fi

  if is_civitai_url "${url}" && { [ "${http_code}" = "401" ] || [ "${http_code}" = "403" ]; }; then
    civitai_auth_failure_message "${http_code}"
    return 1
  fi

  if [ -n "${http_code}" ] && [ "${http_code}" != "000" ]; then
    printf 'HTTP %s' "${http_code}"
  else
    printf 'curl exit %s' "${curl_status}"
  fi

  return 1
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

  if result="$(check_url "${url}")"; then
    printf '[OK]    %s\n' "${url}"
    ok_count=$((ok_count + 1))
  else
    printf '[FAIL]  %s (%s)\n' "${url}" "${result}"
    failed_count=$((failed_count + 1))
  fi
done < "${CONF_FILE}"

printf '\nChecked URLs: %d ok, %d failed\n' "${ok_count}" "${failed_count}"

if [ "${failed_count}" -gt 0 ]; then
  exit 1
fi
