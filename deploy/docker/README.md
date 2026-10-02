# Headless T3 Code with T3 Connect

Requires Docker Engine and Docker Compose v2 on a Linux host (amd64 or arm64).
Copy this directory onto the host. No source checkout, desktop, or systemd inside
the container is needed. The Dockerfile has `runtime` and `providers` targets;
the default seeds Codex, Claude, and OpenCode CLIs into a writable user installation.
Both targets include GitHub CLI (`gh`).

## Install

Run these commands from this directory on Ubuntu:

```sh
cp .env.example .env
printf '\nT3_HOSTNAME=%s\n' "$(hostname)" >> .env
sudo install -d -m 0750 -o 1000 -g 1000 \
  /srv/t3-workspace /srv/t3-workspace/repos /srv/t3-workspace/worktrees
docker compose config --quiet
docker compose build
docker compose run --rm t3 connect link --headless
```

Open the printed authorization URL on another device, verify the code, and
approve it. Accept the managed relay-client download if prompted. `connect link`
records authorization without offering a systemd installation. Do this before
starting the server so the onboarding process and server do not write state
concurrently.

Set up the tools you want before starting T3:

```sh
docker compose run --rm --entrypoint setup-tools t3
```

```sh
docker compose up -d
docker compose ps
docker compose logs --tail=100 t3
```

Sign into the same T3 Connect account on web, desktop, or mobile and select this
environment. No router forwarding or published container port is needed. Add
projects beneath `/workspace/repos`; automatic worktrees resolve beneath
`/workspace/worktrees`. Clone through the container, for example:

```sh
docker compose exec t3 sh
# In this shell:
git clone YOUR_REPOSITORY_URL /workspace/repos/my-project
exit
```

Enable your provider in Settings > Providers for this environment. To configure
more tools or reauthenticate later, reopen the same menu:

```sh
docker compose exec t3 setup-tools
```

Provider executables
are `/home/node/.local/bin/codex`, `/home/node/.local/bin/claude`, and
`/home/node/.local/bin/opencode`. Only
authenticate the providers you use. Agents can install and update development
tools under `/home/node/.local` without root; that directory takes precedence on
PATH in terminals and provider processes. Do not mount host tool directories.

## Interactive tool setup

Choose one or more numbered tools, or `a` for all. Then choose an action:

- **Set up / reauthenticate:** install missing tools at the image's configured
  versions, then run their native login prompts, including for existing accounts.
- **Authentication status:** inspect saved authentication without installing tools.
- **Install / update version:** enter a version or accept the default (`latest`
  for npm providers; the image's pinned version for GitHub CLI).
- **Log out:** use the CLI's own logout flow; OpenCode lets you select a provider.

Codex offers ChatGPT device login or a hidden API-key prompt. Claude offers
subscription or Console/API billing login. OpenCode opens its provider selection
and authentication flow. GitHub uses `github.com` and HTTPS Git credentials.
Complete browser authorization on another device using the printed URL/code.
Codex device login may need enabling in your ChatGPT security/workspace settings;
see [Codex authentication](https://developers.openai.com/codex/auth/).
The menu stays open after each action; `q` or Ctrl+C exits. Failed actions report
the affected tool and let you retry. Existing home volumes are supported without
resetting tools or credentials.

Restart affected provider sessions after an update or account change. Use native
CLI commands for additional provider configuration. To support another tool,
extend the registry and authentication/status/logout cases in `setup-tools.sh`.

## GitHub authentication

GitHub prints a browser URL and one-time code; complete the login on another
device. The setup stores credentials in the persistent home volume and enables
GitHub's HTTPS Git credential helper.
Agents can then clone without password prompts:

```sh
docker compose exec t3 gh repo clone OWNER/REPOSITORY /workspace/repos/REPOSITORY
```

`gh auth status` inspects saved login status. The container has no
OS keyring, so saved tokens are files in the home volume and accessible to agents.
Installation cannot authenticate your accounts without the login/token step.
SSH keys are optional when using these Git credential helpers.

## Install and update tools as an agent

Run these commands in the container terminal or through an agent. They require
no sudo and persist across container recreation:

```sh
# Provider CLIs and other npm tools use the writable user prefix.
npm config set allow-scripts=@openai/codex,@anthropic-ai/claude-code,opencode-ai --location=user
npm install -g @openai/codex@latest @anthropic-ai/claude-code@latest
npm install -g opencode-ai@latest
npm install -g n@latest

# GitHub CLI: supply the desired release version; downloads verify SHA256 sums.
install-forge-cli gh 2.102.0

# Install/update the active development Node.js version.
n latest
hash -r
npm install -g npm@latest
node --version
npm --version

# Python runtimes, project environments, and Python command-line tools.
uv self update
uv python install --default 3.14
uv venv /workspace/repos/my-project/.venv --python 3.14
uv tool install ruff
uv tool upgrade --all

# Install Flutter once. Its bin directory is already on PATH.
git clone --branch stable https://github.com/flutter/flutter.git \
  "$HOME/.local/share/flutter"
flutter --version
# Subsequent Flutter/Dart SDK updates:
flutter upgrade
```

Use `uv python upgrade 3.14` to update a managed Python minor release; existing
virtual environments may need recreation. Install any supported Python version
instead of 3.14 as needed. The `n` manager installs Node/npm under the same
writable prefix; T3's packaged executable has its own runtime. Restart affected
provider sessions after updating their tools.

`NODE_VERSION` selects the bootstrap Node image (currently the latest Current
release), and `NPM_VERSION` seeds npm in the writable user prefix. For LTS,
select `NODE_VERSION=24.21.0` or run `n lts` in an existing container. Installing
Node with `n` also installs its bundled npm; run `npm install -g npm@latest`
afterwards to use the latest npm. A tool installed in an existing home volume
takes precedence over the image's bootstrap tools.

npm 12 blocks dependency install scripts by default. The initial user config
allows scripts for the three included provider packages so their native binaries
install correctly. The command above applies that config to existing home
volumes too. Other global tools may require their own `--allow-scripts` approval;
project dependencies use the project's npm script policy.

The image includes a C/C++ build toolchain and Flutter's basic Linux SDK
prerequisites. Flutter Android builds also need an Android SDK/JDK, which can be
installed under the user home; Linux desktop builds need additional system
libraries baked into the image. Host devices and emulators are not passed
through. System packages and T3 itself still require an image rebuild: agents
cannot use root-level `apt install`. Tools that download executable scratch
files can use `mkdir -p "$HOME/.cache/tmp"` and set
`TMPDIR="$HOME/.cache/tmp"` for that command instead of using noexec `/tmp`.

## Filesystem boundary

| Location         | Access                          | Contents                                                                                                  |
| ---------------- | ------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `/workspace`     | Read/write host bind            | Only the dedicated repositories and worktrees directory                                                   |
| `/home/node`     | Read/write Docker volume        | T3 database, Connect identity, provider credentials/configuration, installed tools/SDKs, caches, and logs |
| `/tmp`           | Temporary, size-limited, noexec | Scratch files; lost when the container is recreated                                                       |
| Image filesystem | Read-only                       | T3, bootstrap Node, Git, build tools, operating-system files                                              |

The named home volume is initialized from the image on first use, including the
worktree symlink. Existing volumes retain their configuration across rebuilds.
T3's application logs live at `/home/node/.t3/userdata/logs`; Docker output logs
are rotated separately. Back up the workspace and home volume with the container
stopped for a consistent database backup. `docker compose down` preserves the
volume; `down --volumes` deletes credentials, history, and installed user tools.

The process runs as UID/GID 1000 with all Linux capabilities dropped,
`no-new-privileges`, Docker's default seccomp profile, private container namespaces,
and CPU/memory/process limits. Keep Ubuntu's default Docker AppArmor profile
enabled. There is no Docker socket, SSH-agent socket, device passthrough, host
network/PID namespace, or host home mount. Use rootless Docker or Docker user
namespace remapping for an additional host boundary; adjust bind ownership to
the mapped UID in that case.

This limits host filesystem access, not reads of the container's operating-system
files. T3 and agents share a UID: agents can read/change credentials, history,
and runtime state in the home volume, and every repository in the workspace.
Do not put unrelated secrets there. Separate untrusted projects into separate
stacks with separate workspace paths, home volumes, and Compose project names.
Container isolation is not a VM boundary.

Outbound networking remains available for T3 Connect, provider APIs, Git, and
package downloads. It is not an egress allowlist and does not block connections
to other homelab services. Enforce those restrictions at the host firewall or
run the stack in a dedicated VM/network segment if required. Noexec temporary
storage can prevent tools that execute downloaded files from `/tmp`; configure
those tools to use a directory under `/workspace` instead. Provider sandboxes
may require kernel features unavailable under these restrictions; use the
container as the boundary if necessary rather than enabling privileged mode or
disabling Docker's security profiles.

## Configuration and updates

Edit `.env` for the workspace path, hostname, image target, pinned versions, CPU/memory
limits, or log level. The fixed UID/GID is 1000; provision the dedicated host
directory for that user. Never mount `/`, your general home, or live T3 data.

`T3_HOSTNAME` sets the container hostname that T3 uses as its default environment
label. Setup captures the Ubuntu host's hostname; Docker does not automatically
inherit it. Without this setting, the label defaults to `t3-homelab`. After
changing the host name, update `T3_HOSTNAME` and recreate the container with
`docker compose up -d --force-recreate`. This does not share the host's UTS
namespace or change the Connect tunnel address.

T3 and system executables are immutable. Update the T3 version pin and rebuild
while agent turns are idle:

```sh
docker compose build --pull
docker compose up -d
```

Use image rebuilds rather than `t3 update` or UI server-runtime updates.
Provider CLIs, SDKs, `n`, and `uv` can be updated in the home volume by agents.
Their Dockerfile version pins seed new volumes only; rebuilding does not
overwrite tools in an existing volume. The home also holds T3's downloaded
managed relay/provider helpers.

Useful commands:

```sh
docker compose exec t3 t3 connect status
docker compose restart t3
docker compose stop t3
```

Health reports the local HTTP listener, not end-to-end Connect reachability.
Check the client and container logs for tunnel failures. To relink, stop the
server, repeat `docker compose run --rm t3 connect link --headless`, then start
it again. Never share authorization codes or credential-bearing log output.

References: [T3 Connect](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md),
[Docker Compose service configuration](https://docs.docker.com/reference/compose-file/services/),
[user-space Node installs](https://github.com/tj/n#optional-environment-variables),
[Python management](https://docs.astral.sh/uv/guides/install-python/),
[Flutter installation](https://docs.flutter.dev/install/manual).

GitHub authentication: [GitHub CLI](https://cli.github.com/manual/gh_auth_login).
