# Contributing to Dream Server

Thanks for building with us.

## Fast Path

If you want to add or extend services, start here:
- [docs/EXTENSIONS.md](docs/EXTENSIONS.md) — extending services (Docker containers, dashboards)
- [docs/INSTALLER-ARCHITECTURE.md](docs/INSTALLER-ARCHITECTURE.md) — modding the installer itself

That guide includes a practical "add a service in 30 minutes" path with templates and checks.

## Reporting Issues

Open an issue with:
- hardware details (GPU, RAM, OS)
- expected behavior
- actual behavior
- relevant logs (`docker compose logs`)

## Pull Requests

1. Fork and create a branch (`git checkout -b feature/my-change`)
2. Keep PR scope focused (one milestone-sized change)
3. Run validation locally
4. Submit PR with clear description, impact, and test evidence

## Contributor Validation Checklist

The fastest way to validate everything:
```bash
make gate    # lint + test + smoke + simulate
```

Or run individual steps:
```bash
make lint    # Shell syntax + Python compile checks
make test    # Tier map unit tests + installer contracts
make smoke   # Platform smoke tests
```

Full manual checklist:
```bash
# Shell/API checks
bash -n install.sh install-core.sh installers/lib/*.sh installers/phases/*.sh scripts/*.sh tests/*.sh 2>/dev/null || true
python3 -m py_compile dashboard-api/main.py dashboard-api/agent_monitor.py

# Unit tests
bash tests/test-tier-map.sh

# Integration/smoke checks
bash tests/integration-test.sh
bash tests/smoke/linux-amd.sh
bash tests/smoke/linux-nvidia.sh
bash tests/smoke/wsl-logic.sh
bash tests/smoke/macos-dispatch.sh
```

If your change touches dashboard frontend and Node is available:
```bash
cd dashboard
npm install
npm run lint
npm run build
```

## Current Priorities

These are the things we most need help with, in order of impact:

### 1. Runs on anything

Dream Server should work on every machine a developer might have. A student with a 4GB laptop and no GPU should be able to run it. So should someone with a 90GB Strix Halo workstation.

What this looks like:
- **New hardware tiers** — we have Tier 0 (4GB, no GPU) through Tier 4 (48GB+ VRAM) plus specialty tiers for Strix Halo and Intel Arc. If there's hardware we don't support, add a tier.
- **CPU-only inference** — llama.cpp handles this, but the installer flow, memory limits, and model selection all need to account for machines with no usable GPU.
- **Memory-constrained environments** — Docker compose overlays that reduce service reservations for low-RAM machines (see `docker-compose.tier0.yml` for the pattern).
- **ARM, Chromebooks, older GPUs** — anything people actually have. If it runs Docker and has 4GB of RAM, it should be on the table.

### 2. Clean installs

The installer should work first try. No manual fixups, no Googling error messages, no "just run it again." If someone hits a wall during install, that's a bug.

What this looks like:
- **Idempotent re-runs** — running the installer twice should not break anything. Existing secrets, configs, and data should be preserved.
- **Clear error messages** — when something fails, tell the user exactly what went wrong and what to do about it. No stack traces, no silent failures.
- **Preflight validation** — catch problems (wrong Docker version, insufficient disk, port conflicts) before the install starts, not halfway through.
- **Platform-specific edge cases** — WSL2 memory limits, macOS Homebrew paths, Windows Defender interference, Secure Boot blocking NVIDIA drivers. These are the things that make real installs fail.
- **Offline support** — pre-downloaded models, air-gapped environments, corporate firewalls. Not everyone has unrestricted internet.

### 3. Extensions and integrations

Dream Server is only as useful as what it connects to. A bare LLM server is a demo. An LLM server that plugs into your workflow tools, observability stack, and creative apps — that's a product.

What this looks like:
- **New service integrations** — wrap any Docker-based tool as a Dream Server extension with a manifest, compose file, and health check. See `extensions/services/` for examples.
- **API bridges** — connect Dream Server to external services (Slack, Discord, email, calendars, CRMs). n8n workflows are the easiest path.
- **Workflow templates** — pre-built n8n workflows that solve real problems (summarize emails, generate images from prompts, monitor RSS feeds).
- **Manifest quality** — every extension needs a valid manifest with health checks, dependency declarations, port contracts, and GPU backend compatibility. Run `dream audit` to validate.
- **Inter-service reliability** — services need to start in the right order, handle dependencies being temporarily down, and recover gracefully. The `compose.local.yaml` overlay pattern handles startup ordering.

### 4. Test coverage for real code paths

Tests should exercise code that exists and catch regressions that would break real users. We do not want tests for features that haven't been built yet.

What this looks like:
- **Installer integration tests** — run the actual installer phases in a container and verify the output. Not mocking the installer, actually running it.
- **Tier map validation** — every tier resolves to the correct model, GGUF file, URL, and context window. `tests/test-tier-map.sh` is the pattern.
- **Health check coverage** — every service has a health check and the health check actually verifies the service is working, not just that a port is open.
- **Extension contract tests** — manifests are valid, compose files parse, declared ports don't conflict, dependencies exist.
- **Platform smoke tests** — the installer doesn't crash on Linux, macOS, Windows, or WSL2. Even if we can't test full installs in CI, we can test that scripts parse and core functions return expected values.

### 5. Installer portability

macOS, Linux (Ubuntu, Debian, Arch, Fedora, NixOS), Windows (native PowerShell + WSL2). Every platform-specific bug fixed unblocks hundreds of users.

What this looks like:
- **POSIX compliance** — no GNU-only flags in scripts that run on macOS (BSD sed, BSD date, BSD grep all behave differently). Use the `_sed_i` helper and `_now_ms` for portable timestamps.
- **Package manager abstraction** — apt, dnf, pacman, brew, xbps are all supported. New distros need a case in the package manager detection.
- **Shell compatibility** — Bash 3.2 (macOS default) through Bash 5.x. No associative arrays in code that runs on macOS unless guarded by a Bash 4+ check.
- **Path handling** — Windows paths vs Unix paths, spaces in paths, symlinks, external drives. Use the `path-utils.sh` library.
- **Docker variations** — Docker Desktop, Docker Engine, Podman, Colima. Different socket paths, different compose plugin locations, different permission models.

If you want to tackle any of these, open an issue first so we can align on approach.

## What We'll Merge Fast

- Bug fixes with reproduction steps
- Tests for existing untested code paths
- Focused, single-concern PRs that do one thing well
- Platform support (new OS, new GPU vendor, new hardware tier)
- Security fixes with clear explanation of the vulnerability

## What Will Get Bounced Back

We've learned these patterns the hard way. Save yourself a review cycle:

- **Mega-PRs that bundle unrelated changes.** One PR = one concern. A bug fix + a feature + a refactor = three PRs.
- **Code that wasn't run.** If your function is called but never defined, or your shell variable won't expand in that context, we'll catch it. Run your code locally before submitting.
- **Breaking changes without migration.** Changing port defaults, tightening schemas, broadening volume mounts — these all need migration notes and maintainer discussion first. Open an issue before the PR.
- **Tests for features that don't exist.** A test suite that skip()'s every check because the underlying feature isn't implemented gives false confidence. Write the tests alongside the feature.
- **Formatting-only PRs.** We appreciate clean code, but a PR that only runs black/prettier across the codebase creates merge conflicts for everyone else and adds no functionality.
- **Over-engineering.** If the problem is simple, the solution should be simple. Don't add configuration, abstraction layers, or feature flags for one-time operations.

## Style

- Bash: `set -euo pipefail`, quote your variables, use `shellcheck`
- Python: match the style of the file you're editing, no reformatting unrelated code
- YAML/JSON: stable keys, minimal noise, no tabs
- Docs: concrete commands and compatibility notes
- Commits: short imperative subject line, explain *why* not *what* in the body

## Questions

Open an issue or start a [GitHub Discussion](https://github.com/Light-Heart-Labs/DreamServer/discussions). Include enough context to reproduce the problem quickly. We're happy to help you figure out the right approach before you write code — it's much faster than reviewing a PR that needs a redesign.
