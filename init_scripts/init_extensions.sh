#!/usr/bin/env bash
set -euo pipefail

source /usr/local/bin/config.sh

# Default to project config; still accepts an optional custom path argument.
CONF_FILE="${1:-${EXTENSIONS_CONF}}"

if [ ! -f "${CONF_FILE}" ]; then
  log "INFO" "Extensions config not found: ${CONF_FILE}"
  exit 0
fi

# Supports both [EXTENSIONS] INI format and plain URL list.
mapfile -t extensions < <(read_config_section_or_plain "${CONF_FILE}" "EXTENSIONS")

if [ "${#extensions[@]}" -eq 0 ]; then
  log "INFO" "No extensions configured"
  exit 0
fi

install_extension_deps() {
  local extension_dir="$1"
  local install_status=0

  # Install pip requirements when provided by the extension.
  if [ -f "${extension_dir}/requirements.txt" ]; then
    log "INFO" "Installing requirements for $(basename "${extension_dir}")"
    if ! python3 -m pip install --no-cache-dir -r "${extension_dir}/requirements.txt"; then
      log "WARN" "Failed requirements install in ${extension_dir}"
      install_status=1
    fi
  fi

  # Some extensions ship custom install scripts for post-clone setup.
  if [ -f "${extension_dir}/install.py" ]; then
    log "INFO" "Running install.py for $(basename "${extension_dir}")"
    if ! python3 "${extension_dir}/install.py"; then
      log "WARN" "install.py failed in ${extension_dir}"
      install_status=1
    fi
  fi

  return "${install_status}"
}

log "INFO" "Processing ${#extensions[@]} extensions"

for repo in "${extensions[@]}"; do
  repo="$(trim "${repo}")"

  [ -z "${repo}" ] && continue

  # Use repository basename as local folder key and commit marker name.
  name="$(basename "${repo}" .git)"
  target_dir="${CUSTOM_NODES_DIR}/${name}"
  last_commit_file="${LAST_COMMITS_DIR}/${name}.commit"

  if ! git_clone_or_update "${target_dir}" "${repo}"; then
    log "WARN" "Skipping extension after git error: ${repo}"
    continue
  fi

  new_commit="$(git -C "${target_dir}" rev-parse HEAD 2>/dev/null || true)"
  old_commit=""
  [ -f "${last_commit_file}" ] && old_commit="$(<"${last_commit_file}")"

  # Reinstall dependencies only when repo commit changed.
  if [ -n "${new_commit}" ] && [ "${new_commit}" != "${old_commit}" ]; then
    if install_extension_deps "${target_dir}"; then
      printf '%s\n' "${new_commit}" > "${last_commit_file}"
    else
      log "WARN" "Extension setup failed for ${name}; will retry next start"
    fi
  else
    log "INFO" "No extension changes for ${name}"
  fi
done
