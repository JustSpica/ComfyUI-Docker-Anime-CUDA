# Anime Text-to-Image (Animagine XL 4.0)

This workflow generates anime images from text prompts using `animagine-xl-4.0-opt.safetensors`, with an optional detail boost from LoRA.

## Pipeline overview

The graph uses a straightforward text-to-image flow: `CheckpointLoaderSimple` -> `LoraLoader` -> positive/negative `CLIPTextEncode` -> `KSampler` -> `VAEDecode` -> `SaveImage`.

Default settings are tuned for low VRAM GPUs (8GB profile):

- Resolution: `832x1216`
- Sampler: `euler_ancestral`
- Steps: `28`
- CFG: `5`
- Denoise: `1.0`
- Seed mode: `fixed`

## Models used

- Checkpoint: `animagine-xl-4.0-opt.safetensors`
- LoRA: `sdxl-extremely-detailed.safetensors` (`0.6 / 0.6`)

If you want cleaner style adherence, lower LoRA strength to `0.45-0.55`.

## Prompt format (Animagine-friendly)

Use prompts in this structure:

`subject, character/series, composition, lighting, style tags, masterpiece, high score, great score, absurdres`

Negative prompt (already included in the workflow):

`lowres, bad anatomy, bad hands, text, error, missing finger, extra digits, fewer digits, cropped, worst quality, low quality, low score, bad score, average score, signature, watermark, username, blurry`

## How to use

1. Open `workflows/anime-text-to-image-animagine-xl-4.json` in ComfyUI.
2. Edit positive/negative prompts.
3. Queue Prompt.
4. Find outputs in `output/` with prefix `animagine_xl4_opt_test`.

## Quick tuning tips

- More details: increase steps to `32-36`.
- More prompt control: increase CFG to `5.5-6.5`.
- Fewer artifacts: reduce LoRA strength and keep CFG near `5`.
- Lower VRAM usage: test `768x1152` instead of `832x1216`.
