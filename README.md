<h1>
  <img alt="MikroKhoros logo" src="./assets/mikrokhoros-logo.png" width="70" valign="middle">
  &nbsp;MikroKhoros
</h1>

[![CI](https://github.com/sonatapublisher/mikrokhoros/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/sonatapublisher/mikrokhoros/actions/workflows/ci.yml)
[![Swift 6.1](https://img.shields.io/badge/Swift-6.1-F05138)](https://www.swift.org/)
[![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#platforms)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

**A persistent object world where AI agents learn through action, consequence, and
experience.**

*MikroKhoros* combines Ancient Greek *mikrós* (“small”) and *khōros* (“place”): a
small, concrete place for agents and objects.

MikroKhoros is a Swift 6 runtime and CLI for persistent object worlds on macOS,
Linux, and Windows. An attached LLM supplies cognition for a concrete agent. The
agent observes its setting, uses a small bounded action language and object
interfaces, produces validated state transitions, and carries permitted history into
future decisions. Its dependency-free domain model uses `swift-crypto` 4.3.1 for
local Ed25519 and SHA-256 integrity mechanisms.

<img src="https://github.com/sonatapublisher/mikrokhoros/raw/refs/heads/main/assets/mikrokhoros-world-map.png" alt="Concept illustration of a persistent world with connected facilities, neighborhoods, cultivated areas, and a harbor." width="100%" />

*A persistent world gives locality, facilities, resources, and shared paths a
concrete structure.*

## The agent loop

MikroKhoros provides partial observation, explicit authority, real preconditions,
persistent state, and recoverable consequences.

```text
observation → plan → bounded action → verified state transition
            → next observation → memory and adaptation
```

Small functional worlds make this loop usable for longer work: agents understand a
setting, meet its preconditions, verify outcomes, recover from errors, and continue.
The runtime records replayable trajectories from authoritative world state.

## Product model

```text
Object SDK → versioned object package → user-owned Inventory source → independent world object
```

Objects carry identity, state, lifecycle, relationships, authority, and history.
Packages define reusable behavior. Inventory sources hold user-owned, configurable
deployment sources outside worlds. Deployments create concrete world objects with
their own placement, state, capability surface, and lineage; later Inventory edits
shape future copies while deployed objects preserve their captured state.

Spatial structure expresses locality, possession, containment, shared resources, and
access. Nested containers and material occupancy make those relationships visible to
agents and enforceable by the runtime.

<img src="https://github.com/sonatapublisher/mikrokhoros/raw/refs/heads/main/assets/mikrokhoros-amphitheatre.png" alt="Concept illustration of an amphitheater showing distinct audience, stage, and arena spaces." width="100%" />

*Objects, places, and access boundaries make an agent’s current situation legible.*

## Runtime surfaces

An LLM supplies cognition for one agent. The human console schedules administrative
commands; `khoros shell <agent-selector>` accepts bounded in-world actions and never
becomes an operating-system shell. The runtime resolves exact identities and governs
capabilities, possession, placement, locks, permissions, persistence, and effect
replay.

## Available today

- Persistent sparse worlds with nested containers, material occupancy, structural
  paths, and world-local history.
- User-global agents with explicit world assignment and replaceable AI profiles.
- Declarative Object Packages, the Object SDK, typed configuration, write-only
  credentials, capability grants, folders, world-bound forks, and host bridges.
- Independent replayable deployments, exact object management, listeners, reports,
  Marketplace restocking, and explicit copy deletion.
- Per-agent equipment and first-party workspace, pencil, printer, paper, Messenger,
  Scratchpad, calculator, and Eye objects.
- Native Wallets, four holdings, recursive bearer property rights, and signed local
  credit records for resource, property, and custody interactions within a world.
- Native management surfaces for Wallet, Messenger, and Objective Board.
- Bare worlds by default and the trusted `default-khoros` template, which composes
  Athena, Objective Board, Library, Warehouse, and Marketplace from five independent
  Inventory sources.

## Current scope

The product is CLI-first. `default-khoros` resolves facilities from exact template
lineage, and agent equipment follows its own lifecycle.

World schema 7, AgentStore schema 3, and administrative snapshot schema 2 define
the current persistence line. The CLI accepts these current formats only and provides
no automatic migration or legacy import for Coin, single-hand, or other historical
files.

Planned layers include `khoros web`, a localhost browser interface for the same
human-management contracts; the Hall; cross-world networking; and network or
blockchain settlement. See the [browser UI specification](docs/ui-design-draft.txt)
and [view and command-coverage brief](docs/design-v2.txt).

## Platforms

| Platform | Support |
| --- | --- |
| macOS 13+ | Supported |
| Linux with Swift 6+ | Supported |
| Windows with Swift 6+ | Supported |

`Package.swift` declares the macOS minimum. SwiftPM does not express Linux or
Windows OS versions. GitHub Actions builds and tests the supported platform matrix.

## Install `khoros`

### macOS and Linux

From a checkout:

```bash
make install
```

The installer builds a release executable and copies it to `~/.local/bin/khoros`.
Set `KHOROS_INSTALL_ROOT` to choose another prefix. `make uninstall` removes only
the executable and preserves product data.

Add the per-user binary directory to your shell. For zsh, place this line in
`~/.zshrc`; for bash, place it in `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Open a new terminal, or set the value in the current one, then verify:

```bash
khoros --help
```

### Windows

From PowerShell:

```powershell
swift build -c release
$bin = Join-Path $env:LOCALAPPDATA "MikroKhoros\bin"
New-Item -ItemType Directory -Force -Path $bin | Out-Null
$release = swift build -c release --show-bin-path
Copy-Item (Join-Path $release "khoros.exe") (Join-Path $bin "khoros.exe") -Force
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ";") -notcontains $bin) {
  $nextPath = if ($userPath) { "$userPath;$bin" } else { $bin }
  [Environment]::SetEnvironmentVariable("Path", $nextPath, "User")
}
```

Open a new PowerShell window and run `khoros --help`. For a guided first path after
installation, read [Operating MikroKhoros](docs/human-guide.md) or begin the
[hands-on tours](docs/tours/README.md).

## Choose your path

| If you want to… | Start here |
| --- | --- |
| Install MikroKhoros | [Installation instructions](#install-khoros) |
| Understand the operating model or administer MikroKhoros | [Operating MikroKhoros](docs/human-guide.md) |
| Follow isolated, reproducible exercises | [Hands-on tours](docs/tours/README.md) |
| Find exact command syntax and options | [Generated CLI reference](docs/cli-reference.md) |
| Build an object package or runtime adapter | [Object SDK guide](docs/object-sdk.md) |
| Review the implemented runtime contract | [Canonical design](docs/design.md) |
| Review trust boundaries, controls, and limits | [Security architecture](docs/security.md) |
| Build, test, or contribute to the repository | [Contributing guide](CONTRIBUTING.md) |

The [documentation index](docs/README.md) routes each audience through the active
documents and keeps historical provenance separate from current product behavior.

## Status and license

MikroKhoros is pre-release software. World-document and public SDK compatibility
become stable with a future numbered release. The project is licensed under
[Apache License 2.0](LICENSE); `swift-crypto` attribution is recorded in
[NOTICE](NOTICE).
