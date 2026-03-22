#!/usr/bin/env bash
set -euo pipefail

# Load shared paths/helpers (log, trim, config file locations).
source /usr/local/bin/config.sh

# Bootstrap step: install/update custom nodes from extensions.conf.
if [ -f "${EXTENSIONS_CONF}" ]; then
  log "INFO" "Running extensions from ${EXTENSIONS_CONF}"
  /usr/local/bin/init_extensions.sh
else
  log "INFO" "No extensions config found at ${EXTENSIONS_CONF}"
fi

# Bootstrap step: download missing models from models.conf.
if [ -f "${MODELS_CONF}" ]; then
  log "INFO" "Running models from ${MODELS_CONF}"
  /usr/local/bin/init_models.sh
else
  log "INFO" "No models config found at ${MODELS_CONF}"
fi

cd "${COMFYUI_DIR}"

# Append CLI_ARGS only when running default command.
# This keeps custom overrides (e.g. bash) untouched.
if [ "${1:-}" = "python3" ] && [ "${2:-}" = "main.py" ] && [ -n "${CLI_ARGS:-}" ]; then
  read -r -a cli_extra <<< "${CLI_ARGS}"
  set -- "$@" "${cli_extra[@]}"
fi

log "INFO" "Starting command: $*"
exec "$@"
