# ComfyUI Anime Docker (CUDA)

A reproducible, GPU-accelerated [ComfyUI](https://github.com/comfyanonymous/ComfyUI) environment packaged as a Docker image, tuned for anime-art workflows on consumer NVIDIA GPUs (8 GB VRAM and up). The image pins CUDA 12.8 with the matching PyTorch and xFormers builds, and the host-side configuration files declare which models and custom nodes are bootstrapped on first run.

## Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Project layout](#project-layout)
- [Configuration](#configuration)
  - [Models (`models.conf`)](#models-modelsconf)
  - [Extensions (`extensions.conf`)](#extensions-extensionsconf)
  - [Civitai API key](#civitai-api-key)
- [URL checker](#url-checker)
- [Operations](#operations)
- [Tips for 8 GB VRAM GPUs](#tips-for-8gb-vram-gpus)

## Features

- **Reproducible image.** CUDA 12.8 runtime with pinned versions: `torch==2.10.0+cu128`, `torchvision==0.25.0+cu128`, `torchaudio==2.10.0+cu128`, `xformers==0.0.35`.
- **Declarative model and extension bootstrap.** `models.conf` and `extensions.conf` drive the initial download and update of model files and custom nodes; only missing files are downloaded.
- **Host-side persistence.** Models, inputs, outputs, workflows, and custom nodes are bind-mounted to the host. The extension Python environment lives in a Docker volume that can be reset cleanly.
- **Authenticated Civitai downloads.** `CIVITAI_API_KEY` is forwarded to the bootstrap process for restricted assets.
- **URL health check.** A host-side script validates every URL in `models.conf` against the upstream provider before a build.
- **Non-root container.** Runs as UID/GID `1000`, exposing only port `8188`.

## Requirements

- Linux host with the NVIDIA driver installed.
- Docker Engine with the NVIDIA Container Toolkit (`gpus: all` support).
- A CUDA-capable NVIDIA GPU. Defaults are tuned for 8 GB VRAM cards (e.g. RTX 4060).
- At least ~20 GB of free disk space for the image, base models, and outputs.

## Quick start

```bash
git clone https://github.com/JustSpica/ComfyUI-Docker-Anime-CUDA.git
cd ComfyUI-Docker-Anime-CUDA

# First run, or after Dockerfile / init_scripts changes.
docker compose up -d --build

# Subsequent starts.
docker compose up -d

# Stop the container.
docker compose down
```

Open `http://localhost:8188` once the container reports ComfyUI is ready.

## Project layout

```text
.
├── Dockerfile                # CUDA 12.8 base + ComfyUI + Python stack
├── docker-compose.yml        # GPU, ports, volumes, environment
├── models.conf               # Declarative model download list
├── extensions.conf           # Declarative custom-node list
├── comfy.settings.json       # ComfyUI UI preferences
├── check_models_url.sh       # Host-side URL health checker
├── init_scripts/
│   ├── entrypoint.sh         # Container entrypoint orchestrator
│   ├── config.sh             # Shared paths, logger, download helpers
│   ├── url_utils.sh          # Shared URL/text utilities (host + container)
│   ├── init_models.sh        # Reads models.conf, downloads missing files
│   └── init_extensions.sh    # Reads extensions.conf, clones/updates nodes
├── workflows/                # Tracked workflow JSON files
├── models/                   # Runtime: downloaded model files
├── custom_nodes/             # Runtime: cloned extensions
├── input/                    # Runtime: ComfyUI input files
└── output/                   # Runtime: ComfyUI generation outputs
```

The `Dockerfile` builds the runtime image; `docker-compose.yml` declares GPU access, the `8188` port, environment variables, and the bind mounts. Bootstrap logic lives in `init_scripts/`: `entrypoint.sh` runs `init_extensions.sh` and `init_models.sh` before handing off to `python3 main.py`.

## Configuration

### Models (`models.conf`)

`models.conf` uses INI-like sections that map one-to-one to ComfyUI's `models/<folder>` layout (`[CHECKPOINTS]` → `models/checkpoints`, `[LORAS]` → `models/loras`, etc.). Each entry supports three formats:

```ini
[CHECKPOINTS]
# 1) URL with explicit output filename
https://example.com/path/file.safetensors|custom-name.safetensors

# 2) URL only — the filename is taken from the URL
https://example.com/path/file.safetensors

# 3) Path-prefixed URL (legacy) — placed at models/<path>
some/path|https://example.com/path/file.safetensors
```

The default selection reflects my personal preferences for anime art generation and is built almost entirely around the **Illustrious** model family (with a single Animagine XL 4.0 checkpoint kept for comparison). Most LoRAs are also Illustrious-compatible, since the workflow I run targets that lineage. Feel free to remove any entry that does not fit your taste — only missing files are downloaded, so the bootstrap is non-destructive.

**Checkpoints**

| File | Family | Notes |
|---|---|---|
| [`animagine-xl-4.0-opt.safetensors`](https://huggingface.co/cagliostrolab/animagine-xl-4.0) | SDXL | Cagliostro Lab's anime SDXL tuned for low VRAM. |
| [`waiIllustriousSDXL_v170.safetensors`](https://civitai.com/models/827184) | Illustrious | General-purpose Illustrious checkpoint with broad style coverage. |
| [`novaAnimeXL_ilV190.safetensors`](https://civitai.com/models/376130) | Illustrious | Higher contrast and richer background detail. |
| [`novaOrangeXL_rexV10.safetensors`](https://civitai.com/models/967405) | Illustrious | Focused on expressive posing and dramatic lighting. |
| [`rinFlanimeIllustrious_v30.safetensors`](https://civitai.com/models/1544647) | Illustrious | Flat-anime style with clean linework and saturated colors. |
| [`plantMilkModelSuite_walnut.safetensors`](https://civitai.com/models/1162518) | Illustrious | Anime art (Euler / low CFG / ~28 steps). |
| [`JANKUTrainedChenkinNoobai_v777.safetensors`](https://civitai.com/models/1277670) | Illustrious | Thicker linework and detailed backgrounds. |

**LoRAs** (Illustrious-compatible unless noted)

| File | Trigger | Notes |
|---|---|---|
| [`sdxl-extremely-detailed.safetensors`](https://huggingface.co/ntc-ai/SDXL-LoRA-slider.extremely-detailed) | `extremely detailed` |Detail booster (SDXL slider). |
| [`dmd2_sdxl_4step_lora_fp16.safetensors`](https://huggingface.co/tianweiy/DMD2) | — | SDXL acceleration for 4-step sampling. |
| [`AddMicroDetails_Illustrious_v6.safetensors`](https://civitai.com/models/1377820) | `addmicrodetails` | Surface-level detail enhancer. |
| [`748cmSDXL.safetensors`](https://civitai.com/models/943607) | `748cmstyle` | 748cm anime style. |
| [`pixel-Illustrius.safetensors`](https://civitai.com/models/43820) | `pixel` | Pixel-art style. |
| [`skormino-sprite-pixel-art.safetensors`](https://civitai.com/models/1631459) | `pixpix`, `8-bit`, `pixel_art` | 8-bit sprite pixel art. |
| [`Anime_artistic_2.safetensors`](https://civitai.com/models/1586542) | `Art8st`, `Anime2rt`, `Semi2realistic` | Versatile artistic/semi-realistic anime style. |
| [`MoriiMee_Gothic_Realistic.safetensors`](https://civitai.com/models/915918) | — | Gothic character art (pale tones, dark fashion). |
| [`iLLC0lorL1nes.safetensors`](https://civitai.com/models/599757) | `C0lorL1nes` | Vibrant colorful line effects. |
| [`Niji_Semi_realism_F_N_R_epoch_10.safetensors`](https://civitai.com/models/534506) | `SemiFrealism`, `SemiNrealism`, `SemiRrealism` | Semi-realistic anime style. |
| [`ck-shadow-circuit-IL.safetensors`](https://civitai.com/models/938811) | `in the style of cksc` | Neurocore shadow/lighting style. |
| [`Aura_Phantasy_illu.safetensors`](https://civitai.com/models/1310467) | `4ur4_illu`, `shiny` | Shiny anime style with auras and glowing effects. |

**Upscalers**

| File | Notes |
|---|---|
| [`4x-UltraSharp.pth`](https://huggingface.co/Aitrepreneur/FLX) | General-purpose 4× upscaler for sharper outputs. |

Two additional sections are recognised:

- **`[CUSTOM]`** — places files outside the section folders. Format: `relative/path:https://...`.
- **`[GIT_REPOS]`** — clones a Git repository into `models/<relative/path>`. Format: `relative/path:https://...`.

Existing non-empty files are skipped. To force a re-download, delete or rename the local file.

### Extensions (`extensions.conf`)

`extensions.conf` accepts either an `[EXTENSIONS]` section or a plain list of Git URLs. Each repository is cloned into `custom_nodes/<repo-basename>` on first run and updated via `git pull --ff-only` on later runs.

Dependencies declared by an extension are installed when its commit hash changes:

- `requirements.txt` is installed with `pip install -r`.
- `install.py` is executed once.

Last-known commits are tracked in `custom_nodes/.last_commits/<name>.commit`. Remove the marker file to force a reinstall on the next start.

### Civitai API key

Some Civitai assets require a logged-in account, paid/early access, or explicit account permission. Create a Civitai API key and expose it as `CIVITAI_API_KEY`:

```bash
export CIVITAI_API_KEY="your-civitai-api-key"
docker compose up -d
```

Alternatively, place the key in an ignored `.env` file at the project root:

```env
CIVITAI_API_KEY=your-civitai-api-key
```

`docker-compose.yml` forwards `CIVITAI_API_KEY` into the container, and `check_models_url.sh` loads it automatically. The key is appended as a `token=` query parameter on Civitai URLs and is redacted from log output.

## URL checker

Before a build, validate that every URL in `models.conf` still resolves:

```bash
bash check_models_url.sh
# or with a custom file
bash check_models_url.sh path/to/other.conf
```

The script performs an HTTP `HEAD` (and falls back to a `GET` range request) against each entry, prints `[OK]` / `[FAIL]` per URL, and exits non-zero if any URL fails. Civitai entries are probed without following redirects, and 401/403 responses produce a tailored authentication error.

## Operations

**Validate the Compose configuration**

```bash
docker compose config --quiet
```

**Syntax-check a shell script**

```bash
bash -n init_scripts/init_models.sh
```

**Rebuild after Dockerfile or `init_scripts/` changes**

```bash
docker compose up -d --build
```

**Reset the extension Python environment**

If the extension venv breaks after upstream package updates (e.g. mismatched `torch`, `xformers`, `torchaudio`):

```bash
docker compose down
docker volume rm comfyui_anime_venv
rm -f custom_nodes/.last_commits/*.commit
docker compose up -d --build
```

Host-side bind mounts (`./models`, `./input`, `./output`, `./workflows`, `./custom_nodes`) are not touched by this reset. Only the Python environment is rebuilt.

## Tips for 8 GB VRAM GPUs

- The default `CLI_ARGS` in `docker-compose.yml` already includes `--lowvram`.
- For Animagine XL 4.0 Opt and similar SDXL checkpoints, start at moderate resolutions and use the included upscale workflow (`workflows/anime-text-to-image-animagine-xl-4-with-upscale.json`) instead of generating large images directly.
- `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` is set in the image to reduce fragmentation under sustained load.
