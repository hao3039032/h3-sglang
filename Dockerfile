ARG SGLANG_BASE_IMAGE=lmsysorg/sglang:v0.5.16
FROM ${SGLANG_BASE_IMAGE}

ARG SGLANG_PIN=d3589a7251e4df6710e14ac55071585e80ae62c7
ARG SGLANG_SOURCE=https://github.com/sgl-project/sglang.git

ENV PYTHON_BIN=/usr/bin/python3 \
    SGLANG_BIN=/usr/local/bin/sglang \
    H3_SGLANG_MODEL_PATH=/models/MiniMax-H3 \
    H3_OUTPUT_DIR=/outputs \
    PYTHONUNBUFFERED=1

WORKDIR /opt/h3-sglang

COPY . /opt/h3-sglang

RUN git init /opt/sglang-src \
    && git -C /opt/sglang-src remote add origin "$SGLANG_SOURCE" \
    && git -C /opt/sglang-src fetch --depth 1 origin "$SGLANG_PIN" \
    && git -C /opt/sglang-src checkout FETCH_HEAD \
    && git -C /opt/sglang-src apply /opt/h3-sglang/patches/sglang/0001-allow-minimax-h3-480p-targets.patch \
    && python3 -m pip install --no-deps --force-reinstall -e /opt/sglang-src/python \
    && python3 -m pip install "/opt/sglang-src/python[diffusion]" \
    && python3 -m pip install --no-deps --force-reinstall /opt/h3-sglang \
    && rm -rf /root/.cache/pip

RUN mkdir -p /outputs /models/MiniMax-H3 \
    && chmod +x /opt/h3-sglang/scripts/*.sh

EXPOSE 7860
STOPSIGNAL SIGTERM

ENTRYPOINT ["/opt/h3-sglang/scripts/start.sh"]
