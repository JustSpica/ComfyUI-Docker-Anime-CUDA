#!/usr/bin/env bash
set -euo pipefail

source /usr/local/bin/config.sh

# Default to project config; still accepts an optional custom path argument.
CONF_FILE="${1:-${MODELS_CONF}}"

if [ ! -f "${CONF_FILE}" ]; then
  log "INFO" "Models config not found: ${CONF_FILE}"
  exit 0
fi

MODEL_SECTIONS=(
  CHECKPOINTS
  DIFFUSION_MODELS
  UNET
  CLIP
  CLIP_VISION
  TEXT_ENCODERS
  LORAS
  VAE
  UPSCALE_MODELS
  CONTROLNET
  EMBEDDINGS
)

# Convert section names like CHECKPOINTS -> checkpoints (ComfyUI folder layout).
section_to_dir() {
  local section="$1"
  printf '%s' "${section}" | tr '[:upper:]' '[:lower:]'
}

# Ensure standard model directories exist even before first download.
for section in "${MODEL_SECTIONS[@]}"; do
  mkdir -p "${MODELS_DIR}/$(section_to_dir "${section}")"
done

download_entry() {
  local section_dir="$1"
  local entry="$2"
  local left=""
  local right=""
  local url=""
  local target_path=""

  # Supported entries:
  # 1) URL|custom_filename
  # 2) relative/path|URL (legacy)
  # 3) URL
  if [[ "${entry}" == *"|"* ]]; then
    left="$(trim "${entry%%|*}")"
    right="$(trim "${entry#*|}")"

    # Supported form A: URL|custom_filename
    if [[ "${left}" =~ ^https?:// ]]; then
      url="${left}"
      right="${right#/}"
      target_path="${MODELS_DIR}/${section_dir}/${right}"

    # Supported form B: relative/path|URL (legacy compatibility)
    elif [[ "${right}" =~ ^https?:// ]]; then
      url="${right}"
      left="${left#/}"
      target_path="${MODELS_DIR}/${left}"
    fi
  elif [[ "${entry}" =~ ^https?:// ]]; then
    # Supported form C: URL only, keeps original file name.
    url="${entry}"
    target_path="${MODELS_DIR}/${section_dir}/$(basename "${url%%\?*}")"
  fi

  if [ -z "${url}" ] || [ -z "${target_path}" ]; then
    log "WARN" "Skipping malformed model entry: ${entry}"
    return 0
  fi

  download_if_missing "${url}" "${target_path}" || \
    log "WARN" "Failed model download: ${url}"
}

download_custom_entry() {
  local entry="$1"
  local relative_path="$(trim "${entry%%:*}")"
  local url="$(trim "${entry#*:}")"
  local target_file=""

  # CUSTOM format: relative/path:https://url/file.bin
  if [ -z "${relative_path}" ] || [ -z "${url}" ] || [ "${relative_path}" = "${url}" ]; then
    log "WARN" "Skipping malformed CUSTOM entry: ${entry}"
    return 0
  fi

  relative_path="${relative_path#/}"
  target_file="${MODELS_DIR}/${relative_path}/$(basename "${url%%\?*}")"

  download_if_missing "${url}" "${target_file}" || \
    log "WARN" "Failed custom download: ${url}"
}

clone_git_repo_entry() {
  local entry="$1"
  local relative_path="$(trim "${entry%%:*}")"
  local repo_url="$(trim "${entry#*:}")"
  local base_dir=""
  local target_dir=""

  # GIT_REPOS format: relative/path:https://huggingface.co/org/repo
  if [ -z "${relative_path}" ] || [ -z "${repo_url}" ] || [ "${relative_path}" = "${repo_url}" ]; then
    log "WARN" "Skipping malformed GIT_REPOS entry: ${entry}"
    return 0
  fi

  if [ "${relative_path}" = "." ]; then
    base_dir="${MODELS_DIR}"
  else
    base_dir="${MODELS_DIR}/${relative_path#/}"
  fi

  target_dir="${base_dir}/$(basename "${repo_url}" .git)"
  mkdir -p "${base_dir}"

  git_clone_or_update "${target_dir}" "${repo_url}" || \
    log "WARN" "Failed model git repo: ${repo_url}"
}

for section in "${MODEL_SECTIONS[@]}"; do
  section_dir="$(section_to_dir "${section}")"

  mapfile -t entries < <(read_config_lines "${CONF_FILE}" "${section}")
  [ "${#entries[@]}" -eq 0 ] && continue

  log "INFO" "Processing section ${section} (${#entries[@]} entries)"

  for entry in "${entries[@]}"; do
    download_entry "${section_dir}" "${entry}"
  done
done

# CUSTOM allows placing files outside the default section folders.
mapfile -t custom_entries < <(read_config_lines "${CONF_FILE}" "CUSTOM")
if [ "${#custom_entries[@]}" -gt 0 ]; then
  log "INFO" "Processing CUSTOM entries (${#custom_entries[@]} entries)"
  for entry in "${custom_entries[@]}"; do
    download_custom_entry "${entry}"
  done
fi

# GIT_REPOS supports model repos that should be cloned/updated.
mapfile -t git_repo_entries < <(read_config_lines "${CONF_FILE}" "GIT_REPOS")
if [ "${#git_repo_entries[@]}" -gt 0 ]; then
  log "INFO" "Processing GIT_REPOS entries (${#git_repo_entries[@]} entries)"
  for entry in "${git_repo_entries[@]}"; do
    clone_git_repo_entry "${entry}"
  done
fi

log "INFO" "Model bootstrap completed"
