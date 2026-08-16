ARG SGLANG_BASE_IMAGE=lmsysorg/sglang:v0.5.16
FROM ${SGLANG_BASE_IMAGE}

ARG SGLANG_PIN=480a8ba7cae46658380428576b51d682f28489f1
ARG SGLANG_SOURCE=https://github.com/hao3039032/sglang-h3.git

ENV PYTHON_BIN=/usr/bin/python3 \
    SGLANG_BIN=/usr/local/bin/sglang \
    H3_SGLANG_MODEL_PATH=/models/MiniMax-H3 \
    H3_OUTPUT_DIR=/outputs \
    PYTHONUNBUFFERED=1

WORKDIR /opt/h3-sglang

COPY . /opt/h3-sglang

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

RUN git init /opt/sglang-src \
    && git -C /opt/sglang-src remote add origin "$SGLANG_SOURCE" \
    && git -C /opt/sglang-src fetch --depth 1 origin "$SGLANG_PIN" \
    && git -C /opt/sglang-src checkout FETCH_HEAD \
    && python3 -m pip install 'ninja>=1.11,<2' \
    && python3 -m pip install --no-deps --force-reinstall -e /opt/sglang-src/python \
    && python3 -m pip install "/opt/sglang-src/python[diffusion]" \
    && python3 -m pip install --no-deps --force-reinstall /opt/h3-sglang \
    && rm -rf /root/.cache/pip

RUN mkdir -p /outputs /models/MiniMax-H3 \
    && chmod +x /opt/h3-sglang/scripts/*.sh

EXPOSE 7860
STOPSIGNAL SIGTERM

ENTRYPOINT ["/opt/h3-sglang/scripts/start.sh"]
