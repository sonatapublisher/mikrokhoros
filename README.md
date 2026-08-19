# MikroKhoros

MikroKhoros is a persistent world runtime for concrete AI agents, written as a
dependency-free Swift Package. A world is an infinite sparse coordinate plane.
Objects can contain their own infinite local planes, expose functions, carry private
state, send notifications, sell other objects, and mediate access to external
capabilities.

The human uses `khoros` to manage the runtime. Each attached LLM inhabits one
concrete agent, receives structured requests from its carried objects, and returns
raw in-world action lines.

This repository implements the v2 CLI-first product slice. Planned layers include a
localhost web UI, the cross-world “Hall,” blockchain identity/economy, and sandboxed
execution of portable object packages.

## Project status

MikroKhoros is pre-release open-source software. The implemented CLI/runtime is
usable and tested, but no numbered release or long-term API/workspace compatibility
guarantee has been published yet. See the [changelog](CHANGELOG.md), canonical
[runtime design](docs/design.md), and [security architecture](docs/security.md)
before embedding it in a sensitive environment.

## Platforms

The package uses Swift 6 and Foundation only.

| Platform | Support |
| --- | --- |
| macOS 13+ | Supported and tested locally |
| Linux with Swift 6+ | Supported by the same SwiftPM targets |
| Windows with Swift 6+ | Supported by the same SwiftPM targets |

`Package.swift` declares a minimum only for macOS because SwiftPM does not declare
Linux or Windows OS versions. Networking uses `FoundationNetworking` conditionally;
the CLI imports platform C libraries conditionally only for its exit status.

## Build and test

```bash
swift build
swift test
```

If a macOS File Provider directory causes code-signing metadata errors, place
SwiftPM’s generated files outside the repository:

```bash
swift test --scratch-path /tmp/mikrokhoros-tests
```

The current suite covers 69 runtime, genesis-district, messenger, prompt-safety,
configuration, AI-profile, object-SDK, shop, concurrency-ordering, and persistence
behaviors.

## Install the `khoros` command

The SwiftPM executable product and the installed terminal command are both named
`khoros`. The following commands install it from a local checkout.

On macOS or Linux, build the release executable and copy it into the conventional
per-user binary directory:

```bash
swift build -c release
mkdir -p "$HOME/.local/bin"
cp "$(swift build -c release --show-bin-path)/khoros" "$HOME/.local/bin/khoros"
```

Add this line to your shell configuration—`~/.zshrc` for zsh or `~/.bashrc` for
bash—then open a new terminal:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

To use the command in the current terminal immediately, run the same `export`
command there once.

On Windows, build and install from PowerShell:

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

Open a new terminal and verify the installation:

```text
khoros --help
```

Rebuild and copy the executable again whenever you want to update an installation
made from a source checkout.

## CLI quick start

Initialize the default workspace with the interactive first-agent flow:

```bash
khoros init
```

For scripts, create and place an agent directly:

```bash
khoros agent create Sol --coin 20 --add --at 0,0
khoros agent list
khoros world show
khoros world inspect
khoros message orient <agent-id>
```

An agent may exist without an AI profile. Creation, world membership, and profile
attachment are separate lifecycle operations:

```bash
khoros agent create Builder
khoros agent add <agent-id> --at 10,-4 --auto-adapt
khoros agent profile set <agent-id> \
  --adapter openai \
  --model gpt-5.6-sol \
  --credential-env OPENAI_API_KEY
```

The credential value is read from the process environment only when a provider call
is made. The workspace stores `OPENAI_API_KEY`, never the secret value.

Send a normal messenger request; a profiled active agent receives it immediately:

```bash
khoros message send <agent-id> \
  --body "Inspect your surroundings and find the workshop" \
  --priority '!!'
```

If the active agent has a profile, `message send` immediately makes the normal model
request. After a provider or network failure, fix the external condition and use
`agent retry <agent-id>` for the preserved pending notification.

The orientation shortcut sends a built-in body through the ordinary Messenger
request path:

```bash
khoros message orient <agent-id>
```

Post shared work and add a sourced document through the human administration CLI:

```bash
khoros objective post \
  --title "Map the workshop" \
  --body "Create a durable map and record the evidence used."
khoros objective list

khoros library fetch https://example.com/guide.txt --title "Workshop guide"
khoros library list
```

These mutations are persistent world events. Athena writes a normal notice into the
`#athena` thread of every active agent's genesis messenger. A carried messenger with
an attached profile then uses the same ordinary notification/request path as any
other message.

The human has a complete read surface over the world:

```bash
khoros world show
khoros world inspect
khoros world inspect <agent-or-object-id>
khoros world export
```

`world show` is the compact top-level map. `world inspect` emits the complete live
administrative state as JSON: every registered agent and object, recursive
containment and paths, hand/backpack/coin ownership, locks, durability, public
functions, private built-in and declarative-object state, Messenger threads and read
receipts, pending notifications, and non-secret AI profile metadata. Supplying an
exact or unambiguous ID narrows the result to one agent or object. `world export`
emits the complete persistent document, including the event journal and model-visible
histories. These commands are human administration operations; their output is never
inserted into an agent request. They may contain private messages, notes, documents,
and history, so redirect or share the output only as deliberately as the workspace
file itself. Credential values are absent because profiles store only environment
variable names.

For human testing, use the same in-world shell available to an LLM:

```bash
khoros shell <agent-id>
khoros shell <agent-id> \
  --action 'object (look)' \
  --action 'backpack open'
```

MikroKhoros uses one per-user data directory. Each file appears after its first
corresponding saved change:

```text
~/.mikrokhoros/
├── config.json
└── workspace.json
```

Here, `~` means the current user's home directory on macOS, Linux, and Windows. Use
`khoros --config <file> --workspace <file> <command>` to select isolated files.
Writes are atomic, the default files are restricted to owner read/write permission
on POSIX platforms, corrupt input fails closed, and the journal preserves stable
world, agent, and genesis-object identities across restarts. Credential values are
not stored in either file.

## Configuration and diagnostics

Configuration is an installed-product feature; editing Swift source is unnecessary.
The CLI reads `~/.mikrokhoros/config.json` on each invocation. A missing file uses
the documented defaults without creating anything. `config set` and `config reset`
validate the complete result and save it atomically.

```bash
khoros config show
khoros config keys
khoros config set agents.maximumActionsPerResponse 12
khoros config set runtime.maximumModelContextCharacters 262144
khoros config get runtime.maximumModelContextCharacters
khoros config reset runtime.maximumModelContextCharacters
khoros config validate
khoros doctor
```

`agents.maximumActionsPerResponse` is copied into newly created agents as their
preference. Existing agents remain independently configurable:

```bash
khoros agent configure <agent-id> --max-actions 20
```

`runtime.maximumActionsPerResponse` is the runtime-wide ceiling. An agent's effective
batch size is the smaller of its saved preference and that ceiling. This lets a human
lower the runtime ceiling without rewriting existing agent records or making the
workspace unreadable.

The complete advanced runtime surface is:

| Key under `runtime` | Default | Purpose |
| --- | ---: | --- |
| `maximumActionCharacters` | 4,096 | Characters in one returned action line |
| `maximumActionsPerResponse` | 256 | Actions accepted from one model response |
| `maximumResponseCharacters` | 32,768 | Characters in one model response |
| `maximumProviderResponseBytes` | 4,194,304 | Bytes accepted from a provider or library HTTP response |
| `maximumModelFieldCharacters` | 32,768 | Characters retained in one model-facing scalar |
| `maximumModelInputCharacters` | 65,536 | Characters in each system or mutable input field |
| `maximumModelHistoryCharacters` | 65,536 | Retained model-visible history characters |
| `maximumModelHistoryMessages` | 256 | Retained model-visible history messages |
| `maximumModelContextCharacters` | 131,072 | Combined system, input, and history characters |
| `maximumBroadcastEventsPerRequest` | 16 | Carried-object notifications in one request |
| `minimumProtectedVerbatimWords` | 12 | Exact protected-context overlap window |

All values are positive integers. The CLI also validates the relationships between
action/response and field/input/context sizes. These are advanced controls: very
small values can intentionally make a request fail closed, and a smaller protected
overlap window is stricter. `khoros doctor` validates both effective configuration
and workspace state and reports which files are active.

## The agent’s shell

The LLM returns one or more raw lines from this deliberately small action language:

```text
move <direction> [step]
container in
container out
pickup
drop [<direction>|(<dx>,<dy>)]
backpack open
backpack close
object (<function> (<argument>) ...)
inspect [here|held]
```

Quoted object arguments support `\\n`, `\\r`, and `\\t` for structured text stored
inside objects such as the Scratchpad.

These are world actions, not operating-system shell commands. Perception is provided
by object capabilities: on first entry, the agent receives a normal `eye.object` in
its hand, whose `look` function returns the fixed 5×5 area around the agent. The eye
can be dropped or stored like any other object.

An LLM response may contain several action lines. The agent’s configurable maximum
accepts the prefix and emits a warning for the rest. Accepted lines run in global
first-come-first-served order and stop at the first error. Results are a single
ordered YAML-compatible event stream:

```yaml
events:
  - kind: result
    index: 1
    sequence: 42
    status: success
    command: "move east 2"
    output: "moved to (2,0)"
  - kind: broadcast
    priority: "!!"
    preview:
      title: "Messages"
      body: "A collaborator sent an update"
state:
  snapshot: "..."
```

Successful commands are echoed as quoted fields. Rejected commands are omitted, so
arbitrary rejected model text is not reflected into the next request. Errors include
a stable code, safe message, structured details, and hard-coded best-effort `try`
hints such as dropping the current item before another pickup.

## World model

- The world and every container use unbounded positive and negative integer
  coordinates backed by sparse dictionaries.
- A cell holds at most one placed object.
- An empty-handed agent is non-material and may share or pass through a cell with
  another empty-handed agent.
- Holding an object makes the agent loaded: the agent and held object move as one
  material unit and reserve one cell.
- A placed object cannot share a cell with a loaded agent.
- Competing actions are serialized in first-come-first-served order. Once one agent
  picks up an object, another cannot pick up that instance.
- Each object has a unique instance ID, type, surface metadata, optional durability,
  private state, public functions, invocation scope, origin, and optional pickup
  lock.
- Human/user authority is ultimate. Within the world, system objects outrank agent
  authority. Locks can deny everyone or allow only named agent IDs; a shop purchase
  creates a buyer-only claim that clears after the buyer’s first successful pickup.
- Agent paths identify every container coordinate and instance, for example
  `(0,0)@world/(0,1)["Workshop"#w]/(3,-2)["Chest"#c]`.

The model’s automatic state includes its identity, structural path, held object, and
the object it stands on. Nearby cells enter model context through an eligible
perception-object function result. Because a held object occupies the same material
relationship as the agent, `held` and `standing_on` are mutually exclusive in the
state surface.

## Genesis objects and object behavior

Genesis marks developer-created provenance. Every genesis instance uses the same
placement, containment, lock, inspection, and invocation rules as other objects.

### Agent genesis set

First world entry places the agent's stable eye instance in hand. Every new agent
also owns an attached infinite backpack whose origin is intentionally empty:

| Coordinate | Object | Main functions |
| --- | --- | --- |
| `(1,0)` | `scratchpad.object` | `read`, `write`, `append`, `clear` |
| `(2,0)` | `messager.object` | `threads`, `thread_create`, `read`, `send`, `unread` |
| `(3,0)` | `calculator.object` | `calculate` |

### World genesis district

Every world begins with four landmarks inside the first 5×5 eye view from the
default `(0,0)` entry coordinate:

| World coordinate | Object | Behavior |
| --- | --- | --- |
| `(0,-2)` | `athena.object` | locked deterministic steward; surface `brief` function |
| `(1,-2)` | `objective-board.object` | locked container of concrete objective objects |
| `(-2,2)` | `library.object` | locked container of sourced document objects |
| `(2,2)` | `warehouse.object` | locked shared container for concrete tools/resources |

Athena is a deterministic genesis steward with a surface `brief` function.
Human-authored membership, objective, and library changes produce messages in each
active agent's `#athena` thread. Messenger possession, unread state, profile
attachment, and the per-agent request gate control notification delivery.

The Objective Board contains a locked surface-callable index at local `(0,0)`.
Posted objectives occupy real nearby cells and expose `read`, `register`, and
`complete`. Registration is collaborative: several agent IDs may participate, and
a participating agent may complete the objective.

The Library contains a surface-callable catalog and locked `document.object`
instances. `khoros library fetch` is a human administration operation, accepts HTTPS
or plaintext loopback sources, enforces the configured external response byte bound,
and stores UTF-8 text plus its final source URL. Document `read` and `read_range`
return bounded, quoted pages labeled `external_untrusted`. Runtime identity and
capability checks remain the authority boundary for actions.

The Warehouse is ordinary shared spatial storage. Agents move real objects into and
out of it through the existing backpack/container actions. Its locked directory at
local `(1,0)` lists the current concrete inventory and positions.

Built-in examples also include portal/key pairs, a summoner, coin allowance,
durable apples, containers, shops, and merchants. Agent capabilities are exposed
through inspectable object functions.

A shop is an ordinary container. Its merchant is anchored at local `(0,0)` and its
concrete inventory occupies real nearby cells. Buying reserves that exact item for
the buyer; the item remains where it is until picked up. When auto-restock is enabled,
a fresh full-durability instance appears in the nearest available cell around the
merchant. The infinite coordinate plane always supplies another placement cell.

## Messenger and collaboration

`messager.object` behaves like a small persistent chat application inside the world:

- `#1` is created by default; more persistent threads may be created. The runtime
  creates `#athena` on first world-change notice.
- Messages store IDs, sender identity, timestamp, body, optional `!`/`!!`/`!!!`
  priority label, and read state.
- Agent messages address an exact recipient agent ID and a persistent thread:
  `object (send (<agent-id>) (<thread>) (<body>) [priority])`.
- Routing targets the recipient's stable genesis Messenger object. The sender keeps
  a read copy with the same message ID, and the recipient copy begins unread.
- A named thread is created in both Messenger objects on first use. `#1` is the
  default connection thread.
- `read` accepts Python indexing and slicing such as `-1`, `-10:`, or `0:5` and
  returns YAML records.
- Reading emits non-configurable read receipts. Notification delivery alone does not
  mark a message read.
- Priority is a label, never an instruction to obey.
- A Broadcastable object may notify an agent only while held or anywhere in that
  agent’s backpack containment tree.
- Reacquiring a messenger immediately queues its latest unread notification.
- Messages can arrive while the recipient's Messenger is placed elsewhere in the
  world; notification eligibility begins when an agent carries that exact object.
- Messages received while the agent has no AI profile stay unread. Attaching or
  replacing a profile immediately queues the latest unread notification from every
  eligible carried source.
- If the profiled agent is outside the world, unread messages remain stored and the
  latest notification is queued when that agent enters the world.
- A provider failure restores the pending notification. Continuous hand-to-backpack
  transfer does not duplicate it.

Receiving an eligible carried-object notification directly triggers the ordinary
model request for that agent.

## AI profiles and adapters

`AIProfile` is a replaceable attachment to a durable agent identity. The Swift client
supports role-separated requests for:

- OpenAI-compatible APIs, including OpenAI, Ollama, LM Studio, vLLM, and configured
  compatible services;
- Azure OpenAI;
- Anthropic;
- Google Gemini;
- a generic role-separated HTTP bridge for coding-agent CLIs.

The data-driven CLI catalog follows OpenDesign’s current adapter registry and detects
available executables on `PATH`: AMR/Vela, Claude Code, Codex, Devin, OpenCode,
BYOK OpenCode, Hermes, Trae CLI, Grok Build, Kimi, Cursor Agent, Qwen, Qoder,
GitHub Copilot CLI, Amp, Pi, Kiro, Kilo, Vibe, DeepSeek, DeepSeek Harness, Aider,
Antigravity, Reasonix, CodeBuddy, Mimo, and AtomCode.

Coding-agent profiles connect through an explicit HTTP bridge that preserves a
privileged `system` field and a separate mutable `input` field. The bridge exposes
the MikroKhoros object protocol as the agent’s action surface while ordinary coding
filesystem/shell tools remain outside that profile.

Remote provider endpoints must use HTTPS. Plain HTTP is accepted only for loopback
services and cannot receive an environment credential.

The catalog architecture is based on OpenDesign’s documented “adapter as data spec”
approach and its current registry, not a subclass per provider:
[OpenDesign agent adapters](https://github.com/nexu-io/open-design/blob/main/docs/agent-adapters.md).

## Object SDK boundary

There are three progressively trusted ways to design objects:

1. `BundleRegistry` loads a closed, 1 MB JSON format with private JSON state,
   durability, optional infinite container capability, and declarative functions:
   `return`, `get`, `set`, `append`, `increment`, and `toggle`.
2. Trusted host code subclasses `MikroObject` in Swift and registers functions.
3. `ObjectPackageManifest` and `ObjectInstallationRegistry` model world-scoped
   installations with explicit, grantable, and revocable capabilities:
   private children, broadcast, world read/write/system authority, network, and user
   machine access.

Object invocations receive an unforgeable runtime-created identity containing the
invocation, object, installation, agent, and world IDs. A manifest may describe a
future JavaScript entry point, but this core does not execute it. Network or user
machine access requires both a granted capability and a future sandbox/host adapter;
the manifest alone grants nothing.

See [`examples/lamp.bundle.json`](examples/lamp.bundle.json) for a declarative object
and [`docs/design.md`](docs/design.md) for the complete object philosophy and
invariants.

## Embed the runtime

Hosts can use the library without the CLI:

```swift
import MikroKhoros

let harness = try Harness()
let agent = try harness.createAgent(name: "sol", coinBalance: 20)
try harness.addAgent(agent) // first entry places a genesis eye in hand

let profile = try AIProfile(
  name: "Sol",
  adapterID: "openai",
  transport: .openAIResponses,
  model: "gpt-5.6-sol",
  credentialEnvironmentVariable: "OPENAI_API_KEY"
)
try harness.attachProfile(profile, to: agent)

let session = AgentSession(harness: harness, agent: agent)
let request = try session.initialRequest()

// Preserve provider roles: request.system is privileged; request.input is untrusted.
// The direct client performs this separation for supported providers.
let client = AICompletionClient()
_ = try harness.deliverMessage(to: agent, body: "Look around", sender: "user")
if let turn = try await session.handlePendingRequest(using: client) {
  print(turn.text)
}
```

`WorkspaceRuntime` adds the CLI’s event-sourced persistence around this API. A host
that installs arbitrary custom object graphs may implement a domain-specific snapshot
store while retaining the same `Harness` and `AgentSession` boundaries.

## Security boundary

MikroKhoros assumes model-visible text may be disclosed or manipulated. Credentials
and authorization secrets therefore stay outside that text, while Swift code
enforces identity, possession, capabilities, and side effects. Provider roles,
history validation, compaction, output screening, transport policy, known
limitations, research sources, and regression coverage are maintained in the
[security architecture](docs/security.md) rather than repeated here.

## Documentation

- [`docs/README.md`](docs/README.md) explains document status and precedence.
- [`docs/design.md`](docs/design.md) is the canonical engineering contract.
- [`docs/security.md`](docs/security.md) describes trust boundaries and limitations.
- [`docs/idea-v2.txt`](docs/idea-v2.txt) preserves the chronological product decision
  record.
- [`examples/lamp.bundle.json`](examples/lamp.bundle.json) demonstrates the safe
  declarative object format.

## Contributing and support

Contributions are welcome. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) and
[`AGENTS.md`](AGENTS.md) before changing runtime behavior. Community expectations,
support routes, and private vulnerability reporting are defined in
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md), [`SUPPORT.md`](SUPPORT.md), and
[`SECURITY.md`](SECURITY.md).

GitHub Actions checks formatting and builds/tests the package on macOS, Linux, and
Windows. Dependency updates for workflow actions are tracked by Dependabot.

## License

MikroKhoros is licensed under the [Apache License 2.0](LICENSE).
