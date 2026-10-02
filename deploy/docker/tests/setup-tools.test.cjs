const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { test } = require("node:test");

function fixture(t, installed = []) {
  const root = fs.mkdtempSync(path.join(os.homedir(), "setup-test-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const home = path.join(root, "home");
  const bin = path.join(root, "bin");
  fs.mkdirSync(path.join(home, ".local/bin"), { recursive: true });
  fs.mkdirSync(bin);
  fs.writeFileSync(path.join(home, "sentinel"), "existing data");
  const cli = `#!/bin/bash
echo "$(basename "$0") $*" >> "$HOME/calls"
if [[ "$*" == 'login --with-api-key' ]]; then
  key=$(cat)
  [[ "$key" == 'synthetic-test-key' ]] || exit 1
  echo api-key-received >> "$HOME/calls"
fi
if [[ "$(basename "$0")" == "$FAIL_TOOL" ]]; then exit 1; fi
`;
  const write = (file, body) => fs.writeFileSync(file, body, { mode: 0o755 });
  for (const tool of installed) write(path.join(home, ".local/bin", tool), cli);
  fs.writeFileSync(path.join(root, "cli"), cli);
  write(
    path.join(bin, "install-forge-cli"),
    `#!/bin/bash
echo "install $*" >> "$HOME/calls"
cp "$FIXTURE/cli" "$HOME/.local/bin/$1"
chmod +x "$HOME/.local/bin/$1"
`,
  );
  write(
    path.join(bin, "npm"),
    `#!/bin/bash
echo "npm $*" >> "$HOME/calls"
case "$*" in
  *@openai/codex@*) tool=codex ;;
  *@anthropic-ai/claude-code@*) tool=claude ;;
  *opencode-ai@*) tool=opencode ;;
  *) exit 1 ;;
esac
cp "$FIXTURE/cli" "$HOME/.local/bin/$tool"
chmod +x "$HOME/.local/bin/$tool"
`,
  );
  return (input, extra = {}) => {
    const result = spawnSync("bash", [path.join(__dirname, "../setup-tools.sh")], {
      input,
      encoding: "utf8",
      timeout: 5000,
      env: {
        ...process.env,
        HOME: home,
        FIXTURE: root,
        PATH: `${bin}:/usr/bin:/bin`,
        GH_VERSION: "2.102.0",
        CODEX_VERSION: "0.160.0",
        CLAUDE_VERSION: "2.1.287",
        OPENCODE_VERSION: "1.18.34",
        FAIL_TOOL: "",
        ...extra,
      },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(path.join(home, "sentinel"), "utf8"), "existing data");
    const log = path.join(home, "calls");
    return { ...result, calls: fs.existsSync(log) ? fs.readFileSync(log, "utf8") : "" };
  };
}

test("first setup installs selected tools and rerun reauthenticates without reinstalling", (t) => {
  const run = fixture(t);
  const first = run("a\n1\n1\n2\nq\n");
  assert.match(first.calls, /install gh 2\.102\.0/);
  assert.match(first.calls, /--allow-scripts=@openai\/codex @openai\/codex@0\.160\.0/);
  assert.match(first.calls, /claude auth login --console/);
  assert.match(first.calls, /codex login --device-auth/);
  assert.match(first.calls, /opencode auth login/);
  assert.match(first.calls, /gh auth setup-git --hostname github.com/);
  const second = run("1 2\n1\n1\nq\n");
  assert.equal(second.calls.split("install gh").length, 2);
  assert.equal(second.calls.split("codex login --device-auth").length, 3);
});

test("status, version updates, logout and invalid selection", (t) => {
  const run = fixture(t, ["gh", "codex", "claude", "opencode"]);
  const result = run("invalid\na\n2\n2\n3\n\n4\n4\nq\n");
  assert.match(result.stdout, /Select numbers/);
  assert.match(result.calls, /codex login status/);
  assert.match(result.calls, /claude auth status --text/);
  assert.match(result.calls, /opencode auth list/);
  assert.match(result.calls, /@openai\/codex@latest/);
  assert.match(result.calls, /opencode auth logout/);
});

test("failed authentication allows remaining tools and retry; EOF exits", (t) => {
  const run = fixture(t, ["gh", "codex"]);
  const result = run("1 2\n1\n1\nq\n", { FAIL_TOOL: "gh" });
  assert.match(result.stderr, /GitHub CLI did not complete/);
  assert.match(result.calls, /codex login --device-auth/);
  assert.doesNotMatch(result.calls, /gh auth setup-git/);
  run("");
});

test("API key is sent through stdin without appearing in command arguments or output", (t) => {
  const run = fixture(t, ["codex"]);
  const result = run("2\n1\n2\nsynthetic-test-key\nq\n");
  assert.match(result.calls, /api-key-received/);
  assert.doesNotMatch(result.calls + result.stdout + result.stderr, /synthetic-test-key/);
});
