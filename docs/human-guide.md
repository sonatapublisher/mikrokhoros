# Operating mikrokhoros

mikrokhoros is operated by a human through the local `khoros` CLI or the native
mikrokhoros Web interface. This guide explains the durable operating model, the
safety boundaries around it, and where to find the right kind of detail. It is not a
replacement for the generated command reference or the hands-on tours.

## Purpose and reading paths

Use this guide when you need to understand what a human can administer, how the
different product layers relate, or which surface is appropriate for a task.

| Need | Best document |
| --- | --- |
| A product overview and current scope | [Repository README](../README.md) |
| A repeatable first-world, package, tool, or host-folder exercise | [Hands-on tours](tours/README.md) |
| Exact command paths, arguments, and options | [Generated CLI reference](cli-reference.md) |
| Object-package and adapter development | [Object SDK guide](object-sdk.md) |
| Normative runtime behavior and persistence rules | [Canonical design](design.md) |
| Threat model, authority checks, and security limits | [Security architecture](security.md) |
| Repository setup and contribution checks | [Contributing guide](../CONTRIBUTING.md) |

The CLI and `khoros web` are complete local human interfaces over the same native
service and runtime layers. The browser is organized around the product
domains: World, Agent Manager, Inventory, Packages, Templates, and fixed Settings.
Searchable Help contains the full command reference, while contextual action sheets
run the exact operation selected from a domain view. The Hall, cross-world
networking, network Wallets, external settlement, and blockchain consensus are
outside both local interfaces.

## Operating model

mikrokhoros keeps the human administrative surface separate from the world-facing
agent surface:

- A human owns and administers user-global agents, packages, Inventory sources,
  credentials, configuration, worlds, reports, and template setup.
- A world is an independent persistence boundary containing concrete agents and
  objects. Ordinary worlds are bare infinite containers.
- An attached LLM supplies the cognition of one registered agent. It proposes only
  bounded in-world actions; it cannot select another world, grant a capability, use
  the human-management surface, or authorize an external effect.
- An Object SDK produces a versioned object package. Installing the package makes it
  available to create user-owned Inventory sources. An Inventory source can deploy
  independent concrete world objects or create future restock copies.

An Inventory source is outside every world. It has configuration, credential-version
handles, capability grants, management actions and views, a revision, and optional
folder/world-binding metadata. It does not have a coordinate, possession state,
durability use, pickup lock, listener, or agent-facing function surface. Those belong
only to concrete world objects.

Every deployment captures immutable package content, the source revision, deployable
configuration, credential-version handles, capability grants, initial state,
durability, locks, and runtime-issued identities for the root and package-owned
children. Changing an Inventory source affects future copies; existing world objects
retain their captured state.

### Exact identity and scope

Names are convenient input, not authority. Human selectors resolve to a complete
runtime ID before authorization or persistence. A command accepts a complete ID, a
unique runtime-ID prefix of at least four characters, or a unique case-insensitive
exact name within its selected scope. Ambiguity returns bounded candidates and does
not mutate state.

Agents, installed packages, Inventory sources, credential versions, and the saved
current-world pointer are user-global. A `--world` selection lasts for a single
command; changing the saved pointer is an explicit world-management operation.
World objects, their containment, occupancy, reports, Wallet records, and model
histories remain world-local.

### Human administration and agent action

The guided human console schedules administrative commands. `khoros shell
<agent-selector>` is a different interface: it submits a bounded action batch to one
agent inside that agent's assigned world. Neither surface expands into an
operating-system shell.

The human can inspect exact world objects and use their declared administrative
interfaces. Agent-facing functions are separately mediated. Package lineage, a type
name, a coordinate, or a selector prefix never confers authority by itself.

## Installation and first path

mikrokhoros is a Swift 6.1 package for macOS 13+, Linux with Swift 6.1+, and Windows
with Swift 6.1+. The repository [README installation section](../README.md#install-khoros)
is the canonical home for the current macOS/Linux and Windows instructions. Return
here after `khoros` is available to choose a first path and understand the operating
model.

### Start with an isolated exercise

Once the executable is available, begin with
[Tour 1: Your first world](tours/01-first-world.md). The tour index creates an
isolated `MIKROKHOROS_HOME` for its examples, so it does not alter your ordinary
product data. Keep that environment value for all four tours.

For a normal local setup, `khoros init` creates a complete `default-khoros` setup
without a wizard, confirmation, provider request, credential prompt, or AI profile.
It creates configuration when absent, installs the five facility packages, creates
their canonical sources under `/Templates/default-khoros`, creates a world named
`default-khoros`, applies the template, and adds an unprofiled `agent` at root
`(0,0)`. Repeating the command repairs recognized missing template pieces and
otherwise makes no change.

Use the generated [CLI reference](cli-reference.md) for the explicit bare-world,
templated-world, template-status, and world-selection command forms.

### Use mikrokhoros Web

Run `khoros web` with or without an existing world. The native `khoros` executable
serves mikrokhoros Web in the foreground; there is no separate `.app` or Node
process. By default it binds exactly `127.0.0.1:47567`. Use `--port <1...65535>` for
one exact custom port or `--available-port` to let the operating system select an
available port atomically. The two port options are mutually exclusive, and an exact
port never falls back silently.

The command prints one short-lived local URL; open that exact URL in a browser and
keep the command running. Use `khoros --world <selector> web` to choose an initial
world without changing the saved current-world pointer. `web` accepts `--config` and
`--world`, but not `--output` or `--color`; mikrokhoros Web owns its browser
presentation. Do not replace `127.0.0.1` with `localhost` or change the bound port;
the host rejects alternate and forwarded authorities. Ctrl-C stops the host.

When an exact port is occupied, a listener that identifies as mikrokhoros Web means
another terminal already owns that address; use its printed launch URL or start a
separate host with `--port` or `--available-port`. An unknown local listener requires
a different port. The marker is bounded diagnostic guidance, not authentication or
permission to attach to another process.

The World page reads the same canonical product state as the CLI. It can switch the
route-local world, focus and follow agents, pan or zoom the map, inspect cells, open
nested containers, review human object reports, keep local pinned shortcuts, and
render the selected exact world object's `ObjectManagementInterface`. The World menu
always ends with `Create new world`; it opens a compact form that commits a bare
world, makes it current, and opens its exact route. Add agent places one existing
user-owned identity at explicit integer coordinates without starting follow. The
bottom command dock is an intentional bounded exact-world interface: its autocomplete
and output are limited to the commands allowed there. Searchable Help remains the
full command reference; domain actions open from their relevant page or selected
entity.

Use the app-view dropdown for Agent Manager, Inventory, Packages, and Templates.
Settings is the fixed sidebar-footer control:

- **Agent Manager** creates and inspects identities, configuration, profiles,
  assignment, presence, and lifecycle equipment. Equipment links open each exact
  held or agent-attached object's bounded interface rather than duplicating object
  controls in this view. Non-spatial equipment keeps its canonical structural path
  without receiving a fabricated world coordinate. Retry is shown only when an
  active agent with a profile has a positive safe pending-work count; the page never
  exposes the content of that queued work.
- **Inventory** manages folders and sources. Selecting one exact source opens its
  typed `ObjectManagementInterface` for declared fields, actions, views, and report
  contracts. Its host controls show field type, requirements, deployability, safe
  defaults, choices, and limits; action inputs retain declared order, type, safe
  defaults, choices, capability requirements, scope, and structured result shape.
  If the selected contract declares a filesystem-path field or path-typed action
  input, its actions and views remain visible as `CLI only` contract metadata;
  configuration-backed views are also CLI-only. The browser cannot set or unset a
  host path, and browser mutation results show configuration-key presence rather
  than values.
  Deployment, reports, restocking, capabilities, and credentials remain source-level
  actions. The source detail shows readiness requirements, exact source/fork/template
  provenance, and exact world binding without revealing source configuration or
  credential values. An exact target World appears only inside an action that needs
  one.
- **Packages** presents available, installed, and retained package records with
  identity/version, runtime, requested capabilities, installation state, retained
  content hash/time where applicable, source counts, and management counts. Its
  install control is labelled **Trusted package source** and accepts only an exact
  `builtin:<catalog-name>` source or an HTTPS URL.
- **Templates** presents every available root and owned-object placement as Object,
  Package, and Placement rows. Placement names the parent space and requested
  coordinate when declared; trusted `default-khoros` currently has nine rows. Status
  and application collect an exact World inside their action, Create World is in the
  compact overflow menu, and the view has no persistent World picker.
- **Settings** handles setup, status, configuration, diagnostics, adapters, and the
  finite web-host status projection.

The browser uses native domain projections and contextual action sheets. A generic
mapping is reserved for a selected exact Inventory source or selected exact world
object through its declared `ObjectManagementInterface`; it is not a replacement for
mikrokhoros Web domain pages. Exact-ID inputs offer bounded completion.
Consequential actions require a prepare/review/confirm step; prepared plans expire
and can be used once. Credential values are write-only and cleared after submission.
Private world inspection requires explicit reveal, export is a download, and report
follow has explicit Start/Stop. Output is inert text and remains in page memory unless
the selected action itself persists canonical product state.

## Worlds, templates, and agents

### Bare worlds and the trusted template

Creating a world produces a bare infinite world unless the exact trusted
`default-khoros` template is selected. The template is a host-owned composition of
five independent canonical Inventory sources. Its Templates view shows every
concrete definition directly:

| Object | Package | Placement |
| --- | --- | --- |
| Athena | `org.mikrokhoros.athena` | world `(0,-2)` |
| Objective Board | `org.mikrokhoros.objective-board` | world `(1,-2)` |
| Objective Index | `org.mikrokhoros.objective-board` | Objective Board `(0,0)` |
| Library | `org.mikrokhoros.library` | world `(-2,2)` |
| Library Catalog | `org.mikrokhoros.library` | Library `(0,0)` |
| Warehouse | `org.mikrokhoros.warehouse` | world `(2,2)` |
| Warehouse Directory | `org.mikrokhoros.warehouse` | Warehouse `(1,0)` |
| Marketplace | `org.mikrokhoros.marketplace` | world `(0,2)` |
| Merchant | `org.mikrokhoros.marketplace` | Marketplace `(0,0)` |

The facilities are authorized by exact template lineage, never by mutable names,
coordinates, types, or package metadata. Applying the same healthy template is
idempotent. An explicit template application can present one aggregate confirmation
when it needs packages, the template folder, or canonical sources; its dry-run mode
shows the planned changes. Required locations are exact unless a supported
`--auto-adapt` option is selected.

Template facilities are independent from agent equipment. Removing or re-entering an
agent does not turn the agent's backpack, Wallet, or holdings into template state.
For the normative template, repair, and lineage contract, read
[design `17`](design.md#17-bare-worlds-and-default-khoros).

### World and agent lifecycle

Worlds are independent storage boundaries. Creating one makes it current. A temporary
`--world` selection applies to one command; a world-management command changes the
saved current-world pointer. Deleting a world removes only its concrete state:
user-level packages, Inventory sources, credentials still retained elsewhere, and
agent identities remain.

Creating an agent identity, placing it in a world, and attaching an AI profile are
separate operations. An agent identity initially lives in the user-level agent
catalog. Its first placement assigns it to one exact world. Removing it from a world
surface preserves that assignment and its concrete equipment so that it can re-enter
the same world. A conflicting world selection for an assigned agent fails without
mutation. Browser-side world entry is not an identity-creation operation and does not
auto-run provider processing.

Profiles can use supported external model services, compatible local servers, or
role-separated coding-agent adapters. Provider credentials remain human-controlled;
adapter and model selection do not change the agent's world authority.

### Messages, objectives, and facilities

Messenger is an ordinary native world object. A human resolves its exact object ID
from the selected agent's administrative surface, inspects its declared interface,
and submits a message through the generic world-object path. A profiled active agent
processes an eligible notification immediately. A provider failure, restart, or
temporarily absent profile leaves a durable unread event for later delivery when the
Messenger is again carried by its bearer.

Objective Board exposes human-only posting and acknowledgement through its exact
native management provider. Agents discover posted work through the Objective Board
and Objective Index, then use the child Objective's bounded read, registration,
progress, final, and revision functions. Objective work has no payment gate.

## Human console and agent shell

### Guided human console

Run `khoros` from an interactive terminal, or request the console explicitly:

```bash
khoros
khoros console
khoros --world default-khoros console
```

Enter a complete command, or enter only a command path to open its guided form. The
one-shot parser, form, completion palette, help, safe-history policy, and command
execution are driven by the same exhaustive command catalog. A displayed default is
a real default; a completion remains a candidate until the command is submitted and
validated.

The editor remains available while commands execute in FIFO order. Prefix a command
with `&` to make a failure pause pending work. `:resume` continues it after review.
`:queue`, `:pause`, `:cancel <queue-id>`, `:clear`, `:context`, `:help`, `:quit`,
and `:quit!` manage the console session. Confirmation, hidden-secret, and
agent-action prompts receive exclusive foreground input and restore the unfinished
human command afterward.

Ctrl-C clears a nonempty draft, cancels a form or running command, and exits from an
empty idle prompt. Ctrl-D exits only when no work remains. The console preserves
scrollback, adapts to terminal size, edits extended Unicode grapheme clusters, and
restores terminal flags and cursor state on exit.

With redirected input, bare `khoros` prints help and exits successfully. Explicit
`khoros console` requires interactive stdin and stdout. The console does not parse or
run operating-system shell syntax.

### Output and selectors

Interactive terminals receive concise human output; redirected stdout receives
canonical YAML. Choose `--output human`, `--output yaml`, or `--output json` when a
script or report consumer needs a stable representation. ANSI colour has a separate
`--color auto|always|never` policy. YAML and JSON never contain ANSI; `NO_COLOR`,
`FORCE_COLOR`, and `TERM=dumb` affect automatic presentation. The
`presentation.unicode` setting selects automatic, Unicode, or ASCII-only human
glyphs. Streaming reports emit one YAML document per event or NDJSON with JSON
output.

Use complete IDs whenever a particular object, Wallet, deployment, or report matters.
Unique names and bounded prefixes are convenience selectors only; exact resolution
happens before authority or persistence checks. Consult the
[CLI reference](cli-reference.md) for each command's selected scope and options.

### Bounded agent shell

`khoros shell <agent-id>` is the direct human testing surface for an agent's
in-world action language. An LLM can propose the same bounded action lines:

```text
move <direction> [steps]
container in
container out
pickup
drop [<direction>|(<dx>,<dy>)]
backpack open
backpack close
holding select <1|2|3|4>
object (<function> (<argument>) ...)
inspect [here|held]
```

The first world entry places an `eye.object` in holding 1. Each agent has four
independent holding roots; holding 1 begins as primary, and `holding select` changes
which root ordinary `pickup`, `drop`, `inspect held`, and `object` actions use. The
Eye's `look` function renders the fixed 5×5 area around the agent. It is a normal
object that can be carried, stored, dropped, locked, sold, or replaced.

An action batch runs in first-come-first-served order, accepts the configured action
prefix, warns about excess lines, stops at its first error, and returns an ordered
YAML-compatible event stream. This language is intentionally not a general purpose
command shell. Its full protocol is [design `15`](design.md#15-agent-request-and-action-protocol).

## Packages, Inventory, and world objects

### From package to independent copy

`ObjectPackageManifest` is the one portable package format. It records a package ID
and version, install policy, supported runtime, initial object data, optional
package-owned child graph, agent-facing functions, requested capabilities, typed
human fields and action inputs, views, and bounded report contracts.

The installed CLI supports the closed declarative runtime. Declarative actions can
read and mutate bounded JSON state, return values, and emit declared reports. They
cannot import code or directly access the operating-system shell, filesystem, or
network. Trusted native Swift objects are compiled and registered by a host.
JavaScript packages remain unavailable until a sandboxed adapter exists.

The normal lifecycle is:

1. In mikrokhoros Web, install a package from **Trusted package source** using
   an exact available `builtin:<catalog-name>` source or an HTTPS URL, then create or
   inspect its Inventory source. The CLI's `inventory install` command separately
   accepts its documented path-or-URL input.
2. Configure typed fields, create credential versions through a write-only input
   path, and grant only the requested capabilities that you intend to allow.
3. Check readiness, then deploy an independent world copy to an exact destination or
   a supported adaptive location.
4. Use the source's management actions and views for source-level work, and use
   exact world-object administration for a deployed copy.

For a complete, reproducible version of this workflow, take
[Tour 2: Install and deploy an object package](tours/02-object-package.md). The
generated [CLI reference](cli-reference.md) owns the exact install, configure,
secret, capability, action, view, deploy, copy-listing, and copy-inspection syntax.

### Credentials, capabilities, and source organization

Credentials are immutable version handles. The human supplies secret values through
hidden input, stdin, or an explicitly selected environment variable; the runtime
stores only the opaque reference in Inventory and keeps secret values out of ordinary
human output. Source configuration, credential changes, and capability grants affect
future deployments by incrementing the source revision; existing copies retain their
captured revision.

Inventory folders organize sources for the human. They never become world containers.
A world-bound source fork copies ordinary configuration, management state, and grants
from its parent, has its own revision, records the exact parent source ID, parent
revision, and fork time, omits credential handles, and can deploy or restock only in
its exact bound world. The source detail independently reports every missing required
configuration field, credential field, and requested capability; readiness is checked
again immediately before deployment or restocking. Moving an Inventory source between
folders does not change its existing world copies.

### Live host folders and composable objects

The `builtin:user-workspace` package projects selected human host folders into a
world through a world-bound Inventory fork and an explicitly granted user-machine
capability. The deployed workspace remains an ordinary movable container. Mounted
folders and files become anchored objects, symbolic links are visible but
non-traversable, and contents reconcile lazily when the relevant object surface is
used. Agents see the mount alias and relative path; absolute host paths stay on the
human management surface.

Grant only the host-resource capability and access mode that a particular source
needs. A projected write remains subject to the selected mount, read-only policy,
symlink/path checks, encoding and size limits, and replay-safe external-effect
receipts. Follow [Tour 4: Expose a live host folder](tours/04-live-user-workspace.md)
for the complete setup.

The `builtin:pencil`, `builtin:printer`, and `builtin:paper` packages demonstrate
ordinary object-to-object composition. A held pencil calls compatible neighboring
objects; a printer writes to its configured relative output coordinate; Paper and
projected text files implement the same callable contract. Direct agent calls cannot
invoke object-only functions, and a failed target call consumes no durability. See
[Tour 3: Compose printer, paper, and pencil](tours/03-composable-tools.md).

For authoring details, capability contexts, function audiences, and native-adapter
rules, use the [Object SDK guide](object-sdk.md).

## Advanced administration

### Inspecting and managing exact world objects

Use `status` and `doctor` to orient and validate installed-product state. World
administration can inspect the selected world, examine an exact agent or object,
export a world, list or show objects, and run declared object actions or views.
The [CLI reference](cli-reference.md) owns the exact command forms.

`world inspect` is a complete human-only live view of agents, containment, placement,
locks, durability, package and Inventory lineage, listener state, public functions,
Wallet IDs, Wallet modes and balances, four holdings, bearer ownership, and
non-secret private state. `world export` includes the world journal, signed Wallet
records, operation envelopes, and model histories. Both can expose private messages,
notes, documents, activity, and exact IDs, so treat their output as private user
data.

Generic world-object administration always resolves an exact object ID, its current
revision, and a typed declared interface. The exact trusted native generic
human-management providers are Wallet, Messenger, and Objective Board. Package
metadata cannot turn another object into one of those providers or bypass the
runtime's authority checks.

### Listeners and reports

A human listener is enabled for one exact world-object ID. Only declared reports
emitted while that listener is enabled enter the human report store. Reports carry
an exact report ID and time, authenticated world, concrete-object, Inventory-source,
revision, package/version, declared type, title, body, and structured payload.
Lineage is runtime-issued rather than supplied by the report body. Reports remain
separate from Messenger notifications and agent requests.

World-scoped management views can select an exact copy without a listener. Use the
listener, report, and view command families in the
[CLI reference](cli-reference.md) for exact selectors and streaming options.

### Marketplace and restocking

The `default-khoros` Marketplace is requested at `(0,2)@world`. Its Merchant is a
package-owned child at local `(0,0)`; bare worlds have no Marketplace. Agents at the
exact Merchant use its `catalog` and `buy` functions. `buy` names the concrete item
and requires an exact full payer Wallet ID. Merchant is not a native generic
human-management provider.

A human creates an Inventory-backed restock rule against the exact Merchant. Manual
and purchase-triggered restocking use the source's current revision and create a new
concrete ID. Existing stock and purchased objects preserve their own state. Rule
changes apply to future stock, and deleting a rule leaves existing stock and
purchased objects in place.

### Explicit copy deletion

Copy deletion is intentionally separate from Inventory configuration. Start with a
dry run for the exact selected object, deployment, or all-descendants scope, then use
the required confirmation form only after reviewing the result. A nonempty container
requires explicit recursion; its preview lists every contained object, including
objects with different lineage.

Deleting an Inventory source does not delete its world descendants. Active restock
rules must be removed before deleting their source. See the generated
[CLI reference](cli-reference.md) for the exact dry-run, `--yes`, `--recursive`, and
scope options.

## Wallets, holdings, and property

The economy is world-local and bearer-based. Every registered agent receives one
native `wallet.object` at exact backpack coordinate `(4,0)` and four independent
carrying positions numbered 1 through 4. A Wallet object is a public surface; its
balance, mode, and signed history live in the world credit service.

Holding roots do not occupy material world cells. Their recursive contents remain
property of the bearer. The canonical `ObjectLocationIndex` derives ownership from
registered containment, four holding roots, and agent backpacks, including inactive
agents. Names, types, coordinates, package metadata, a copied object, or a Wallet
prefix never confer property authority.

Wallet IDs must be complete runtime IDs whenever a transfer or purchase names a
payer or recipient. The exact current bearer must match the Wallet registration,
original backpack provenance, signed custody commitment, and location index before a
Wallet can spend. A valid journaled move can transfer bearer rights; raw moves,
stale snapshots, and package-controlled metadata cannot.

### Human and agent financial boundaries

The human uses the exact Wallet management surface for deposit, deduction, mode,
balance, bounded statement, and local-chain verification. Messenger exposes bounded
human message/thread operations, and Objective Board exposes human-only objective
posting and acknowledgement. These trusted native generic management providers are
limited to Wallet, Messenger, and Objective Board.

An agent can transfer credit only by invoking `transfer` on the exact Wallet it
currently owns. Merchant `buy` requires an exact full payer Wallet ID. A normal
Messenger message can request or announce funding, but message text cannot mint
credit, alter Wallet mode, or authorize a deposit. Objective work does not require
payment.

Amounts use at most two decimal places and signed 64-bit minor units. A finite Wallet
must have enough value for a transfer or merchant purchase. Unlimited mode bypasses
that sufficiency check only for an explicitly priced Merchant purchase; it records
the positive nominal price and applies zero. Peer transfers still use the retained
finite shadow balance, so unlimited mode does not create transferable value.

The root treasury authority is locally generated and pinned by an Ed25519 public key.
Its private key is available only through an opaque credential handle. Signed records
bind the exact world and authority key, prior record hash, accounts, custody, and
operation information. A missing or mismatched private credential permits
verify-only inspection but makes credit mutation fail closed. This provides local
integrity and replay protection, not external consensus, settlement, or finality.

Read [design `16.1`](design.md#161-wallet-economy-treasury-and-custody) and the
[Wallet, treasury, and property-rights boundary](security.md#wallet-treasury-and-property-rights-boundary)
before making financial or custody-related changes.

## Local data, configuration, and recovery

### Product data and privacy

The default product root is `~/.mikrokhoros`:

```text
~/.mikrokhoros/
├── config.json
├── agents.json
├── inventory.json
├── console-history.json
├── packages/
│   └── <sha256>.json
├── credentials/
│   └── <opaque-version-handle>
├── treasury-authority.json
├── treasury-credentials/
│   └── <opaque-private-key-handle>
└── worlds/
    ├── index.json
    └── <world-id>.json
```

- `config.json` contains human-owned limits and defaults.
- `agents.json` contains user-owned agent identities, profiles, defaults, and world
  assignments. It is AgentStore schema 3 and has no concrete world-object state or
  initial Coin balance.
- `inventory.json` contains installed-package records, redacted Inventory sources,
  folder organization, fork provenance, and exact world bindings.
- `console-history.json` contains bounded command paths and explicitly entered safe
  fields. It excludes secrets, message/objective bodies, raw agent actions,
  credential-bearing URLs, arbitrary management assignments, output, Wallet funding
  bodies, full Wallet IDs, custody material, and queue state.
- `packages/` retains content-addressed package bytes. `credentials/` stores
  write-only credential versions and is owner-restricted on POSIX systems.
- `treasury-authority.json` contains the root authority's public key, key ID,
  creation time, and opaque private-credential handle. Private key bytes remain in
  `treasury-credentials/`.
- `worlds/index.json` holds the bounded world catalog and current-world pointer.
  Each `worlds/<world-id>.json` contains that world's journal, agent snapshots,
  holdings, deployment snapshots, listeners, reports, restock rules, Wallet snapshot
  and signed record chain, operation envelopes, and model histories. World documents
  use schema 7.

`MIKROKHOROS_HOME` selects another complete product root for isolated development and
automation. `--config <file>` overrides configuration for one command. Product data
is independent of the current shell directory.

Persistent mutations use the product lock, atomic replacement, and recoverable
transactions where multiple stores must change together. Package downloads are
streamed beneath configured limits; remote packages require HTTPS except loopback
development. Credential versions remain while a live Inventory source or world copy
references them, then are collected after their final persisted reference is removed.
World deletion commits catalog, assignment, retention, and world-file changes before
credential collection.

### Configuration and recovery

All published numeric limits are user-owned configuration: model/action/request
limits, package and document sizes, reports, Inventory folders, object invocation,
host mounts, projected directory/file exposure, and console input/queue/history
limits. Use the `config` command family to inspect effective values, enumerate keys,
read or set one key, reset defaults, and validate the complete configuration. The
generated [CLI reference](cli-reference.md) lists the exact forms.

`agents.maximumActionsPerResponse` is copied into newly created agents; individual
agents remain configurable, subject to the runtime-wide ceiling. Increasing a limit
deliberately increases persistence, memory, provider, or execution exposure. Consult
[design `18`](design.md#18-configuration-and-diagnostics) and
[security `Verification`](security.md#verification) before widening a security-relevant
boundary.

Use `status` to orient, `doctor` to validate local state, and the relevant list or
inspect surface to resume an interrupted operation. Successful persisted work remains
durable. For an isolated tour, repeat the first missing step after checking its
result; the tour index includes focused recovery guidance.

### Compatibility boundary

The current storage contract is intentionally a clean break: world schema 7,
AgentStore schema 3, and administrative snapshot schema 2. Coin/single-hand and
other older files are rejected before load. mikrokhoros has no automatic migration,
explicit legacy import, or compatibility conversion. The retired `--workspace`
option returns unsupported-format guidance and never mutates state.

## Further reading

- [Hands-on tours](tours/README.md) for isolated, progressive exercises.
- [Generated CLI reference](cli-reference.md) for every command path and option.
- [Object SDK guide](object-sdk.md) for package and adapter development.
- [Canonical design](design.md) for runtime behavior, persistence, and future
  boundaries.
- [Security architecture](security.md) for trust boundaries, validation controls,
  and known limits.
- [Contributing guide](../CONTRIBUTING.md) for repository changes and required
  verification.
