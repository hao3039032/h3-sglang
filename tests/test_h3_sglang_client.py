from pathlib import Path

import httpx
import pytest

from h3_sglang_client import (
    H3SglangClient,
    H3SglangError,
    SIZE_SHORT_EDGE,
    build_conditions,
    build_request,
)


def test_build_request_maps_sizes_and_orders_conditions(tmp_path):
    image = tmp_path / "reference.png"
    audio = tmp_path / "voice.wav"
    image.write_bytes(b"image")
    audio.write_bytes(b"audio")

    payload = build_request(
        prompt=" Make this scene cinematic. ",
        reference_images=[image],
        reference_audios=[audio],
        aspect_ratio="9:16",
        size="preview",
        duration=5,
        steps=24,
        seed=123,
        model="MiniMax/MiniMax-H3",
    )

    assert payload["task"] == "ref2va"
    assert payload["target"]["short_edge"] == 480
    assert SIZE_SHORT_EDGE["native"] == 768
    assert payload["conditions"] == [
        {
            "type": "image",
            "uri": image.resolve().as_uri(),
            "role": "reference",
        },
        {
            "type": "audio",
            "uri": audio.resolve().as_uri(),
            "role": "reference",
        },
    ]


def test_build_request_validates_core_fields(tmp_path):
    reference = tmp_path / "reference.mp4"
    reference.write_bytes(b"video")

    with pytest.raises(H3SglangError, match="Prompt is required"):
        build_request(prompt=" ", reference_videos=[reference])
    with pytest.raises(H3SglangError, match="aspect_ratio"):
        build_request(
            prompt="prompt",
            reference_videos=[reference],
            aspect_ratio="2:1",
        )
    with pytest.raises(H3SglangError, match="steps"):
        build_request(prompt="prompt", reference_videos=[reference], steps=61)


def test_build_conditions_enforces_reference_limits(tmp_path):
    references = [tmp_path / f"image-{index}.png" for index in range(10)]
    for reference in references:
        reference.write_bytes(b"image")

    with pytest.raises(H3SglangError, match="9 image references"):
        build_conditions(reference_images=references)
    with pytest.raises(H3SglangError, match="at least one reference"):
        build_conditions()


def test_generate_downloads_completed_mp4(tmp_path, monkeypatch):
    monkeypatch.setenv("H3_POLL_INTERVAL", "0.01")
    seen = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.method == "POST" and request.url.path == "/v1/videos":
            return httpx.Response(200, json={"id": "job-123"})
        if request.method == "GET" and request.url.path == "/v1/videos/job-123":
            return httpx.Response(200, json={"id": "job-123", "status": "completed"})
        if request.url.path == "/v1/videos/job-123/content":
            return httpx.Response(
                200,
                headers={"content-type": "video/mp4"},
                content=b"mp4-data",
            )
        return httpx.Response(404)

    client = H3SglangClient(
        base_url="http://sglang.test",
        output_dir=tmp_path / "outputs",
        transport=httpx.MockTransport(handler),
    )
    result = client.generate(
        prompt="prompt",
        reference_images=[Path(__file__)],
        seed=7,
    )

    assert result.path.name.startswith("h3-job-123-")
    assert result.path.suffix == ".mp4"
    assert result.path.read_bytes() == b"mp4-data"
    assert result.metrics["job_id"] == "job-123"
    assert result.metrics["seed"] == 7
    assert [request.method for request in seen] == ["POST", "GET", "GET"]


def test_generate_surfaces_sglang_error(tmp_path, monkeypatch):
    monkeypatch.setenv("H3_POLL_INTERVAL", "0.01")

    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "POST":
            return httpx.Response(200, json={"id": "failed-job"})
        return httpx.Response(
            200,
            json={
                "id": "failed-job",
                "status": "failed",
                "error": {"message": "audio decode failed"},
            },
        )

    client = H3SglangClient(
        base_url="http://sglang.test",
        output_dir=tmp_path,
        transport=httpx.MockTransport(handler),
    )

    with pytest.raises(H3SglangError, match="audio decode failed"):
        client.generate(prompt="prompt", reference_images=[Path(__file__)])
