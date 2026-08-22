# Tour 4: expose a live host folder

This tour binds one selected folder to a world-specific Inventory fork, deploys it as
a live container graph, and edits a projected text file with an ordinary pencil.
Agents see the mount alias and relative paths; the absolute host path remains in the
human management surface.

## 1. Prepare a dedicated folder

On macOS or Linux:

```bash
export TOUR_FOLDER="$(mktemp -d "${TMPDIR:-/tmp}/mikrokhoros-files.XXXXXX")"
printf 'Hello from the host.\n' > "$TOUR_FOLDER/welcome.txt"
```

In PowerShell:

```powershell
$env:TOUR_FOLDER = Join-Path ([IO.Path]::GetTempPath()) `
  ("mikrokhoros-files-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force $env:TOUR_FOLDER | Out-Null
Set-Content (Join-Path $env:TOUR_FOLDER "welcome.txt") "Hello from the host."
```

Use only this disposable folder for the writable tour mount.

## 2. Create a world-bound source

```bash
khoros inventory install builtin:user-workspace
khoros --world default-khoros inventory fork 'User Workspace' \
  --name 'Tour Workspace'
khoros inventory action run 'Tour Workspace' mount-add \
  --input name=tour-files \
  --input "path=$TOUR_FOLDER" \
  --input x=0 \
  --input y=0 \
  --input access=read-write \
  --input auto-adapt=false
khoros inventory capability grant 'Tour Workspace' user-machine
khoros inventory view show 'Tour Workspace' readiness
```

If readiness reports a missing grant or field, set exactly that requirement and run
the view again.

## 3. Deploy the live user-workspace object

```bash
khoros inventory deploy 'Tour Workspace' --at 8,0
khoros world object show 'Tour Workspace'
khoros world object view show 'Tour Workspace' mounts
```

The user-workspace object root is movable. Projected folders, files, and links are
anchored to their resource binding.

## 4. Enter the projection and edit the file

```bash
khoros shell agent \
  --action 'drop west' \
  --action 'move east 8' \
  --action 'container in' \
  --action 'container in' \
  --action 'move east 10'
khoros inventory deploy Pencil --to agent
khoros shell agent \
  --action 'backpack open' \
  --action pickup \
  --action 'backpack close' \
  --action 'move west 9' \
  --action 'object (append (-1) (0) ("Written from the world.\\n"))'
```

Verify the selected host file on macOS or Linux:

```bash
tail -n 3 "$TOUR_FOLDER/welcome.txt"
```

Or in PowerShell:

```powershell
Get-Content (Join-Path $env:TOUR_FOLDER "welcome.txt") -Tail 3
```

The pencil addressed a projected file object. The folder-bound service enforced the
captured capability, binding, relative path, access mode, entry type, and containment
before the write.

## 5. Verify replay safety

```bash
khoros doctor
khoros world object view show 'Tour Workspace' readiness
```

Restarting or inspecting MikroKhoros does not repeat the host-file write. The
world journal retains a bounded external-effect receipt while live content is
reconciled on the next relevant interaction.

Continue by reading the [Object SDK guide](../object-sdk.md), browsing
`khoros inventory package available`, or starting `khoros` to explore the adaptive
human console.
