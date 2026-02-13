# Devcontainer Layer Design

## Overview

A Spacemacs layer providing full VS Code-like devcontainer support. Thin wrapper
around the official `devcontainer` CLI with TRAMP-based container access.

## Approach

**Thin CLI Wrapper** — the `devcontainer` CLI handles all spec-level complexity
(parsing devcontainer.json, building images, features, lifecycle hooks, compose).
Elisp handles detection, TRAMP wiring, LSP configuration, and keybindings.

## Layer Structure

```
layers/+tools/devcontainer/
├── packages.el      — declare package dependencies
├── funcs.el         — core functions (CLI wrapper, TRAMP wiring, detection)
├── config.el        — defcustom variables, defaults
└── keybindings.el   — SPC d c prefix keybindings
```

Location chosen for future upstream PR to spacemacs/spacemacs.

## External Dependencies

- `@devcontainers/cli` — installed via `npm install -g @devcontainers/cli`
- Docker and/or Podman — auto-detected at runtime

## Elisp Dependencies (all already installed)

- `docker-tramp` — TRAMP method for docker containers
- `lsp-mode` — for remote LSP configuration
- `projectile` — for project detection hooks
- `json` (built-in) — for reading devcontainer.json metadata

No new MELPA packages needed.

## Core Functionality

### Container Lifecycle

All via `devcontainer` CLI, run as async processes with output in
`*devcontainer*` buffer:

| CLI Command         | Purpose                                  |
|---------------------|------------------------------------------|
| `devcontainer up`   | Build image (if needed) and start        |
| `devcontainer exec` | Run commands inside running container    |
| `devcontainer build`| Force rebuild the container image        |
| `devcontainer stop` | Stop the running container               |

### Project Detection

- Hook into `projectile-after-switch-project-hook`
- Check for `.devcontainer/devcontainer.json` or `.devcontainer.json`
- If found and container not running: prompt "Open in container? (y/n)"
- Per-project choices persisted to cache file

### TRAMP Connection

- Extract container name/ID from `devcontainer up --log-format json` output
- Construct TRAMP path: `/docker:<container-id>:/workspaces/<project>/`
- For Podman: `/podman:<container-id>:/workspaces/<project>/`
- Set `default-directory` to TRAMP path for the project
- All file operations, compilation, terminals go through the container

### Runtime Auto-Detection

- Check `executable-find` for docker and podman
- Prefer Docker if both available (configurable)
- Verify `devcontainer` CLI is available, warn if missing

## LSP & Terminal Integration

### LSP via TRAMP

- `lsp-mode` natively supports TRAMP paths — runs language servers on the
  remote side automatically
- No per-language configuration needed; container's toolchain is used
- Normal lsp-mode "server not found" flow if server missing in container

### DAP

- `dap-mode` connects to debug adapters inside the container via TRAMP
- No special wiring needed

### Terminals

- `SPC d c t` opens a terminal that execs into the container
- Integrates with existing multi-vterm setup
- Terminal inherits the container's environment

### Compilation

- `compile` / `projectile-compile-project` runs inside the container
  automatically when `default-directory` is a TRAMP path

## Keybindings

Prefix: `SPC d c` (mnemonic: devcontainer)

| Binding     | Command                  | Description                                    |
|-------------|--------------------------|------------------------------------------------|
| `SPC d c o` | `devcontainer-open`      | Build (if needed) & connect to devcontainer    |
| `SPC d c s` | `devcontainer-stop`      | Stop the running devcontainer                  |
| `SPC d c r` | `devcontainer-rebuild`   | Force rebuild and reconnect                    |
| `SPC d c t` | `devcontainer-terminal`  | Open a terminal inside the container           |
| `SPC d c l` | `devcontainer-log`       | Show the *devcontainer* output buffer          |
| `SPC d c d` | `devcontainer-disconnect`| Disconnect TRAMP without stopping container    |
| `SPC d c i` | `devcontainer-info`      | Show devcontainer status & metadata            |

## Configuration Variables

All `defcustom`:

| Variable                          | Default                              | Description                                  |
|-----------------------------------|--------------------------------------|----------------------------------------------|
| `devcontainer-cli-path`           | `(executable-find "devcontainer")`   | Path to devcontainer CLI                     |
| `devcontainer-docker-path`        | `(executable-find "docker")`         | Path to docker CLI                           |
| `devcontainer-podman-path`        | `(executable-find "podman")`         | Path to podman CLI                           |
| `devcontainer-preferred-runtime`  | `'auto`                              | `'auto`, `'docker`, or `'podman`             |
| `devcontainer-auto-detect`        | `t`                                  | Check for devcontainer.json on project switch|
| `devcontainer-prompt-to-open`     | `t`                                  | Prompt before opening                        |
| `devcontainer-cache-file`         | `~/.emacs.d/.cache/devcontainer-projects` | Where to persist per-project choices    |
