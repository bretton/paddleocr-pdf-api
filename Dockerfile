FROM nvcr.io/nvidia/cuda:12.9.2-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV DISABLE_MODEL_SOURCE_CHECK=True
ENV PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-dev python3-venv \
    libgl1 libglx-mesa0 libglib2.0-0 libgomp1 libmagic1 \
    && rm -rf /var/lib/apt/lists/*

# Use an isolated venv: Ubuntu 24.04 (PEP 668) marks the system Python as
# externally managed, so system-wide pip installs are blocked.
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /app

RUN pip install --no-cache-dir paddlepaddle-gpu==3.2.2 \
    --index-url https://www.paddlepaddle.org.cn/packages/stable/cu129/

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir "paddlex[ocr]"

COPY app ./app

ENV FLAGS_use_stream_safe_cuda_allocator=false

VOLUME /data

EXPOSE 8000

ENTRYPOINT []
CMD ["python3", "-m", "app.api"]
