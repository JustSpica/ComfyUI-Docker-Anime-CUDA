#!/usr/bin/env bash
set -euo pipefail

# Shared URL/text utilities.
source "$(cd "$(dirname "$0")" && pwd)/init_scripts/url_utils.sh"

# Optional first arg overrides default models.conf path.
CONF_FILE="${1:-models.conf}"

readonly URL_CHECK_CONNECT_TIMEOUT=15
readonly URL_CHECK_MAX_TIME=30
readonly URL_CHECK_MAX_FILESIZE=1048576

# 2xx and 3xx are considered reachable. 3xx is accepted because Civitai
# URLs are probed without --location, so a redirect is a valid response.
http_success() {
  local http_code="$1"
  [[ "${http_code}" =~ ^[23][0-9][0-9]$ ]]
}

load_civitai_api_key_from_env_file() {
  local env_file="${1:-.env}"
  local raw_line=""
  local line=""
  local value=""

  [ -n "${CIVITAI_API_KEY+x}" ] && return 0
  [ -f "${env_file}" ] || return 0

  while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
    line="$(strip_comment_and_trim "${raw_line}")"
    [[ "${line}" == CIVITAI_API_KEY=* ]] || continue
    value="${line#CIVITAI_API_KEY=}"

    if [[ "${value}" =~ ^\"(.*)\"$ ]]; then
      value="${BASH_REMATCH[1]}"
    elif [[ "${value}" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi

    export CIVITAI_API_KEY="${value}"
    return 0
  done < "${env_file}"
}

civitai_auth_failure_message() {
  local http_code="$1"

  if [ -z "$(get_civitai_api_key)" ]; then
    printf 'HTTP %s; Civitai requires login/token. Set CIVITAI_API_KEY for restricted assets' "${http_code}"
  else
    printf 'HTTP %s; Civitai denied access with a Civitai API key. Check account access for this asset' "${http_code}"
  fi
}

load_civitai_api_key_from_env_file ".env"

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

    if is_http_url "${left}"; then
      printf '%s\n' "${left}"
      return
    fi

    if is_http_url "${right}"; then
      printf '%s\n' "${right}"
      return
    fi
  fi

  # URL only
  if is_http_url "${entry}"; then
    printf '%s\n' "${entry}"
    return
  fi

  # relative/path:URL (CUSTOM/GIT_REPOS style)
  if [[ "${entry}" == *":"* ]]; then
    right="$(trim "${entry#*:}")"
    if is_http_url "${right}"; then
      printf '%s\n' "${right}"
    fi
  fi
}

# Runs a single curl probe and prints "http_code curl_exit_status".
probe_url() {
  local request_url="$1"
  shift
  local curl_status=0
  local http_code=""

  http_code="$(curl --silent "$@" \
    --connect-timeout "${URL_CHECK_CONNECT_TIMEOUT}" \
    --max-time "${URL_CHECK_MAX_TIME}" \
    --output /dev/null \
    --write-out '%{http_code}' \
    "${request_url}")" || curl_status=$?

  printf '%s %s' "${http_code}" "${curl_status}"
}

# Evaluate a probe result: print 'ok' on success, auth message on Civitai 401/403.
# Returns 0 (success), 1 (permanent auth failure), 2 (try next probe).
evaluate_probe() {
  local url="$1"
  local http_code="$2"

  if http_success "${http_code}"; then
    printf 'ok'
    return 0
  fi

  if is_civitai_url "${url}" && http_auth_failure "${http_code}"; then
    civitai_auth_failure_message "${http_code}"
    return 1
  fi

  return 2
}

check_url() {
  local url="$1"
  local request_url="${url}"
  local curl_location_args=(--location)
  local probe_result="" http_code="" curl_status=""

  if is_civitai_url "${url}"; then
    local api_key=""
    api_key="$(get_civitai_api_key)"
    [ -n "${api_key}" ] && request_url="$(civitai_authenticated_url "${url}")"
    curl_location_args=()
  fi

  # Try HEAD first.
  probe_result="$(probe_url "${request_url}" "${curl_location_args[@]}" --head)"
  http_code="${probe_result%% *}"
  curl_status="${probe_result##* }"
  evaluate_probe "${url}" "${http_code}" && return 0
  [ $? -eq 1 ] && return 1

  # Some hosts reject HEAD but accept GET. Request only one byte and cap payload.
  probe_result="$(probe_url "${request_url}" "${curl_location_args[@]}" \
    --request GET --range 0-0 --max-filesize "${URL_CHECK_MAX_FILESIZE}")"
  http_code="${probe_result%% *}"
  curl_status="${probe_result##* }"
  evaluate_probe "${url}" "${http_code}" && return 0
  [ $? -eq 1 ] && return 1

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
  display_url="$(redact_url_token "${url}")"

  if result="$(check_url "${url}")"; then
    printf '[OK]    %s\n' "${display_url}"
    ok_count=$((ok_count + 1))
  else
    printf '[FAIL]  %s (%s)\n' "${display_url}" "${result}"
    failed_count=$((failed_count + 1))
  fi
done < "${CONF_FILE}"

printf '\nChecked URLs: %d ok, %d failed\n' "${ok_count}" "${failed_count}"

if [ "${failed_count}" -gt 0 ]; then
  exit 1
fi
