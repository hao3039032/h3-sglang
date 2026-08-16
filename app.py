"""Gradio entry point for a native SGLang MiniMax H3 deployment."""

from __future__ import annotations

import os
import threading
from pathlib import Path
from typing import Any

import gradio as gr
from fastapi.middleware import Middleware

from h3_gradio import (
    PublicOriginMiddleware,
    configured_public_port,
    configured_public_proto,
)
from h3_sglang_client import H3SglangClient, H3SglangError


_client: H3SglangClient | None = None
_client_lock = threading.Lock()
_generation_lock = threading.Lock()


def _get_client() -> H3SglangClient:
    global _client
    if _client is None:
        with _client_lock:
            if _client is None:
                _client = H3SglangClient()
    return _client


def _paths(files: Any) -> list[Path]:
    if not files:
        return []
    if not isinstance(files, list):
        files = [files]
    paths: list[Path] = []
    for item in files:
        value = item if isinstance(item, (str, Path)) else getattr(item, "name", None)
        if value:
            paths.append(Path(value))
    return paths


def generate_video(
    prompt: str,
    reference_images: Any,
    reference_videos: Any,
    reference_audios: Any,
    aspect_ratio: str,
    size: str,
    duration: float,
    steps: int,
    seed: float | None,
) -> tuple[str, str]:
    resolved_seed = int(seed) if seed is not None else None
    try:
        with _generation_lock:
            result = _get_client().generate(
                prompt=prompt,
                reference_images=_paths(reference_images),
                reference_videos=_paths(reference_videos),
                reference_audios=_paths(reference_audios),
                aspect_ratio=aspect_ratio,
                size=size,
                duration=float(duration),
                steps=int(steps),
                seed=resolved_seed,
            )
        return str(result.path), (
            f"Done · job={result.metrics['job_id']} · seed={result.metrics['seed']} · "
            f"{result.metrics['duration_seconds']:.1f}s"
        )
    except (H3SglangError, OSError, ValueError) as error:
        raise gr.Error(str(error)) from error


def build_demo() -> gr.Blocks:
    with gr.Blocks(title="MiniMax H3 REF2VA") as demo:
        gr.Markdown("# MiniMax H3 · REF2VA")
        with gr.Row():
            with gr.Column(scale=3):
                prompt = gr.Textbox(
                    label="Prompt",
                    lines=12,
                    placeholder="Use <Picture 1>, <Video 1>, and <Audio 1> tags",
                )
                with gr.Row():
                    reference_images = gr.File(
                        label="Reference images",
                        file_count="multiple",
                        file_types=["image"],
                        type="filepath",
                    )
                    reference_videos = gr.File(
                        label="Reference videos",
                        file_count="multiple",
                        file_types=["video"],
                        type="filepath",
                    )
                    reference_audios = gr.File(
                        label="Reference audio",
                        file_count="multiple",
                        file_types=["audio"],
                        type="filepath",
                    )
                with gr.Row():
                    aspect_ratio = gr.Dropdown(
                        ["16:9", "9:16", "1:1", "4:3", "3:4", "21:9"],
                        value="9:16",
                        label="Aspect ratio",
                    )
                    size = gr.Dropdown(
                        ["preview", "native"],
                        value="preview",
                        label="Size",
                    )
                    duration = gr.Slider(
                        4, 15, value=5, step=0.5, label="Duration (seconds)"
                    )
                    steps = gr.Slider(8, 60, value=24, step=1, label="Steps")
                with gr.Row():
                    seed = gr.Number(
                        value=None,
                        precision=0,
                        minimum=0,
                        maximum=2**63 - 1,
                        label="Seed",
                    )
                submit = gr.Button("Generate", variant="primary")
            with gr.Column(scale=2):
                output = gr.Video(label="Output MP4")
                status = gr.Textbox(label="Status", interactive=False)
        submit.click(
            generate_video,
            inputs=[
                prompt,
                reference_images,
                reference_videos,
                reference_audios,
                aspect_ratio,
                size,
                duration,
                steps,
                seed,
            ],
            outputs=[output, status],
        )
    return demo


demo = build_demo()


if __name__ == "__main__":
    public_port = configured_public_port(os.getenv("GRADIO_PUBLIC_PORT"))
    public_proto = configured_public_proto(os.getenv("GRADIO_PUBLIC_PROTO"))
    middleware_options = {}
    if public_port is not None:
        middleware_options["public_port"] = public_port
    if public_proto is not None:
        middleware_options["public_proto"] = public_proto
    app_kwargs = {}
    if middleware_options:
        app_kwargs["middleware"] = [
            Middleware(PublicOriginMiddleware, **middleware_options)
        ]
    demo.queue(default_concurrency_limit=1).launch(
        server_name="0.0.0.0",
        server_port=int(os.getenv("PORT", "7860")),
        show_error=True,
        app_kwargs=app_kwargs,
    )
