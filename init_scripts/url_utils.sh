#!/usr/bin/env bash
# Shared URL and text utilities sourced by both host-side scripts
# (check_models_url.sh) and container-side scripts (config.sh).
# This file MUST have zero side effects at source-time: no mkdir,
# no env assertions, no I/O beyond function definitions.

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

is_http_url() {
  local url="$1"
  [[ "${url}" =~ ^https?:// ]]
}

is_civitai_url() {
  local url="$1"
  [[ "${url}" =~ ^https?://([^/]+\.)?civitai\.(com|red)(/|$) ]]
}

http_auth_failure() {
  local http_code="$1"
  [ "${http_code}" = "401" ] || [ "${http_code}" = "403" ]
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

# Append Civitai API token to a URL when available and not already present.
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

redact_url_token() {
  local url="$1"
  local before_token=""
  local after_token=""

  if [[ "${url}" != *"token="* ]]; then
    printf '%s' "${url}"
    return 0
  fi

  before_token="${url%%token=*}"
  after_token="${url#*token=}"

  if [[ "${after_token}" == *"&"* ]]; then
    printf '%stoken=REDACTED&%s' "${before_token}" "${after_token#*&}"
  else
    printf '%stoken=REDACTED' "${before_token}"
  fi
}
