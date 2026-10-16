# syntax=docker/dockerfile:1
ARG NODE_VERSION=26
ARG DOCKER_VERSION=29
FROM docker:${DOCKER_VERSION}-cli AS docker-cli
FROM node:${NODE_VERSION}-bookworm-slim AS runtime

ARG T3_VERSION=latest
ARG N_VERSION=latest
ARG NPM_VERSION=latest
ARG UV_VERSION=latest
ARG GH_VERSION=latest
ARG DOTNET_CHANNEL=10.0
ARG DOTNET_VERSION=latest
ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential ca-certificates cmake curl file gdb git jq less \
      libatomic1 libffi-dev libglu1-mesa libgssapi-krb5-2 libicu72 libicu-dev \
      libsqlite3-dev libssl-dev make ninja-build openssh-client patch pkg-config \
      libnss3 libglib2.0-0 libatk1.0-0 libatk-bridge2.0-0 libatspi2.0-0 \
      libdbus-1-3 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 \
      libxfixes3 libxrandr2 libxkbcommon0 libgbm1 libasound2 libexpat1 \
      python3 python3-dev python3-venv ripgrep rsync sqlite3 unzip wget xz-utils \
      zip zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && bash /tmp/dotnet-install.sh --channel "$DOTNET_CHANNEL" --version "$DOTNET_VERSION" --install-dir /opt/dotnet --no-path \
    && /opt/dotnet/dotnet --info \
    && rm /tmp/dotnet-install.sh

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/ /usr/local/libexec/docker/cli-plugins/

# Keep a bootstrap runtime in the image for both new and existing home volumes.
RUN set -eu; \
    case "$TARGETARCH" in amd64) arch=x64 ;; arm64) arch=arm64 ;; *) exit 1 ;; esac; \
    if [ "$T3_VERSION" = latest ]; then \
      T3_VERSION=$(curl -fsSL https://api.github.com/repos/pingdotgg/t3code/releases/latest | jq -er '.tag_name | ltrimstr("v")'); \
    fi; \
    archive="t3-${T3_VERSION}-linux-${arch}.tar.gz"; \
    release="https://github.com/pingdotgg/t3code/releases/download/v${T3_VERSION}"; \
    mkdir -p /opt/t3 /tmp/t3-install; \
    cd /tmp/t3-install; \
    curl -fsSLO "$release/$archive"; \
    curl -fsSLO "$release/SHA256SUMS"; \
    grep -F "$archive" SHA256SUMS > archive.sha256; \
    sha256sum -c archive.sha256; \
    tar -xzf "$archive" -C /opt/t3 --strip-components=1; \
    /opt/t3/t3 --version; \
    printf '%s\n' "$T3_VERSION" > /opt/t3/version; \
    rm -rf /tmp/t3-install

ENV HOME=/home/node \
    T3CODE_HOME=/home/node/.t3 \
    T3CODE_HOST=127.0.0.1 \
    T3CODE_PORT=3773 \
    T3CODE_NO_BROWSER=true \
    T3CODE_TELEMETRY_ENABLED=false \
    NPM_CONFIG_PREFIX=/home/node/.local \
    N_PREFIX=/home/node/.local \
    DOTNET_ROOT=/opt/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    GH_HOST=github.com \
    PATH="/home/node/.local/bin:/home/node/.dotnet/tools:/home/node/.local/share/flutter/bin:/opt/dotnet:${PATH}"

COPY --chmod=0755 install-forge-cli.sh /usr/local/bin/install-forge-cli
COPY --chmod=0755 t3-entrypoint.sh /usr/local/bin/t3

# Docker copies this initial home into a new named volume. T3's default worktree
# location resolves into the same host directory as repositories.
RUN mkdir -p /workspace/repos /workspace/worktrees /home/node/.t3 \
      /home/node/.local/bin /home/node/.local/share \
    && ln -s /workspace/worktrees /home/node/.t3/worktrees \
    && chown -R node:node /workspace /home/node

USER node
RUN docker compose version
RUN install-forge-cli gh "$GH_VERSION" \
    && gh config set git_protocol https --host github.com \
    && gh auth setup-git --hostname github.com --force
RUN npm install --global "npm@${NPM_VERSION}" "n@${N_VERSION}" \
    && if [ "$UV_VERSION" = latest ]; then uv_path=; else uv_path="${UV_VERSION}/"; fi \
    && curl -fsSL "https://astral.sh/uv/${uv_path}install.sh" -o /tmp/uv-install.sh \
    && UV_INSTALL_DIR=/home/node/.local/bin UV_NO_MODIFY_PATH=1 sh /tmp/uv-install.sh \
    && rm /tmp/uv-install.sh \
    && npm config set allow-scripts=@openai/codex,@anthropic-ai/claude-code,opencode-ai --location=user \
    && printf '\nexport PATH="$HOME/.local/bin:$HOME/.dotnet/tools:$HOME/.local/share/flutter/bin:/opt/dotnet:$PATH"\n' >> /home/node/.profile
ARG CODEX_VERSION=latest
ARG CLAUDE_VERSION=latest
ARG OPENCODE_VERSION=latest
ENV GH_VERSION=${GH_VERSION} \
    CODEX_VERSION=${CODEX_VERSION} \
    CLAUDE_VERSION=${CLAUDE_VERSION} \
    OPENCODE_VERSION=${OPENCODE_VERSION}
COPY --chmod=0755 setup-tools.sh /usr/local/bin/setup-tools
WORKDIR /workspace
ENTRYPOINT ["t3"]
CMD []

FROM runtime AS providers
RUN npm install --global \
      "@openai/codex@${CODEX_VERSION}" "@anthropic-ai/claude-code@${CLAUDE_VERSION}" \
      "opencode-ai@${OPENCODE_VERSION}" \
    && npm cache clean --force
