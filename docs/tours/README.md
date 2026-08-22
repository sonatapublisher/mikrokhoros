# MikroKhoros hands-on tours

These tours drive the installed `khoros` executable as a human user. They build on
one isolated product home while covering a first world, an Object SDK package,
composable tools, and a selected live host folder.

Tours are reproducible exercises rather than the complete operating manual. Read
[Operating MikroKhoros](../human-guide.md) for the human/agent boundary, product
model, safety guidance, and ongoing administration; use the generated
[CLI reference](../cli-reference.md) when you need exact command syntax.

## Before starting

Install MikroKhoros by following the
[README installation instructions](../../README.md#install-khoros).
Return here once the executable is available.

Verify the executable is on `PATH`:

```bash
command -v khoros
khoros --help
```

Create a temporary product home on macOS or Linux:

```bash
export MIKROKHOROS_HOME="$(mktemp -d "${TMPDIR:-/tmp}/mikrokhoros-tour.XXXXXX")"
printf 'Tour data: %s\n' "$MIKROKHOROS_HOME"
```

In PowerShell on Windows:

```powershell
$env:MIKROKHOROS_HOME = Join-Path ([IO.Path]::GetTempPath()) `
  ("mikrokhoros-tour-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force $env:MIKROKHOROS_HOME | Out-Null
$env:MIKROKHOROS_HOME
```

Keep the same environment value for all four tours. It isolates configuration,
agents, Inventory, packages, credentials, console history, and managed worlds
from ordinary `~/.mikrokhoros` data. Removing this temporary directory later removes
only the tour state.

## Tour order

1. [Your first world](01-first-world.md), approximately 10 minutes.
2. [Install and deploy an object package](02-object-package.md), approximately 15 minutes.
3. [Compose printer, paper, and pencil](03-composable-tools.md), approximately 15 minutes.
4. [Expose a live host folder](04-live-user-workspace.md), approximately 20 minutes.

The primary examples use human-readable names. MikroKhoros resolves each unique name
to an exact runtime identity before execution. List output displays a unique short ID
when names are duplicated; either that prefix or the complete ID is accepted.

Interactive terminals use human presentation. For automation, select a stable machine
format explicitly:

```bash
khoros status --output yaml
khoros status --output json
```

## Useful recovery commands

```bash
khoros status
khoros doctor
khoros world show
khoros agent list
khoros inventory list
khoros world object list
```

- If a coordinate is occupied, inspect the destination and choose another coordinate,
  or retry an operation that supports `--auto-adapt`.
- If a selector is ambiguous, retry with one short ID shown in the error or list.
- If deployment is not ready, run `inventory show` and grant or configure only the
  missing requirement it reports.
- If a tour is interrupted, run `doctor`, inspect the relevant list, and continue from
  the first step whose result is absent. Persisted successful steps remain intact.
