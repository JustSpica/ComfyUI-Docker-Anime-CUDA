# Anime Text-to-Image with Upscale (Animagine XL 4.0)

This workflow generates an anime image with `animagine-xl-4.0-opt.safetensors`, then runs a dedicated upscale + low-step refinement pass for sharper final output while keeping VRAM usage manageable.

## Pipeline overview

The graph is a two-stage flow:

1. Base generation: `CheckpointLoaderSimple` -> `LoraLoader` -> positive/negative `CLIPTextEncode` -> `KSampler` -> `VAEDecode`
2. Upscale + refine: `UpscaleModelLoader` (`4x-UltraSharp`) -> `ImageUpscaleWithModel` -> `ImageScaleToTotalPixels` -> `VAEEncode` -> `LoraLoaderModelOnly` (`dmd2`) -> second `KSampler` -> `VAEDecode` -> `SaveImage`

An `ImageCompareNode` is included to compare pre-upscale vs final output.

## Default settings (low VRAM profile)

- Base resolution: `1344x768`
- Base sampler: `euler_ancestral`
- Base steps / CFG / denoise: `28 / 5 / 1.0`
- Upscale model: `4x-UltraSharp.pth`
- Resize target after upscale: `3 MP` (`ImageScaleToTotalPixels`, `lanczos`)
- Refine sampler: `euler_ancestral`
- Refine steps / CFG / denoise: `8 / 1 / 0.35`

## Models used

- Checkpoint: `animagine-xl-4.0-opt.safetensors`
- Detail LoRA (base pass): `sdxl-extremely-detailed.safetensors` (`0.6 / 0.6`)
- Fast refine LoRA (second pass): `dmd2_sdxl_4step_lora_fp16.safetensors` (`1.0` model-only)
- Upscaler: `4x-UltraSharp.pth`

These are expected in `models.conf` and are downloaded automatically on container startup when missing.

## How to use

1. Open `workflows/anime-text-to-image-animagine-xl-4-with-upscale.json` in ComfyUI.
2. Edit positive/negative prompts.
3. Queue Prompt.
4. Find outputs in `output/` with prefix `animagine_xl_4_opt_upscale`.

## Quick tuning tips

- Cleaner style: reduce base LoRA to `0.45-0.55`.
- More detail: increase base steps to `30-34`.
- Less artifacts after upscale: lower refine denoise to `0.25-0.30`.
- Lower VRAM pressure: reduce base size (for example `1216x704`) and keep refine steps low.
