"""Client for MiniMax H3's asynchronous SGLang video API."""

from __future__ import annotations

import os
import random
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx


FPS = 24
ASPECT_RATIOS = ("16:9", "9:16", "1:1", "4:3", "3:4", "21:9")
SIZE_SHORT_EDGE = {"preview": 480, "native": 768}
CONDITION_LIMITS = {"image": 9, "video": 3, "audio": 3}


@dataclass(frozen=True)
class GenerationResult:
    path: Path
    metrics: dict[str, Any]


class H3SglangError(RuntimeError):
    pass


def _file_uri(path: Path) -> str:
    try:
        return path.resolve(strict=True).as_uri()
    except OSError as error:
        raise H3SglangError(f"Reference file is not readable: {path}") from error


def build_conditions(
    reference_images: list[Path] | None = None,
    reference_videos: list[Path] | None = None,
    reference_audios: list[Path] | None = None,
) -> list[dict[str, str]]:
    groups = {
        "image": reference_images or [],
        "video": reference_videos or [],
        "audio": reference_audios or [],
    }
    conditions: list[dict[str, str]] = []
    for condition_type, paths in groups.items():
        values = [Path(path) for path in paths]
        if len(values) > CONDITION_LIMITS[condition_type]:
            raise H3SglangError(
                f"At most {CONDITION_LIMITS[condition_type]} {condition_type} references are allowed"
            )
        conditions.extend(
            {
                "type": condition_type,
                "uri": _file_uri(path),
                "role": "reference",
            }
            for path in values
        )
    if not conditions:
        raise H3SglangError("REF2VA requires at least one reference file")
    return conditions


def build_request(
    *,
    prompt: str,
    reference_images: list[Path] | None = None,
    reference_videos: list[Path] | None = None,
    reference_audios: list[Path] | None = None,
    aspect_ratio: str = "9:16",
    size: str = "preview",
    duration: float = 5.0,
    steps: int = 24,
    seed: int | None = None,
    model: str = "MiniMax/MiniMax-H3",
) -> dict[str, Any]:
    if not prompt or not prompt.strip():
        raise H3SglangError("Prompt is required")
    if aspect_ratio not in ASPECT_RATIOS:
        raise H3SglangError(f"aspect_ratio must be one of {ASPECT_RATIOS}")
    if size not in SIZE_SHORT_EDGE:
        raise H3SglangError("size must be preview or native")
    duration = float(duration)
    if not 4.0 <= duration <= 15.0:
        raise H3SglangError("duration must be between 4 and 15 seconds")
    steps = int(steps)
    if not 8 <= steps <= 60:
        raise H3SglangError("steps must be between 8 and 60")
    if seed is not None and not 0 <= int(seed) <= 2**63 - 1:
        raise H3SglangError("seed must be between 0 and 2^63-1")

    return {
        "model": model,
        "prompt": prompt.strip(),
        "task": "ref2va",
        "conditions": build_conditions(
            reference_images, reference_videos, reference_audios
        ),
        "target": {
            "short_edge": SIZE_SHORT_EDGE[size],
            "aspect_ratio": aspect_ratio,
            "duration_seconds": duration,
        },
        "num_outputs_per_prompt": 1,
        "num_inference_steps": steps,
        "flow_shift": 12.0,
        "audio_flow_shift": 3.0,
        "seed": seed,
    }


def _error_message(status: dict[str, Any]) -> str:
    error = status.get("error")
    if isinstance(error, dict):
        message = error.get("message") or error.get("detail")
        if message:
            return str(message)
    if error:
        return str(error)
    return "SGLang generation failed without an error message"


def _validate_status(status: dict[str, Any]) -> str:
    if not isinstance(status, dict) or not isinstance(status.get("id"), str):
        raise H3SglangError("SGLang returned an invalid video status response")
    state = str(status.get("status", "")).lower()
    if state in {"failed", "cancelled", "canceled", "deleted", "error"}:
        raise H3SglangError(_error_message(status))
    if state not in {"queued", "in_progress", "processing", "running", "completed"}:
        raise H3SglangError(f"SGLang returned unexpected status {state!r}")
    return state


def _download_extension(response: httpx.Response) -> str:
    content_type = response.headers.get("content-type", "").split(";", 1)[0].strip()
    if content_type == "video/mp4" or not content_type:
        return ".mp4"
    return ".bin"


class H3SglangClient:
    def __init__(
        self,
        base_url: str | None = None,
        output_dir: Path | None = None,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        self.base_url = (
            base_url
            or os.getenv("H3_SGLANG_BASE_URL", "http://127.0.0.1:30010")
        ).rstrip("/")
        self.output_dir = Path(
            output_dir or os.getenv("H3_OUTPUT_DIR", "outputs")
        ).resolve()
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.transport = transport

    def generate(
        self,
        *,
        prompt: str,
        reference_images: list[Path] | None = None,
        reference_videos: list[Path] | None = None,
        reference_audios: list[Path] | None = None,
        aspect_ratio: str = "9:16",
        size: str = "preview",
        duration: float = 5.0,
        steps: int = 24,
        seed: int | None = None,
        model: str | None = None,
        timeout_seconds: float = 45 * 60,
    ) -> Path | GenerationResult:
        started = time.monotonic()
        selected_seed = (
            int(seed)
            if seed is not None
            else random.SystemRandom().randint(0, 2**63 - 1)
        )
        payload = build_request(
            prompt=prompt,
            reference_images=reference_images,
            reference_videos=reference_videos,
            reference_audios=reference_audios,
            aspect_ratio=aspect_ratio,
            size=size,
            duration=duration,
            steps=steps,
            seed=selected_seed,
            model=model or os.getenv("H3_MODEL_NAME", "MiniMax/MiniMax-H3"),
        )
        with httpx.Client(
            base_url=self.base_url, transport=self.transport, timeout=30.0
        ) as client:
            try:
                response = client.post("/v1/videos", json=payload)
                response.raise_for_status()
                submitted = response.json()
            except httpx.HTTPError as error:
                raise H3SglangError(f"Could not submit SGLang job: {error}") from error
            video_id = submitted.get("id")
            if not isinstance(video_id, str) or not video_id:
                raise H3SglangError("SGLang submission did not return a job id")

            deadline = time.monotonic() + timeout_seconds
            poll_interval = float(os.getenv("H3_POLL_INTERVAL", "1"))
            status_state = "queued"
            while True:
                try:
                    response = client.get(f"/v1/videos/{video_id}")
                    response.raise_for_status()
                    status = response.json()
                except httpx.HTTPError as error:
                    raise H3SglangError(
                        f"Could not poll SGLang job {video_id}: {error}"
                    ) from error
                status_state = _validate_status(status)
                if status_state == "completed":
                    break
                if time.monotonic() >= deadline:
                    raise H3SglangError(
                        f"SGLang job {video_id} exceeded {timeout_seconds:g} seconds"
                    )
                time.sleep(max(0.1, poll_interval))

            destination = self.output_dir / f"h3-{video_id}-{uuid.uuid4().hex}"
            try:
                with client.stream(
                    "GET", f"/v1/videos/{video_id}/content?variant=0"
                ) as response:
                    response.raise_for_status()
                    destination = destination.with_suffix(
                        _download_extension(response)
                    )
                    with destination.open("wb") as output:
                        for chunk in response.iter_bytes(1024 * 1024):
                            output.write(chunk)
            except httpx.HTTPError as error:
                destination.unlink(missing_ok=True)
                raise H3SglangError(
                    f"Could not download SGLang result {video_id}: {error}"
                ) from error
            if destination.stat().st_size == 0:
                destination.unlink(missing_ok=True)
                raise H3SglangError("SGLang returned an empty result file")

        elapsed = time.monotonic() - started
        print(
            f"generated {SIZE_SHORT_EDGE[size]}p {aspect_ratio} duration={duration:g}s "
            f"steps={steps} seed={selected_seed} job={video_id} "
            f"seconds={elapsed:.3f} output={destination}",
            flush=True,
        )
        return GenerationResult(
            destination,
            {
                "job_id": video_id,
                "seed": selected_seed,
                "duration_seconds": round(elapsed, 3),
                "output_bytes": destination.stat().st_size,
            },
        )
