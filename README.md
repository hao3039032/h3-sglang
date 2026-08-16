# MiniMax H3 on SGLang

This repository packages a native MiniMax-H3 REF2VA deployment with a small
Gradio frontend. It is intended for platforms that provide a complete external
MiniMax-H3 model directory and all visible GPUs to the container.

The deployment pins the `h3` branch from
[hao3039032/sglang-h3](https://github.com/hao3039032/sglang-h3) to commit
`480a8ba7cae46658380428576b51d682f28489f1`. Platform images containing
SGLang 0.5.1 are too old for H3. The fork also allows the custom 480-pixel
short-edge target while retaining the native 768-pixel target.

## Precision Policy

- The REF2VA DiT runs BF16/FP32 by default.
- The Qwen text encoder is not quantized.
- The video and audio VAEs are not quantized.
- `H3_DIT_QUANT=fp8` enables SGLang online FP8 for the DiT. This is an
  experimental quality/performance mode on consumer GPUs; upstream validated it
  on B200/B300-class hardware, not on RTX 4090 or RTX 5090.
- The UI maps `preview` to `short_edge=480` and `native` to `short_edge=768`.
  The 480p path is a custom fork behavior and still needs visual and audio
  validation on the target workload.

## Local Bootstrap

```bash
./scripts/bootstrap.sh
```

This creates `.venv`, checks out the pinned SGLang fork commit under
`.third_party/sglang`, and installs both SGLang and this repository. It never
downloads model weights.
The host or container must also provide `ffprobe`; SGLang uses it to validate
the final MiniMax H3 output.

Serve SGLang and Gradio separately when developing:

```bash
export H3_SGLANG_MODEL_PATH=/absolute/path/to/MiniMax-H3
./scripts/serve-5090.sh
```

```bash
./scripts/start-gradio.sh
```

Or run both processes in one terminal:

```bash
export H3_SGLANG_MODEL_PATH=/absolute/path/to/MiniMax-H3
export MINIMAX_H3_LICENSE_ACCEPTED=1
./scripts/start.sh
```

The default topology is the upstream 2x RTX 5090 recipe: TP2, Ulysses1,
memory placement, and 20 resident DiT blocks. The launcher does not pass
`--num-gpus` unless `H3_NUM_GPUS` is explicitly set. This lets GPU visibility
be controlled by `CUDA_VISIBLE_DEVICES`, the container runtime, or the
platform's process environment.

With `H3_DIT_QUANT=fp8`, the 5090 launcher keeps checkpoint tensors on CPU and
streams each quantized module through the GPU only for weight postprocessing.
This avoids materializing the complete quantized DiT on one 32 GB GPU before
layerwise residency is configured.

For a 4x RTX 4090 candidate, start with:

```bash
export H3_NUM_GPUS=4
export H3_TP_SIZE=2
export H3_ULYSSES_DEGREE=2
```

If capacity is more important than latency, also try `H3_TP_SIZE=4` with
`H3_ULYSSES_DEGREE=1`. These are candidate configurations and have not been
validated by this repository.

## Docker

Build directly from the official CUDA 13 SGLang Python environment:

```bash
docker build -t h3-sglang:local .
```

Run it with a complete model-root mount:

```bash
docker run --rm --gpus all --ipc host --shm-size 32g \
  -p 7860:7860 \
  -v /path/to/MiniMax-H3:/models/MiniMax-H3:ro \
  -v h3-outputs:/outputs \
  -e MINIMAX_H3_LICENSE_ACCEPTED=1 \
  h3-sglang:local
```

The image does not include weights and does not download, validate, repair, or
replace them. `H3_SGLANG_MODEL_PATH` must point to a readable, complete model
root. A missing or invalid model is an operator error and should be fixed by
remounting or restoring the model, not by runtime recovery logic.

Set the public proxy origin only when the platform rewrites Gradio URLs:

```bash
-e GRADIO_PUBLIC_PORT=8443
-e GRADIO_PUBLIC_PROTO=https
```

These settings are intentionally platform-neutral and never hard-code a
provider-specific hostname.

## API

The frontend submits REF2VA jobs to SGLang's asynchronous API:

```text
POST /v1/videos
GET  /v1/videos/{id}
GET  /v1/videos/{id}/content?variant=0
```

Reference files must be visible at the same local path to both Gradio and
SGLang. The single-container entry point satisfies this automatically. If the
processes are split across containers, they need a shared upload/staging
volume; sending only a local `file://` URI to a remote SGLang container is not
sufficient.
