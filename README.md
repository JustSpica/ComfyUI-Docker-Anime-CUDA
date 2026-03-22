# ComfyUI Docker (Anime + Cinemagraph)

Setup focado em ComfyUI com GPU NVIDIA para gerar imagens de anime e cinemagraphs.

## Arquitetura (baseada no projeto de referencia)

- `Dockerfile`: imagem CUDA + Python + ComfyUI + bootstrap scripts.
- `docker-compose.yml`: execucao com GPU, volumes persistentes e configs montadas.
- `init_scripts/config.sh`: funcoes compartilhadas (logs, download, parse de config).
- `init_scripts/init_extensions.sh`: instala/atualiza custom nodes de `extensions.conf`.
- `init_scripts/init_models.sh`: baixa modelos de `models.conf` por secoes.
- `init_scripts/entrypoint.sh`: roda bootstrap e inicia o ComfyUI.
- `check_models_url.sh`: valida rapidamente links de download no `models.conf`.

## Como iniciar

```bash
docker compose build
docker compose up -d
```

UI do ComfyUI: `http://localhost:8188`

## Onde editar

- `extensions.conf`: repos Git de extensoes.
- `models.conf`: lista de checkpoints, loras, vae e utilitarios.

Arquivos de dados ficam em `./models`, `./input`, `./output` e `./custom_nodes`.

## Validar links de modelos antes de subir

```bash
bash check_models_url.sh
```

Isso evita subir o container com URLs quebradas.

## Dicas para RTX 4060 8GB

- Mantido `--lowvram` por padrao em `CLI_ARGS`.
- Para RTX 4060 8GB, use `animagine-xl-4.0-opt` com resolucoes moderadas.
- Comece com resolucoes como `768x1152` e ajuste conforme VRAM.
- Se extensoes quebrarem deps, remova o volume `comfyui_anime_venv` e suba de novo.
