# Self-Hosted PDF OCR API for Large Documents

A self-hosted PDF OCR API powered by [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) and the PaddleOCR-VL model. Runs on GPU via Docker, processes PDFs page-by-page, and returns markdown content in JSON responses. Good support (not perfect) for Latvian and Lithuanian languages.

> **Fork notice:** This is a fork maintained at [github.com/bretton/paddleocr-pdf-api](https://github.com/bretton/paddleocr-pdf-api), based on the original [Edgaras0x4E/paddleocr-pdf-api](https://github.com/Edgaras0x4E/paddleocr-pdf-api). It targets **Ubuntu 24.04 + CUDA 12.9** and adds an optional **local image-description backend (Ollama + Gemma 4 E4B)**. The prebuilt Docker Hub images are the upstream's and do not include these changes — build from source (below) to get them.

## Contents

- [Self-Hosted PDF OCR API for Large Documents](#self-hosted-pdf-ocr-api-for-large-documents)
	- [Contents](#contents)
	- [Model](#model)
	- [Requirements](#requirements)
	- [Quick start](#quick-start)
	- [Usage](#usage)
		- [Submit a PDF](#submit-a-pdf)
		- [Check progress](#check-progress)
		- [Get a single page](#get-a-single-page)
		- [Get all pages](#get-all-pages)
		- [List all jobs](#list-all-jobs)
		- [Cancel a job](#cancel-a-job)
		- [Delete a job](#delete-a-job)
	- [API reference](#api-reference)
	- [Configuration](#configuration)
		- [Database backend](#database-backend)
		- [Job mode](#job-mode)
		- [Image descriptions](#image-descriptions)
		- [Local image descriptions with Ollama + Gemma 4](#local-image-descriptions-with-ollama--gemma-4)
		- [API key authentication](#api-key-authentication)
	- [Data persistence](#data-persistence)
	- [Changelog](#changelog)
		- [Fork (bretton/paddleocr-pdf-api)](#fork-brettonpaddleocr-pdf-api)
		- [v0.4.0](#v040)
		- [v0.3.0](#v030)
		- [v0.2.0](#v020)
	- [License](#license)

## Model

| | |
|---|---|
| **Model** | PaddleOCR-VL-1.6 |
| **Parameters** | 0.9B |
| **Layout detection** | PP-DocLayoutV3 |
| **GPU VRAM** | ~8.5GB (OCR only); ~18GB if also running Ollama + Gemma 4 E4B |
| **Input formats** | PDF, PNG, JPG, JPEG, BMP, TIFF, WEBP |
| **FlashAttention-2** | Used automatically by `paddlepaddle-gpu` on GPUs with Compute Capability ≥ 8.0 (e.g. RTX 30/40/50, A10/A100) |

## Requirements

- **OS / CUDA:** Built for **Ubuntu 24.04** with **CUDA 12.9** (base image `nvcr.io/nvidia/cuda:12.9.2-cudnn-runtime-ubuntu24.04`).
- **NVIDIA driver:** ≥ 575 (required by the CUDA 12.9 runtime).
- **NVIDIA Container Toolkit:** ≥ 1.19.1 — see the [install guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html). After install: `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`.
- **GPU VRAM:** ~8.5GB for OCR alone; ~18GB to also run the local Gemma 4 E4B describer on the same card.

Verify the toolkit and driver before building:

```bash
docker run --rm --gpus all nvcr.io/nvidia/cuda:12.9.2-cudnn-runtime-ubuntu24.04 nvidia-smi
```

If that prints your GPU, you're ready to build.

## Quick start

**Using the [Docker Hub image](https://hub.docker.com/r/edgaras0x4e/paddleocr-pdf-api):**

```yaml
services:
  paddleocr:
    image: edgaras0x4e/paddleocr-pdf-api:latest
    ports:
      - "127.0.0.1:8099:8000"
    volumes:
      - ocr-data:/data
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    restart: unless-stopped

volumes:
  ocr-data:
```

```bash
docker compose up -d
```

**Or build from source (this fork — Ubuntu 24.04 / CUDA 12.9):**

```bash
git clone https://github.com/bretton/paddleocr-pdf-api.git && cd paddleocr-pdf-api
docker compose up --build -d
```

The bundled `docker-compose.yml` builds two services: `paddleocr` (the API, on `localhost:8099`) and `ollama` (the local vision model, on `localhost:11434`). On first startup the OCR model (~2GB) is downloaded and loaded into GPU memory. The API accepts requests immediately, but jobs will start processing once the model is ready.

If you want local image descriptions, pull the Gemma 4 model once after the stack is up:

```bash
docker compose exec ollama ollama pull gemma4:e4b
```

See [Local image descriptions with Ollama + Gemma 4](#local-image-descriptions-with-ollama--gemma-4) for details.

**Baked image (no first-run download):** for scale-to-zero or cold-start-sensitive deployments, change the image tag to `edgaras0x4e/paddleocr-pdf-api:latest-baked`. The model is pre-baked into the image, so the container starts without downloading anything; cold-start warmup is only the model load into GPU memory.

## Usage

### Submit a PDF

Also accepts single image files as a bonus: `.png`, `.jpg`, `.jpeg`, `.bmp`, `.tif`, `.tiff`, `.webp` (processed as a 1-page job).

```bash
curl -X POST http://localhost:8099/ocr -F "file=@document.pdf"
```

```json
{
  "job_id": "994e7b398bb44d8ab5eade4d2ef57a15",
  "filename": "document.pdf",
  "status": "queued"
}
```

### Check progress

```bash
curl http://localhost:8099/ocr/{job_id}
```

```json
{
  "job_id": "994e7b398bb44d8ab5eade4d2ef57a15",
  "filename": "document.pdf",
  "status": "processing",
  "total_pages": 185,
  "processed_pages": 42,
  "error": null
}
```

### Get a single page

```bash
curl http://localhost:8099/ocr/{job_id}/pages/1
```

```json
{
  "job_id": "994e7b398bb44d8ab5eade4d2ef57a15",
  "page_num": 1,
  "markdown": "## Chapter 1\n\nLorem ipsum dolor sit amet, consectetur adipiscing elit..."
}
```

### Get all pages

```bash
curl http://localhost:8099/ocr/{job_id}/result
```

```json
{
  "job_id": "994e7b398bb44d8ab5eade4d2ef57a15",
  "filename": "document.pdf",
  "status": "completed",
  "total_pages": 185,
  "processed_pages": 185,
  "pages": [
    {"page_num": 1, "markdown": "## Chapter 1\n\nLorem ipsum dolor sit amet..."},
    {"page_num": 2, "markdown": "..."}
  ]
}
```

### List all jobs

```bash
curl http://localhost:8099/jobs
```

```json
{
  "jobs": [
    {
      "job_id": "994e7b398bb44d8ab5eade4d2ef57a15",
      "filename": "document.pdf",
      "status": "completed",
      "total_pages": 185,
      "processed_pages": 185
    }
  ]
}
```

### Cancel a job

```bash
curl -X POST http://localhost:8099/ocr/{job_id}/cancel
```

```json
{
  "job_id": "994e7b398bb44d8ab5eade4d2ef57a15",
  "status": "cancelling"
}
```

### Delete a job

```bash
curl -X DELETE http://localhost:8099/ocr/{job_id}
```

```json
{
  "status": "deleted"
}
```

## API reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/ocr` | Upload a PDF for processing |
| `GET` | `/ocr/{job_id}` | Get job status and progress |
| `GET` | `/ocr/{job_id}/pages/{page_num}` | Get markdown for a specific page |
| `GET` | `/ocr/{job_id}/result` | Get all completed pages |
| `POST` | `/ocr/{job_id}/cancel` | Cancel a queued or running job |
| `DELETE` | `/ocr/{job_id}` | Delete a job and its data |
| `GET` | `/jobs` | List all jobs |

## Configuration

Environment variables set in `docker-compose.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `API_KEY` | _(empty)_ | Optional API key. When set, all requests must include an `X-API-Key` header |
| `OCR_DPI` | `200` | DPI for PDF page rendering |
| `DATABASE_URL` | _(empty)_ | Empty uses SQLite at `DB_PATH`. A `postgresql://...` URL uses PostgreSQL instead. |
| `RUN_MODE` | `server` | `server` is the always-on API. `job` reads one file from stdin, processes it, and exits. |
| `DB_PATH` | `/data/ocr.db` | SQLite database path (used when `DATABASE_URL` is empty) |
| `UPLOAD_DIR` | `/data/uploads` | Upload storage path |

### Database backend

By default the API stores jobs and results in SQLite at `/data/ocr.db`, persisted on the `/data` volume. No configuration is needed.

To use PostgreSQL instead, set `DATABASE_URL`:

```yaml
environment:
  - DATABASE_URL=postgresql://user:password@host:5432/ocr
```

The schema is created automatically on startup. With PostgreSQL the database is external, so the API is stateless apart from the uploaded files held on `/data` during processing. Multiple server containers can share one PostgreSQL database.

### Job mode

By default the container runs as an always-on server (`RUN_MODE=server`). Set `RUN_MODE=job` to instead process a single file and exit. The file is piped in on stdin; the result is written to the same database as server mode and read back through the API:

```bash
docker run --rm -i --gpus all \
  -e RUN_MODE=job \
  edgaras0x4e/paddleocr-pdf-api:latest < document.pdf
```

The container reads the file from stdin, runs the same OCR pipeline, saves the result to the database, and exits (`0` on success, non-zero on failure). It does not start the HTTP server. The baked image variant avoids the model download on each run, which suits repeated one-shot jobs.

To keep the result, point the run at a persistent database:

```bash
# PostgreSQL (external DB, nothing mounted)
docker run --rm -i --gpus all \
  -e RUN_MODE=job -e DATABASE_URL=postgresql://user:password@host:5432/ocr \
  edgaras0x4e/paddleocr-pdf-api:latest-baked < document.pdf

# SQLite (mount the /data volume so the database persists)
docker run --rm -i --gpus all \
  -e RUN_MODE=job -v ocr-data:/data \
  edgaras0x4e/paddleocr-pdf-api:latest-baked < document.pdf
```

### Image descriptions

When enabled, cropped image regions (photos, charts, seals, logos) detected by the layout model are sent to an OpenAI-compatible vision model, and the returned description is inlined in the page markdown as a `> **[Label]** ...` blockquote. Disabled by default - the original behavior (stripping image tags) is preserved.

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE_DESCRIPTION_ENABLED` | `false` | Master switch. When `false`, images are stripped as before. |
| `IMAGE_DESCRIPTION_PROVIDER` | `openai` | `openai` (any `OpenAI(base_url=…)`-compatible endpoint) or `azure` (uses `AzureOpenAI`). |
| `IMAGE_DESCRIPTION_API_URL` | `https://api.openai.com/v1` | Base URL. For `azure`, the resource endpoint, e.g. `https://<name>.cognitiveservices.azure.com`. |
| `IMAGE_DESCRIPTION_API_KEY` | _(empty)_ | Bearer / API key. Local backends accept any placeholder. |
| `IMAGE_DESCRIPTION_API_VERSION` | _(empty)_ | Azure-only, e.g. `2025-01-01-preview` (chat) or `2025-04-01-preview` (responses). |
| `IMAGE_DESCRIPTION_API_MODE` | `chat_completions` | `chat_completions` (universal) or `responses` (OpenAI-native / Azure). |
| `IMAGE_DESCRIPTION_MODEL` | `gpt-5.4` | Model name (or Azure deployment name). |
| `IMAGE_DESCRIPTION_PROMPT` | _built-in neutral prompt_ | Default prompt used when no per-label override is set. |
| `IMAGE_DESCRIPTION_PROMPT_<LABEL>` | _(empty)_ | Per-label override, e.g. `IMAGE_DESCRIPTION_PROMPT_CHART="Extract numeric data as a markdown table."`. Label is the uppercase `block_label` (`IMAGE`, `CHART`, `SEAL`, `HEADER_IMAGE`, `FOOTER_IMAGE`). |
| `IMAGE_DESCRIPTION_LABELS` | `image,chart,seal,header_image,footer_image` | Comma-separated labels to describe. `table` and `formula` are always skipped (PaddleOCR renders them natively). |
| `IMAGE_DESCRIPTION_MIN_PIXELS` | `10000` | Skip crops smaller than this area (w × h). Filters out bullet icons. |
| `IMAGE_DESCRIPTION_MAX_EDGE_PX` | `1568` | Downscale longest edge before sending. `0` disables. |
| `IMAGE_DESCRIPTION_MAX_PER_PAGE` | `10` | Cap of described images per page. |
| `IMAGE_DESCRIPTION_TIMEOUT` | `60` | Seconds per request. |
| `IMAGE_DESCRIPTION_MAX_RETRIES` | `2` | Retries on transient errors. |
| `IMAGE_DESCRIPTION_ON_ERROR` | `skip` | `skip`, `placeholder` (inserts `[image description unavailable]`), or `fail`. |

Example `docker-compose.yml` override:

```yaml
environment:
  - IMAGE_DESCRIPTION_ENABLED=true
  - IMAGE_DESCRIPTION_PROVIDER=azure
  - IMAGE_DESCRIPTION_API_URL="https://<your-resource>.cognitiveservices.azure.com"
  - IMAGE_DESCRIPTION_API_VERSION="2025-04-01-preview"
  - IMAGE_DESCRIPTION_API_MODE=responses
  - IMAGE_DESCRIPTION_MODEL="gpt-5.4"
  - IMAGE_DESCRIPTION_API_KEY="<your-key>"
  - IMAGE_DESCRIPTION_PROMPT_CHART="Extract all data points from this chart as a markdown table."
```

**Startup connectivity check.** On boot (in both server and job mode) the API logs whether it can reach the configured vision endpoint, so misconfiguration is obvious in `docker compose logs paddleocr`:

```
[image-desc] OK: reached http://ollama:11434/v1; model 'gemma4:e4b' is available
[image-desc] WARNING: reached http://ollama:11434/v1 but model 'gemma4:e4b' is not loaded. ...
[image-desc] WARNING: cannot reach vision endpoint http://ollama:11434/v1: <error>. ...
[image-desc] disabled (IMAGE_DESCRIPTION_ENABLED not set)
```

The check is non-fatal — it never blocks startup if the vision backend is still coming up.

### Local image descriptions with Ollama + Gemma 4

This fork bundles an [Ollama](https://ollama.com) service so image descriptions can run **entirely locally** on the same GPU, with no third-party API key. Gemma 4 E4B is a multimodal (image-capable) model served over Ollama's OpenAI-compatible API, which the existing `IMAGE_DESCRIPTION_*` hook consumes directly.

The bundled `docker-compose.yml` already wires this up:

```yaml
services:
  paddleocr:
    # ...
    depends_on:
      - ollama
    environment:
      - IMAGE_DESCRIPTION_ENABLED=true
      - IMAGE_DESCRIPTION_PROVIDER=openai
      - IMAGE_DESCRIPTION_API_URL=http://ollama:11434/v1   # service name, not localhost
      - IMAGE_DESCRIPTION_MODEL=gemma4:e4b
      - IMAGE_DESCRIPTION_API_KEY=ollama                   # dummy; client requires a value

  ollama:
    image: ollama/ollama:latest          # requires Ollama >= 0.20.0 for Gemma 4
    ports:
      - "127.0.0.1:11434:11434"
    volumes:
      - ollama-models:/root/.ollama
    environment:
      - OLLAMA_KEEP_ALIVE=5m             # unload idle model to free VRAM on the shared GPU
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

volumes:
  ollama-models:
```

Bring it up and pull the model once:

```bash
docker compose up -d
docker compose exec ollama ollama pull gemma4:e4b   # ~9.6GB, one-time
```

Notes:

- **Endpoints.** PaddleOCR stays on `localhost:8099`; Ollama is on `localhost:11434` (OpenAI-compatible at `/v1`). Container-to-container, PaddleOCR reaches Ollama via the service name `ollama`, not `localhost`.
- **VRAM.** PaddleOCR-VL (~8.5GB) + Gemma 4 E4B (~9.6GB) ≈ 18GB on a single card. If you hit CUDA OOM, lower `OLLAMA_KEEP_ALIVE` (e.g. `30s`) so Gemma unloads faster between calls, or run Ollama on a second GPU.
- **GPU sharing.** Both containers request the same NVIDIA device and time-share it; no extra configuration is needed beyond the `deploy.resources` block.
- **Higher throughput.** For heavy, concurrent description workloads, vLLM (with continuous batching) outperforms Ollama, at the cost of holding VRAM resident. Ollama is the better fit for the bursty, low-volume description workload and a shared GPU.

### API key authentication

Uncomment the environment section in `docker-compose.yml`:

```yaml
environment:
  - API_KEY=your-secret-key
```

Then restart:

```bash
docker compose down && docker compose up -d
```

All requests must then include the header:

```bash
curl -H "X-API-Key: your-secret-key" http://localhost:8099/jobs
```

## Data persistence

The `/data` volume stores the SQLite database and uploaded PDFs. This is a named Docker volume (`ocr-data`) that persists across container restarts and rebuilds. When `DATABASE_URL` points at PostgreSQL, the database lives in PostgreSQL and `/data` only holds uploaded files during processing.

## Changelog

### Fork (bretton/paddleocr-pdf-api)

- Migrated the base image to **Ubuntu 24.04 + CUDA 12.9** (`cuda:12.9.2-cudnn-runtime-ubuntu24.04`) from Ubuntu 22.04 / CUDA 12.6, with the matching `cu129` PaddlePaddle wheel index.
- Fixed Ubuntu 24.04 build breakage: replaced the removed `libgl1-mesa-glx` with `libgl1 libglx-mesa0`, and installed Python packages into an isolated venv to satisfy PEP 668 (externally-managed environment).
- Documented the **NVIDIA Container Toolkit ≥ 1.19.1** and driver ≥ 575 requirements, plus a GPU verification command.
- Added an optional **local image-description backend (Ollama + Gemma 4 E4B)** wired into `docker-compose.yml` via the existing OpenAI-compatible `IMAGE_DESCRIPTION_*` hook — no third-party API key needed.
- Added a non-fatal **startup connectivity check** that logs whether the vision endpoint is reachable and the model is loaded.
- Notes on FlashAttention-2 (used automatically on Compute Capability ≥ 8.0 GPUs) and an Ollama-vs-vLLM trade-off for the describer.

### v0.4.0

- Added an optional PostgreSQL backend, selected with `DATABASE_URL`. SQLite remains default.
- Added an optional `job` run mode (`RUN_MODE=job`): the container reads a file, processes it, saves the result to the database, and exits.

### v0.3.0

- Updated the OCR model to PaddleOCR-VL-1.6 (requires `paddleocr` 3.6.0).
- Added a baked image variant (`:latest-baked` / `:v0.3.0-baked`) with the model pre-baked into the image - no first-run download, for fast cold starts and scale-to-zero deployments.

### v0.2.0

- Accept single image uploads (`.png`, `.jpg`, `.jpeg`, `.bmp`, `.tif`, `.tiff`, `.webp`) as 1-page jobs.
- Optional image descriptions via OpenAI / Azure OpenAI models.
- Fixed tables to markdown tables.

## License

MIT
