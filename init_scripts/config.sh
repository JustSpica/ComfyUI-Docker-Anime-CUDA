#!/usr/bin/env bash
set -euo pipefail

# Shared URL/text utilities (no side effects, safe to source before env checks).
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/url_utils.sh" 2>/dev/null \
  || source /usr/local/bin/url_utils.sh

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

readonly DOWNLOAD_CONNECT_TIMEOUT=20
readonly DOWNLOAD_MAX_TIME=900
readonly DOWNLOAD_MAX_RETRIES=3

log_civitai_auth_error() {
  local http_code="$1"
  if [ -z "$(get_civitai_api_key)" ]; then
    log "ERROR" "Civitai denied download (HTTP ${http_code}). Set CIVITAI_API_KEY for restricted assets."
  else
    log "ERROR" "Civitai denied download (HTTP ${http_code}). Check whether your API key has access to this asset."
  fi
}

# Returns 0 on success, 1 on permanent failure (no retry), 2 on transient failure.
download_file_once() {
  local download_url="$1"
  local tmp_path="$2"
  local original_url="$3"
  local curl_status=0
  local http_code=""

  http_code="$(curl -sS -fL --retry 3 \
    --connect-timeout "${DOWNLOAD_CONNECT_TIMEOUT}" --max-time "${DOWNLOAD_MAX_TIME}" \
    --write-out '%{http_code}' \
    -o "${tmp_path}" \
    "${download_url}")" || curl_status=$?

  if [ "${curl_status}" -eq 0 ]; then
    return 0
  fi

  rm -f "${tmp_path}"

  if is_civitai_url "${original_url}" && http_auth_failure "${http_code}"; then
    log_civitai_auth_error "${http_code}"
    return 1
  fi

  return 2
}

# Download only when missing; temporary file avoids partial/corrupted output.
download_if_missing() {
  local url="$1"
  local target_path="$2"
  local retries="${DOWNLOAD_MAX_RETRIES}"
  local attempt=1
  local tmp_path="${target_path}.tmp"
  local download_url="${url}"
  local redacted_url=""

  mkdir -p "$(dirname "${target_path}")"

  if [ -s "${target_path}" ]; then
    log "INFO" "Skipping existing file: ${target_path}"
    return 0
  fi

  if is_civitai_url "${url}"; then
    download_url="$(civitai_authenticated_url "${url}")"
  fi

  redacted_url="$(redact_url_token "${url}")"

  while [ "${attempt}" -le "${retries}" ]; do
    log "INFO" "Downloading (${attempt}/${retries}): ${redacted_url}"

    download_file_once "${download_url}" "${tmp_path}" "${url}"
    local result=$?

    if [ "${result}" -eq 0 ]; then
      mv "${tmp_path}" "${target_path}"
      log "INFO" "Saved: ${target_path}"
      return 0
    fi

    [ "${result}" -eq 1 ] && return 1

    log "WARN" "Download failed (attempt ${attempt}): ${redacted_url}"
    attempt=$((attempt + 1))
    sleep $((2 ** (attempt - 1)))
  done

  log "ERROR" "Giving up download: ${redacted_url}"
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
