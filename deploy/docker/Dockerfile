# syntax=docker/dockerfile:1
ARG NODE_VERSION=26.10.0
FROM node:${NODE_VERSION}-bookworm-slim AS runtime

ARG T3_VERSION=0.0.45
ARG N_VERSION=10.2.0
ARG NPM_VERSION=12.2.0
ARG UV_VERSION=0.12.22
ARG GH_VERSION=2.102.0
ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl git libatomic1 libglu1-mesa \
      openssh-client pkg-config ripgrep unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

# Install the release archive into the immutable image, not the writable T3 home.
RUN set -eu; \
    case "$TARGETARCH" in amd64) arch=x64 ;; arm64) arch=arm64 ;; *) exit 1 ;; esac; \
    archive="t3-${T3_VERSION}-linux-${arch}.tar.gz"; \
    release="https://github.com/pingdotgg/t3code/releases/download/v${T3_VERSION}"; \
    mkdir -p /opt/t3 /tmp/t3-install; \
    cd /tmp/t3-install; \
    curl -fsSLO "$release/$archive"; \
    curl -fsSLO "$release/SHA256SUMS"; \
    grep -F "$archive" SHA256SUMS > archive.sha256; \
    sha256sum -c archive.sha256; \
    tar -xzf "$archive" -C /opt/t3 --strip-components=1; \
    ln -s /opt/t3/t3 /usr/local/bin/t3; \
    t3 --version; \
    rm -rf /tmp/t3-install

ENV HOME=/home/node \
    T3CODE_HOME=/home/node/.t3 \
    T3CODE_HOST=127.0.0.1 \
    T3CODE_PORT=3773 \
    T3CODE_NO_BROWSER=true \
    T3CODE_TELEMETRY_ENABLED=false \
    NPM_CONFIG_PREFIX=/home/node/.local \
    N_PREFIX=/home/node/.local \
    GH_HOST=github.com \
    PATH="/home/node/.local/bin:/home/node/.local/share/flutter/bin:${PATH}"

COPY --chmod=0755 install-forge-cli.sh /usr/local/bin/install-forge-cli

# Docker copies this initial home into a new named volume. T3's default worktree
# location resolves into the same host directory as repositories.
RUN mkdir -p /workspace/repos /workspace/worktrees /home/node/.t3 \
      /home/node/.local/bin /home/node/.local/share \
    && ln -s /workspace/worktrees /home/node/.t3/worktrees \
    && chown -R node:node /workspace /home/node

USER node
RUN install-forge-cli gh "$GH_VERSION" \
    && gh config set git_protocol https --host github.com \
    && gh auth setup-git --hostname github.com --force
RUN npm install --global "npm@${NPM_VERSION}" "n@${N_VERSION}" \
    && curl -fsSL "https://astral.sh/uv/${UV_VERSION}/install.sh" -o /tmp/uv-install.sh \
    && UV_INSTALL_DIR=/home/node/.local/bin UV_NO_MODIFY_PATH=1 sh /tmp/uv-install.sh \
    && rm /tmp/uv-install.sh \
    && npm config set allow-scripts=@openai/codex,@anthropic-ai/claude-code,opencode-ai --location=user \
    && printf '\nexport PATH="$HOME/.local/bin:$HOME/.local/share/flutter/bin:$PATH"\n' >> /home/node/.profile
ARG CODEX_VERSION=0.160.0
ARG CLAUDE_VERSION=2.1.287
ARG OPENCODE_VERSION=1.18.34
ENV GH_VERSION=${GH_VERSION} \
    CODEX_VERSION=${CODEX_VERSION} \
    CLAUDE_VERSION=${CLAUDE_VERSION} \
    OPENCODE_VERSION=${OPENCODE_VERSION}
COPY --chmod=0755 setup-tools.sh /usr/local/bin/setup-tools
WORKDIR /workspace
ENTRYPOINT ["t3"]
CMD ["serve"]

FROM runtime AS providers
RUN npm install --global \
      "@openai/codex@${CODEX_VERSION}" "@anthropic-ai/claude-code@${CLAUDE_VERSION}" \
      "opencode-ai@${OPENCODE_VERSION}" \
    && npm cache clean --force
