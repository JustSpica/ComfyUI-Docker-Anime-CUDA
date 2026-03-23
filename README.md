# ComfyUI Anime Docker (CUDA)

I built this project primarily for my personal use. The main purpose is to have a reliable ComfyUI environment for lower-end NVIDIA GPUs, especially 8GB VRAM cards, while keeping Python dependencies clean, isolated, and reproducible through Docker. Instead of redoing manual setup every time, this repository keeps the whole bootstrap process predictable.

In practice, this setup focuses on four things: 

- Running ComfyUI in a container
- Preserving all important data on the host
- Automating model downloads from config
- Automating `custom_nodes` installation/update in a repeatable way.
- Keeping workflow files synced between host and container.

## Quick start

```bash
git clone https://github.com/JustSpica/ComfyUI-Docker-Anime-CUDA.git
cd comfyui-docker-anime-CUDA

# first run, or after changing Docker image/build files
docker compose up -d --build

# Start the container with ComfyUI.
docker compose up -d

# Stop the container
docker compose down
```

After startup, open `http://localhost:8188`.

## Project layout

```text
.
├── Dockerfile
├── docker-compose.yml
├── models.conf
├── extensions.conf
├── check_models_url.sh
├── comfy.settings.json
├── init_scripts/
│   ├── entrypoint.sh
│   ├── init_models.sh
│   ├── init_extensions.sh
│   └── config.sh
├── workflows/
├── models/
├── custom_nodes/
├── input/
└── output/
```

`Dockerfile` defines the base CUDA image, and `docker-compose.yml` handles runtime settings (GPU, ports, volumes, environment variables). Bootstrap scripts live in `init_scripts/`: `entrypoint.sh` orchestrates startup, `init_models.sh` downloads models from `models.conf`, and `init_extensions.sh` manages custom nodes listed in `extensions.conf`.

## Models

Model bootstrap is controlled by `models.conf`. The current default model set is:

| Section | File | Purpose |
|---|---|---|
| `CHECKPOINTS` | `animagine-xl-4.0-opt.safetensors` | Main anime image model for low VRAM generation (SDXL). |
| `LORAS` | `sdxl-extremely-detailed.safetensors` | Detail enhancer LoRA for richer micro-textures. |
| `LORAS` | `dmd2_sdxl_4step_lora_fp16.safetensors` | SDXL acceleration LoRA for faster sampling-style workflows. |
| `UPSCALE_MODELS` | `4x-UltraSharp.pth` | 4x upscaler for sharper outputs and detail recovery. |

You can add more entries under sections like `[CHECKPOINTS]` and `[LORAS]`. On startup, only missing files are downloaded.

If you update URLs or suspect a provider link is broken, run the URL checker first:

```bash
bash check_models_url.sh
```

## Extensions

Extensions are listed in `extensions.conf`. On startup, the project clones or updates each repository into `./custom_nodes`, installs extension dependencies (from `requirements.txt` and/or `install.py` when present), and records commits in `custom_nodes/.last_commits` to skip unnecessary reinstalls. 

This keeps the environment more stable and reproducible than relying only on manual installs inside the UI.

## Persistence and dependency hygiene

Persistent data is stored on the host through bind mounts (`./models`, `./input`, `./output`, `./workflows`, and `./custom_nodes`). The extension runtime virtual environment is stored in the Docker volume `comfyui_anime_venv`, which helps keep dependency state separate from the image layers while still allowing clean resets when needed.

If image updates or extension changes lead to import/dependency issues (`torch`, `xformers`, `torchaudio`, `pip`, etc.), recreate the extension runtime with:

```bash
docker compose down
docker volume rm comfyui_anime_venv
rm -f custom_nodes/.last_commits/*.commit
docker compose up -d --build
```

## Notes for 8GB VRAM GPUs (RTX 4060 profile)

The default `CLI_ARGS` already includes `--lowvram`, and the current stack is pinned for CUDA 12.8 (`torch==2.10.0+cu128`, `torchvision==0.25.0+cu128`, `torchaudio==2.10.0+cu128`, `xformers==0.0.35`). For Animagine XL 4.0 Opt, start at moderate resolutions and upscale in later steps to avoid VRAM pressure.
