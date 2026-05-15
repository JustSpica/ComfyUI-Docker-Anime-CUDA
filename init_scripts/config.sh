#!/usr/bin/env bash
set -euo pipefail

# COMFYUI_DIR is provided by Dockerfile ENV and used as root for runtime data.
: "${COMFYUI_DIR:?COMFYUI_DIR environment variable is required}"

# Shared constants used by all bootstrap scripts.
MODELS_DIR="${COMFYUI_DIR}/models"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
LAST_COMMITS_DIR="${CUSTOM_NODES_DIR}/.last_commits"

# Project config file locations.
EXTENSIONS_CONF="/app/config/extensions.conf"
MODELS_CONF="/app/config/models.conf"

# Create expected directory tree early so downstream scripts can assume it exists.
mkdir -p "${MODELS_DIR}" "${CUSTOM_NODES_DIR}" "${LAST_COMMITS_DIR}"
# Keep .last_commits importable if ComfyUI scans custom_nodes as packages.
touch "${LAST_COMMITS_DIR}/__init__.py"

# Consistent timestamped logger for all scripts.
log() {
  local level="$1"
  local message="$2"
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${level}" "${message}"
}

# Normalize values read from config files.
trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

# Remove inline comments (# or ;) and trim whitespace.
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

resolve_civitai_download_url() {
  local url="$1"
  local curl_auth_args=()
  local curl_status=0
  local response=""
  local redirect_url=""
  local auth_url=""
  local api_key=""

  CIVITAI_RESOLVED_URL="${url}"
  CIVITAI_RESOLVE_HTTP_CODE=""

  api_key="$(get_civitai_api_key)"
  auth_url="$(civitai_authenticated_url "${url}")"
  CIVITAI_RESOLVED_URL="${auth_url}"

  if [ -n "${api_key}" ]; then
    curl_auth_args=(-H "Authorization: Bearer ${api_key}")
  fi

  response="$(curl -sS --head \
    --connect-timeout 20 \
    --max-time 60 \
    "${curl_auth_args[@]}" \
    --output /dev/null \
    --write-out '%{http_code}\n%{redirect_url}' \
    "${auth_url}")" || curl_status=$?

  CIVITAI_RESOLVE_HTTP_CODE="${response%%$'\n'*}"
  if [[ "${response}" == *$'\n'* ]]; then
    redirect_url="${response#*$'\n'}"
  fi

  if [ "${curl_status}" -ne 0 ]; then
    return "${curl_status}"
  fi

  if ! http_success "${CIVITAI_RESOLVE_HTTP_CODE}"; then
    return 22
  fi

  if [ -n "${redirect_url}" ]; then
    CIVITAI_RESOLVED_URL="${redirect_url}"
  fi
}

# Read INI-like entries from a section, or plain entries if no section is provided.
read_config_lines() {
  local config_file="$1"
  local section="${2:-}"
  local current_section=""
  local has_sections=0

  while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
    local line
    line="$(strip_comment_and_trim "${raw_line}")"
    [ -z "${line}" ] && continue

    if [[ "${line}" =~ ^\[(.+)\]$ ]]; then
      has_sections=1
      current_section="${BASH_REMATCH[1]}"
      continue
    fi

    if [ -n "${section}" ]; then
      [ "${current_section}" = "${section}" ] && printf '%s\n' "${line}"
    elif [ "${has_sections}" -eq 0 ]; then
      printf '%s\n' "${line}"
    fi
  done < "${config_file}"
}

# Prefer a section (e.g. [EXTENSIONS]), then fallback to plain list format.
read_config_section_or_plain() {
  local config_file="$1"
  local section="$2"
  local entries=()

  mapfile -t entries < <(read_config_lines "${config_file}" "${section}")
  if [ "${#entries[@]}" -eq 0 ]; then
    mapfile -t entries < <(read_config_lines "${config_file}")
  fi

  if [ "${#entries[@]}" -gt 0 ]; then
    printf '%s\n' "${entries[@]}"
  fi
}

# Download only when missing; temporary file avoids partial/corrupted output.
download_if_missing() {
  local url="$1"
  local target_path="$2"
  local retries=3
  local attempt=1
  local tmp_path="${target_path}.tmp"
  local curl_auth_args=()
  local effective_curl_auth_args=()
  local effective_url=""
  local curl_status=0
  local http_code=""

  mkdir -p "$(dirname "${target_path}")"

  if [ -s "${target_path}" ]; then
    log "INFO" "Skipping existing file: ${target_path}"
    return 0
  fi

  if is_civitai_url "${url}" && [ -n "$(get_civitai_api_key)" ]; then
    curl_auth_args=(-H "Authorization: Bearer $(get_civitai_api_key)")
  fi

  while [ "${attempt}" -le "${retries}" ]; do
    log "INFO" "Downloading (${attempt}/${retries}): ${url}"

    effective_url="${url}"
    effective_curl_auth_args=("${curl_auth_args[@]}")

    if is_civitai_url "${url}"; then
      curl_status=0
      resolve_civitai_download_url "${url}" || curl_status=$?
      http_code="${CIVITAI_RESOLVE_HTTP_CODE:-}"

      if [ "${curl_status}" -ne 0 ]; then
        if [ "${http_code}" = "401" ] || [ "${http_code}" = "403" ]; then
          if [ -z "$(get_civitai_api_key)" ]; then
            log "ERROR" "Civitai denied download (HTTP ${http_code}). Set CIVITAI_API_KEY for login-restricted assets."
          else
            log "ERROR" "Civitai denied download (HTTP ${http_code}) even with a Civitai API key. Check account access for this asset."
          fi
          return 1
        fi

        log "WARN" "Failed to resolve Civitai download URL (attempt ${attempt}, HTTP ${http_code:-000}): ${url}"
        attempt=$((attempt + 1))
        sleep 2
        continue
      fi

      effective_url="${CIVITAI_RESOLVED_URL}"
      effective_curl_auth_args=()
    fi

    curl_status=0
    http_code="$(curl -sS -fL --retry 3 --connect-timeout 20 --max-time 900 \
      "${effective_curl_auth_args[@]}" \
      --write-out '%{http_code}' \
      -o "${tmp_path}" \
      "${effective_url}")" || curl_status=$?

    if [ "${curl_status}" -eq 0 ]; then
      mv "${tmp_path}" "${target_path}"
      log "INFO" "Saved: ${target_path}"
      return 0
    fi

    rm -f "${tmp_path}"

    if is_civitai_url "${url}" && { [ "${http_code}" = "401" ] || [ "${http_code}" = "403" ]; }; then
      if [ -z "$(get_civitai_api_key)" ]; then
        log "ERROR" "Civitai denied download (HTTP ${http_code}). Set CIVITAI_API_KEY for login-restricted assets."
      else
        log "ERROR" "Civitai denied download (HTTP ${http_code}) even with a Civitai API key. Check account access for this asset."
      fi
      return 1
    fi

    log "WARN" "Download failed (attempt ${attempt}): ${url}"
    attempt=$((attempt + 1))
    sleep 2
  done

  log "ERROR" "Giving up download: ${url}"
  return 1
}

# Clone once, then fast-forward updates on subsequent runs.
git_clone_or_update() {
  local target_dir="$1"
  local repo_url="$2"

  if [ -d "${target_dir}/.git" ]; then
    log "INFO" "Updating repo: ${target_dir}"
    git -C "${target_dir}" pull --ff-only
  else
    log "INFO" "Cloning repo: ${repo_url}"
    git clone --recursive "${repo_url}" "${target_dir}"
  fi
}
