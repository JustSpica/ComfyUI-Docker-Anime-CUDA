# ComfyUI Docker with CUDA support - Optimized for faster builds
FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04 AS base

LABEL maintainer="ComfyUI Docker Maintainer"
LABEL description="ComfyUI tuned for anime-art and simple animation workflows"

# Runtime defaults for stable logs and lower VRAM pressure on 8GB GPUs.
ENV DEBIAN_FRONTEND=noninteractive \
    HF_HUB_ENABLE_HF_TRANSFER=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
    COMFYUI_DIR=/app/ComfyUI \
    PATH="/venv/bin:$PATH" \
    VENV_DIR=/venv

# OS packages used by ComfyUI and common image nodes.
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build and version tools
    ca-certificates \
    git \
    git-lfs \
    # Python
    python3 \
    python3-dev \
    python3-venv \
    # Libs for GUI and media
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    # Fonts
    fontconfig \
    # Utils
    curl \
    wget && \
    fc-cache -f -v && \
    git lfs install --system && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Non-root runtime user and shared working folders.
RUN mkdir -p /app /app/config "${COMFYUI_DIR}" "${VENV_DIR}" && \
    chown -R 1000:1000 /app "${COMFYUI_DIR}" "${VENV_DIR}"

USER 1000

# Isolated Python environment.
RUN python3 -m venv "${VENV_DIR}"

# Install GPU stack early.
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir \
    torch==2.10.0+cu128 \
    torchvision==0.25.0+cu128 \
    torchaudio==2.10.0+cu128 \
    --index-url https://download.pytorch.org/whl/cu128 && \
    pip install --no-cache-dir -U \
    xformers==0.0.35 \
    --index-url https://download.pytorch.org/whl/cu128

# Clone ComfyUI and pin to latest stable tag by default.
WORKDIR /app
ARG COMFYUI_REF=latest-tag
RUN git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}" && \
    cd "${COMFYUI_DIR}" && \
    if [ "${COMFYUI_REF}" = "latest-tag" ]; then \
      git fetch --tags && \
      git checkout "$(git describe --tags "$(git rev-list --tags --max-count=1)")"; \
    else \
      git checkout "${COMFYUI_REF}"; \
    fi

WORKDIR ${COMFYUI_DIR}

# Create persisted folders expected by ComfyUI.
RUN mkdir -p "${COMFYUI_DIR}/models" \
    "${COMFYUI_DIR}/input" \
    "${COMFYUI_DIR}/output" \
    "${COMFYUI_DIR}/custom_nodes/.last_commits" && \
    touch "${COMFYUI_DIR}/custom_nodes/.last_commits/__init__.py"

# Install core deps plus requirements.
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir \
    huggingface_hub \
    hf-transfer \
    imageio \
    imageio-ffmpeg \
    onnxruntime-gpu \
    opencv-python-headless \
    pillow \
    scikit-image

# Separate stage: script/config changes do not invalidate heavy build layers.
FROM base

USER root

# Bootstrap scripts and default config files.
COPY --chown=1000:1000 init_scripts/config.sh /usr/local/bin/config.sh
COPY --chown=1000:1000 init_scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=1000:1000 init_scripts/init_extensions.sh /usr/local/bin/init_extensions.sh
COPY --chown=1000:1000 init_scripts/init_models.sh /usr/local/bin/init_models.sh
COPY --chown=1000:1000 extensions.conf /app/config/extensions.conf
COPY --chown=1000:1000 models.conf /app/config/models.conf

# Normalize line endings from Windows hosts and mark scripts executable.
RUN sed -i 's/\r$//' /usr/local/bin/config.sh && \
    sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && \
    sed -i 's/\r$//' /usr/local/bin/init_extensions.sh && \
    sed -i 's/\r$//' /usr/local/bin/init_models.sh && \
    chmod +x /usr/local/bin/config.sh \
    /usr/local/bin/entrypoint.sh \
    /usr/local/bin/init_extensions.sh \
    /usr/local/bin/init_models.sh

USER 1000
WORKDIR ${COMFYUI_DIR}

# Persist data and extension-installed Python packages.
VOLUME ["/app/ComfyUI/models", "/app/ComfyUI/input", "/app/ComfyUI/output", "/app/ComfyUI/custom_nodes", "/venv"]

EXPOSE 8188

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["python3", "main.py"]
