FROM ghcr.io/openclaw/openclaw:latest

USER root

ENV PIP_ROOT_USER_ACTION=ignore \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 python3-pip python3-venv \
  && python3 -m pip install --no-cache-dir --break-system-packages seaborn matplotlib pandas numpy pillow \
  && ln -sf /usr/bin/python3 /usr/local/bin/python \
  && ln -sf /usr/bin/pip3 /usr/local/bin/pip \
  && mkdir -p /home/node/.openclaw/workspace/output \
  && chown -R 1000:1000 /home/node/.openclaw \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

USER 1000:1000
