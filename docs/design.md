# MikroKhoros runtime and Object SDK design

This document is the canonical engineering contract for the implemented CLI-first
product. Security invariants are specified in [`security.md`](security.md).

## 1. Product boundary

MikroKhoros contains worlds. A world contains agents and objects. The human creates
and manages agents, chooses AI profiles, installs object packages, owns Inventory
source objects, deploys concrete copies, and reads administrative state.

An attached LLM is one agent’s cognition. The world has already been selected by the
human. The LLM receives a role-separated request and returns one or more raw world
action lines. Runtime code authorizes and executes each action against current state.

The first-party executable is `khoros`. Its human CLI and the agent action language
are separate interfaces:

- the human CLI manages product state;
- the agent action language manipulates only the agent and accessible world objects;
- an object’s human-management interface is a structured runtime contract exposed
  through Inventory for package-backed objects and through exact world-object
  management for native objects; and
- an object’s agent-facing functions belong to concrete world instances.

## 2. Canonical object layers

```text
MikroKhoros Object SDK
  developer APIs, schemas, capability services, and runtime contracts
                          ↓ used to build
Object package
  portable versioned artifact containing one implementation and manifest
                          ↓ installed for the human user
Installed object package
  registered implementation available to create Inventory objects
                          ↓ package policy creates
Inventory object
  user-owned configurable source outside every world
                          ↓ copied by deployment or restocking
World object
  independent concrete instance inside exactly one world
```

The SDK is a development kit. It has no coordinate, object identity, possession
state, durability, or agent-visible surface.

An installed package is user-global. A concrete world object is world-local.
These identities remain distinct:

- package ID and semantic version;
- package content hash;
- Inventory object ID and revision;
- deployment ID;
- concrete world-object ID; and
- invocation ID.

## 3. Installed-product state

The default root is `~/.mikrokhoros`:

| State | Default location | Scope |
| --- | --- | --- |
| Runtime configuration | `config.json` | user-global |
| Agent identities, profiles, and world assignments | `agents.json` | user-global |
| Package catalog, Inventory folders, and source objects | `inventory.json` | user-global |
| Guided-console history | `console-history.json` | user-global |
| Retained package bytes | `packages/<sha256>.json` | user-global |
| Credential versions | `credentials/<handle>` | user-global |
| Root treasury authority | `treasury-authority.json` | user-global key pin, world-local use |
| Root treasury private credential | `treasury-credentials/<handle>` | user-global signing authority |
| World catalog and current selection | `worlds/index.json` | user-global |
| World journal and model histories | `worlds/<world-id>.json` | exact world |

`MIKROKHOROS_HOME` selects another complete product root. `--config` overrides only
the configuration document. Package, Inventory, agent-identity, configuration, and
template-discovery commands are user-global. Concrete membership, copy, listener,
report, merchant, restock, and template commands use the current world or the exact
world selected temporarily by `--world`.

The current shell directory is never a persistence selector. `world use` changes the
catalog’s persistent current-world pointer; `--world` never changes it. Agent-targeted
commands resolve the agent’s exact assignment first and reject a conflicting world
selection. Runtime authorization, lineage, and retention records contain exact world
IDs rather than file paths.

Inventory schema 4 stores the permanent folder hierarchy, source folder membership,
fork provenance, optional exact-world binding, canonical template-source provenance,
and artifact retention keyed by exact world ID. World schema 7 stores the display
name, template applications and repairs, runtime-adapter identity/state, concrete
instance revisions, instance movement and management mutations, projected topology,
four-slot holdings, world-local credit snapshots, signed credit records, operation
envelopes, bounded nested-invocation receipts, and bounded external-effect receipts.
The AgentStore is schema 3 and the administrative world snapshot is schema 2. The
world catalog schema stores exact IDs, names, timestamps, and the current selection.

Persistent documents are versioned and size-bounded. Mutating CLI processes are
serialized through a product-state lock. Writes use a temporary file, storage
synchronization, and atomic replacement. Template setup uses a cross-document
recovery journal so an interrupted product mutation resolves to its complete prior or
committed state before the next command loads files. Each journal records the exact
affected world IDs; credential collection is deferred until a world-deletion
transaction commits, so rollback can restore every retained artifact.

This release is a clean persistence break. Coin/single-hand world formats, world
schemas other than 7, AgentStore schemas other than 3, and administrative snapshots
other than 2 are rejected. No world or agent migration is provided; legacy import and
automatic legacy conversion are outside the product contract. The retired
`--workspace` spelling is rejected before product mutation.

### 3.1 Human command architecture

The executable target is a thin adapter over `MikroKhorosCLIKit`. Every executable
leaf is represented exactly once by `CommandKind` and one `CommandDefinition`.
Definitions supply the path, help summary, ordered positional and option fields,
cardinality, completion provider, default resolver, foreground-input declaration,
and history policy.

Both entry paths converge on the same named execution flow:

```text
one-shot tokens ────────→ CommandParser ─→ ParsedCommand ─→ CommandExecutor
console tokens or form ──→ CommandParser ─→ ParsedCommand ─→ CommandExecutor
```

`CommandCatalog.definition(for:)` and runtime dispatch use exhaustive switches.
Adding a `CommandKind` without catalog metadata or execution routing therefore fails
the Swift build. Domain handlers remain named functions so source-graph tools can
trace one-shot and console calls to the same mutation boundary.

`khoros` starts the guided console when stdin and stdout are terminals. `khoros
console` requests it explicitly. Bare noninteractive execution prints generated help;
explicit noninteractive console use fails with `console.tty_required`.

The console is an inline editor rather than a full-screen interface. A dependency-free
terminal abstraction has termios and WinSDK backends plus a deterministic fake. It
owns terminal mode, logical line endings, physical-row clearing, resize detection,
bracketed paste, cursor visibility, and restoration. Editing operates on extended
grapheme clusters while terminal-cell measurement handles combining sequences, CJK
width, emoji, and horizontal input scrolling.

The empty prompt renders a compact context header rather than the catalog. Typing or
Tab opens a height- and width-bounded palette. A complete quoted command line enters
the normal parser directly; a leaf command path without fields runs directly, while a
path with fields opens its catalog-generated form.

Known command paths open a form containing every declared field. Collection is
permissive: defaults are captured when displayed, omission remains omission, and the
ordinary parser and handler validate only when the queued item executes. Completion
reads bounded local state and never invokes an object, model provider, remote endpoint,
or operating-system shell.

Inventory fork forms capture an explicit world selection. Management-action forms
resolve the selected source or exact concrete object, list its declared actions, and
ask for the selected action’s typed inputs. They still materialize ordinary tokens
and use the shared parser and executor.

Submitted commands enter a session-local FIFO. Each item captures its configuration
override, exact selected world, resolved values, and a queue ID. State locks and documents are acquired anew
for each item, so later items observe committed earlier mutations. Ordinary failures
do not stop later work. A leading `&` marks an error barrier; its failure pauses before
the next item while preserving FIFO order until `:resume`. Console controls are a
separate exhaustive enum and never enter `CommandParser`.

Ctrl-C clears a nonempty draft, cancels a form or foreground prompt, requests
cooperative cancellation of running work, and exits from an empty idle root prompt.
Paused pending work requires a second consecutive Ctrl-C before it is discarded.
Ctrl-D exits only while idle. Escape cancels the current editor/form interaction and
is not interpreted as Ctrl-C.

`CommandIO` serializes output and grants execution-time foreground ownership to
confirmation, hidden secret, and manual agent-action prompts. The renderer
restores the human draft, cursor, completion choice, and form position afterward.

Handlers produce one presentation-neutral structured result. Human terminals receive
headings, tables, complete detail identities, semantic ANSI status, and trusted
runtime-authored next actions. Redirected output defaults to canonical YAML; explicit
JSON is pretty-printed for finite results and newline-delimited for streams. YAML
streams use document separators. Machine modes never contain ANSI and multiline
values use YAML block scalars.

Human selectors resolve within the command's selected entity and world scope in this
order: complete runtime ID, unique ID prefix of at least four characters, then unique
case-insensitive exact name. The executor receives the complete resolved identity.
Package IDs and semantic versions retain their package identity syntax.

`khoros shell` uses the same terminal and line editor with its own exhaustive action
catalog, state header, help, history, and completion. Its typed rendering does not
modify `AgentTurn.text` or the model-visible action/result protocol. A submitted turn
containing an action failure is persisted and displayed once, then returns nonzero.

Successfully submitted forms are stored in a versioned, bounded, atomically replaced,
user-private history document. Only explicitly entered fields whose definition permits
history are retained. Secret material, hidden input, message/objective bodies, raw
actions, credential-bearing URLs, arbitrary management assignments, command output,
defaults not entered by the user, global context, and queue state are absent.

## 4. Unified object package

`ObjectPackageManifest` is the package schema. Unknown fields fail decoding. A
manifest contains:

- schema version;
- stable package ID and `major.minor.patch` version;
- display name and runtime;
- requested capabilities;
- package-selected installation behavior;
- initial object type, name, summary, public data, private state, durability,
  containment capability, invocation access, and functions;
- an optional validated flat owned-object graph with local parent IDs and
  container-local coordinates;
- typed human configuration fields;
- typed management actions and result contracts;
- management views and optional listened-world-object scope; and
- report title, body, payload, and byte contracts.

Package installation is content-addressed by SHA-256. The visible catalog key is
package ID plus semantic version. Package content for an existing ID/version is
immutable. A package version removed from the visible catalog remains retained while
Inventory records and deployment snapshots reference its content.

Owned-object IDs are package-local construction identifiers. The package validator
rejects duplicate IDs, missing or non-container parents, cycles, and coordinate
collisions. Deployment replaces every local ID with a fresh concrete runtime ID.

### 4.1 Installation policy

```yaml
installation:
  on_install: create_inventory_object
  additional_inventory_objects: allow
```

or:

```yaml
installation:
  on_install: register_only
  additional_inventory_objects: deny
```

`create_inventory_object` registers the package and creates one default source in
the same Inventory transaction. `register_only` creates only the catalog record.
`additional_inventory_objects` controls later `inventory create` commands.

Package versions coexist. Installing a new version leaves older packages, Inventory
objects, and world copies unchanged.

### 4.2 Runtime adapters

The installed CLI registers the closed declarative adapter and exact native adapters
for the first-party user-workspace, pencil, printer, and paper packages. Declarative
actions operate on bounded JSON state through a fixed interpreter:

- return;
- get;
- set;
- append;
- increment;
- toggle; and
- emit one declared report.

The manifest cannot create execution authority. Declarative packages do not import
code or directly call a shell, filesystem, network, or user machine.

Native Swift objects are trusted host implementations compiled into the embedding
process and selected through an exact package-to-adapter registration. A manifest
cannot register or activate native code. Portable JavaScript packages are rejected with
`object_package.runtime_unavailable` until a sandboxed cross-platform adapter
exists.

Finance is a runtime-owned authority domain, not an Object SDK capability. No
declarative or native package may mint credit, change a wallet balance or mode, sign
treasury records, forge custody, infer property ownership, or create/copy the
reserved `wallet.object` type. Packages can provide ordinary object functions and
human-management contracts. The runtime’s exact native generic human-management
providers are limited to Wallet, Messenger, and Objective Board. Agent-owned Wallet
`transfer` and trusted Merchant `buy` remain agent object functions mediated by the
runtime; Objective Index is a discovery surface, not a native generic management
provider. Funding requests travel as ordinary Messenger messages, and a message does
not itself authorize a deposit.

## 5. Inventory objects

An `InventoryObjectRecord` is a human-owned source outside all worlds. It stores:

- runtime-issued source ID and user-facing name;
- package ID, version, and content hash;
- monotonically increasing revision;
- validated non-secret configuration;
- opaque immutable credential-version handles;
- requested and granted capabilities;
- object-defined management state;
- timestamps; and
- logical deletion state preserving lineage.

It is absent from `Harness`. It has no coordinate, bearer, holding or backpack state,
durability consumption, pickup lock, agent functions, or model-visible surface.

### 5.1 Human management contract

`ObjectManagementInterface` supplies structured metadata for the CLI and future
localhost UI:

- `ManagementField`: text, integer, decimal, Boolean, choice, URL, filesystem path,
  or secret;
- `ManagementAction`: stable ID, typed input names, capability requirements,
  mutating/read-only behavior, closed action, and structured result declaration;
- `ManagementView`: stable ID, structured source, result declaration, and optional
  listened-world-object scope; and
- `ObjectReportDefinition`: stable type and bounded title, body, and typed payload
  contract.

The runtime adds the standard human base interface: identity, package provenance,
readiness, missing fields/credentials/grants, revision, selected-world deployment
counts, restock dependencies, listener status, report summaries, and generic
configure/deploy/inspect/delete controls.

`WorldRuntime.managementInterface(for:)` returns the combined base and
object-defined description as structured data. The CLI renders that value directly;
the localhost UI can consume the same service.

Configuration updates are atomic. Every submitted field is declared, non-secret
values match their type, URL values use HTTP(S), paths are structurally valid, and
secret fields use the dedicated secret interface. Successful mutating
configuration, credential, capability, or management operations increment the
Inventory revision. Read-only actions and views preserve it.

Management state and human reports stay outside agent prompts and model histories.

### 5.2 Readiness

An Inventory source is ready to create a world copy when:

- every required non-secret field has a valid value;
- every required secret field references an available credential version; and
- every requested capability has been granted to that source.

Readiness is evaluated immediately before deployment or restocking.

### 5.3 Inventory folders and world-bound forks

The permanent Inventory root folder and `InventoryFolderRecord` hierarchy organize
human-owned sources. Folder names are unique among siblings. Paths resolve through
the hierarchy; exact runtime IDs remain authoritative for mutation. Moving or
renaming a folder preserves descendant identities. An Inventory folder has no
coordinate and never deploys as a world container.

Every Inventory source records one folder ID. Moving a source changes only that
organizational reference and timestamps; its source revision, package state,
credentials, grants, and world descendants remain unchanged.

`inventory fork` creates an independent source with the same package content,
ordinary configuration, management state, and grants. The fork omits credential
handles, starts at revision 1, records its parent source and parent revision, and is
permanently bound to the exact selected world. The package’s additional-source
policy applies. Deployment and restocking compare the bound world ID with the selected
world before mutation.

## 6. Credentials

`CredentialStore` is a cross-platform abstraction. The CLI implementation stores
each assignment as an immutable opaque version:

- interactive entry disables terminal echo;
- `--stdin` accepts automation input;
- `--from-env <name>` reads that environment variable at command execution;
- Inventory and world documents store only the version handle; and
- deployment captures the currently selected handles.

Updating or clearing a source credential changes future copies. Existing world
copies keep their captured handles. Secret values stay outside CLI output,
administrative snapshots, world exports, object reports, errors, prompts, model
history, and package metadata.

Inventory persistence tracks artifact retention by exact world ID. After a
successful state save, credential versions with no live Inventory, managed-world, or
in-process runtime reference are collected.

## 7. SDK authority contexts

Authority is separated by call site:

- `AgentObjectContext` identifies one agent invocation;
- `UserObjectContext` identifies one human management operation;
- `ObjectDeploymentContext` identifies one world-copy creation;
- `ObjectReportEmitter` emits structured human reports during its bound invocation;
  retained emitters expire when that invocation returns; and
- trusted built-in Swift objects use an internal complete runtime context.

`ObjectInvocationIdentity` is constructed by MikroKhoros from registered runtime
objects. It binds invocation, concrete object, agent, world, and optional lineage.
Caller-provided names and arguments cannot replace these values.

`ObjectCapabilityBroker` and mediated service objects enforce grants at every
protected operation:

- world read;
- world write;
- world system;
- network; and
- opaque user-folder access.

Each world copy receives the grant snapshot captured by its deployment. Revoking a
grant from its Inventory source changes future copies and preserves existing copies.
External package APIs do not expose `Harness`.

`ObjectRuntimeAdapter` separates runtime-specific package behavior from Inventory,
deployment, and replay. It validates its exact package contract, creates default
management state, captures deployment state, instantiates concrete graphs, restores
bounded adapter state, and handles scoped human actions and views. Exact world
actions receive `WorldObjectManagementContext`, which carries trusted identity,
lineage, revision, grants, the selected instance, and mediated services without a
public full-runtime handle.

Public functions declare an `agent`, `object`, or `both` audience. Direct agent
actions can call agent/both functions. A nested call can call object/both functions.
Nested identity retains the root invocation and original agent while recording each
calling and target object, current invocation, lineage, world, and depth.

Relative reads and calls resolve one exact delta in the caller’s immediate space. A
placed caller uses its own coordinate; a held caller uses its carrier’s coordinate.
No compatible-target search occurs. The configured call-depth limit terminates
recursive chains. Source and target durability are deducted only after each
successful function completion.

## 8. Deployment, snapshots, and lineage

`khoros inventory deploy` resolves one ready Inventory source and one destination.
Destinations are:

- root world;
- a container object’s local space; or
- an agent’s backpack.

Root-world `(0,0)` is the default. Exact occupancy returns
`placement.occupied`. Explicit `--auto-adapt` uses deterministic diamond-order
nearest-free placement.

Every deployment generates:

- one deployment ID;
- one concrete root object ID and one concrete ID for every owned object; and
- `ObjectLineage` containing package ID/version/hash, Inventory ID/revision,
  deployment ID, and optional restock-rule ID.

`ObjectDeploymentSnapshot` stores the package manifest, deployable configuration,
credential handles, root and owned-object private state, current and maximum
durability, locks, captured grants, concrete IDs, parent relationships, coordinates,
and lineage. Replay reconstructs the complete graph from the snapshot and recorded
destination. It never reads the current Inventory source.

Existing world objects remain unchanged across source configuration, credential,
grant, and management updates; package catalog changes; package version installs;
package removal from the visible catalog; and Inventory-source deletion.

`freshCopy()` remains a low-level native-object factory. Inventory deployment and
restocking use deployment snapshots and lineage.

Adapter-backed snapshots additionally record runtime-adapter ID/version, source
adapter state, concrete instance revision, and any captured external-resource
bindings required to restore the graph without consulting the current source.

## 9. Copy discovery and deletion

The selected world indexes concrete objects by Inventory source and deployment.
Deletion requires one scope family:

- explicit world-object IDs;
- explicit deployment IDs; or
- every descendant of one Inventory source in the selected world.

A preview resolves exact IDs and containment consequences. Non-empty containers
require recursive deletion. Recursive scope includes every contained object,
including children with other lineage. Runtime targets are revalidated immediately
before commit. The operation removes only the resolved world objects and their exact
listeners. Stored reports remain historical records.

Inventory configuration never invokes copy deletion. Inventory-source deletion and
restock-rule deletion leave existing world objects in place.

Agent-attached lifecycle objects are special. A Wallet is created by the agent
lifecycle, remains at backpack coordinate `(4,0)`, is not an Inventory deployment,
cannot be copied or fabricated by a package, and cannot be deleted as a standalone
object or as part of a subtree containing it. Removing an agent from a world leaves
the identity, backpack, Wallet, Messenger, holdings, and wallet history available for
same-world re-entry. Deleting the world removes that world-local concrete state and
its signed ledger; user-global agent identity and package/Inventory sources remain.
Any future custody-changing operation must first produce a signed custody record and
update the canonical location commitment; a raw object move cannot silently transfer
wallet authority.

## 10. Human listeners and reports

A listener is keyed by one exact concrete world-object ID in one world. Enabling
it does not mutate the object or notify an agent.

When a declarative object emits a report, `WorldRuntime` validates:

- the object is still registered;
- exact listener enablement;
- Inventory/package/world lineage;
- declared report type;
- title and body limits;
- typed payload fields;
- package payload limit; and
- global encoded report limit.

The stored `ObjectReport` contains report ID/time, world ID, concrete object ID,
Inventory source ID/revision, package ID/version, report type, title, body, and
structured payload. Configured report retention prunes older report events from the
world journal.

Reports are human management data. Messenger broadcasts are agent notification data.
These paths remain independent.

## 11. Marketplace and Inventory-backed restocking

When `default-khoros` is applied, its Inventory-backed Marketplace is a
`shop.object` requested at `(0,2)@world`. Its package-owned Merchant is anchored at
shop-local `(0,0)`. A bare world has neither object.

A `RestockRule` stores:

- source Inventory object ID;
- merchant ID;
- current price and enablement;
- requested shop-local coordinate and adaptation policy; and
- concrete IDs created by that rule.

Rule creation produces the first stock copy. Manual and purchase-triggered
restocking:

1. resolve the rule and current Inventory source;
2. validate current readiness;
3. capture the current source revision, deployable configuration, credentials, and
   grants;
4. create new deployment and object IDs;
5. apply the merchant’s ordinary shop-inventory lock;
6. place the copy at the requested or deterministic nearest free cell; and
7. register its price and lineage.

A purchase validates current stock identity, shop location, merchant ownership,
pickup lock, exact full payer wallet ID, bearer ownership of that wallet, finite or
unlimited mode, and replacement readiness before moving value. The purchased object
receives an allow-only buyer claim and stays in place until picked up. The replacement
is a new current-revision object. Failure restores the original lock and balance and
removes any partially placed replacement. Merchant payment is the only built-in
purchase gate; Objective Board participation never requires a payment or wallet
balance.

The package-owned Merchant exposes `catalog` and `buy` as trusted agent object
functions. `buy` accepts an item selector and the exact full payer Wallet ID; it is
not a generic human-management action or provider.

Changing a rule affects future stock. Existing stock and purchased instances retain
their own price, state, and lineage. Each created-stock record stores the price that
was active when that concrete copy was created.

## 12. World and containment

`world.object` is the root `MikroObject`. A container is an ordinary object with a
`Space`. Each space is an infinite sparse map:

```text
Coordinate(Int x, Int y) -> zero or one MikroObject
```

Negative and distant coordinates are valid. Coordinates are local to their
container. Containment cycles and duplicate runtime identities are invalid.

Structural paths combine coordinates, names, and IDs:

```text
(0,0)@world/(0,1)["Workshop"#w]/(3,-2)["Chest"#c]
```

Names are display data. IDs authorize identity-sensitive operations.

### 12.1 Exact-instance management and live user workspaces

The human can list, inspect, render the management interface for, act on, view, and
move one exact concrete world object. Actions and views declare Inventory, world, or
both scope. A mutating world action increments only the selected instance revision.
An ordinary movable root can change containers or coordinates atomically;
filesystem-projected descendants return `object.anchored`.

The same generic world-object management contract covers native objects as well as
package-backed objects. Its exact-object interface exposes declared actions, views,
input kinds, scope, mutation status, and structured result shape. Exact trusted
native generic human-management providers are limited to Wallet, Messenger, and
Objective Board. Wallet declares `deposit`, `deduct`, and `setMode` actions plus
`balance`, bounded `statement`, and local-chain `verify` views. Messenger declares
bounded message/thread management. Objective Board declares the human-only `post`
and `ack` actions plus objective, attention, and activity views. The CLI uses
`world object interface`, `world object action list|run`, and
`world object view list|show` for these operations; it does not maintain a parallel
coin, message, or objective command vocabulary.

Agent-facing functions are a distinct authority surface. An agent may invoke
`transfer` only on the exact Wallet it currently owns. Objective Board `view` and
Objective Index `list` discover human-posted objectives; the child Objective exposes
`read`, `register`, `progress`, `final`, and `revision`. The trusted Merchant exposes
agent `catalog` and `buy`, and `buy` requires the exact full payer Wallet ID.
Objective Index and Merchant are not native generic human-management providers.

Native management receives the exact registered object and the selected world under
the product lock. Before each operation it revalidates registration, current
instance revision, object lineage/lock, bearer property rights where applicable,
capabilities, full wallet IDs, and typed bounded inputs. Results are safe structured
projections: private wallet records, credential bytes, hidden host paths, and another
bearer’s private subtree never become a generic view or an agent prompt.

The first-party `user-workspace.object` is a deployed container backed by one or
more named folder bindings captured from a world-bound Inventory fork. Each mount
records an opaque binding ID, human-only canonical path, requested local coordinate,
and read-only/read-write mode. The world surface contains:

- `user-folder.object` containers for directories;
- `user-file.object` objects for regular files; and
- non-traversable `filesystem-link.object` objects for symbolic links.

Projected IDs derive from deployment seed, binding ID, and relative path. Existing
paths retain IDs and coordinates across refresh and restart. New entries use the
ordinary deterministic diamond-order placement around local origin. Relevant look,
inspect, entry, list, read, write, and human-management boundaries reconcile the
affected directory. No watcher or daemon is required.

Agent-visible state contains mount aliases and relative paths. Host paths remain on
the human management surface. Projected text functions return bounded structured
untrusted data. Text operations reject non-UTF-8 content; symbolic links are visible
but never followed.

`pencil.object` is a held 100-durability tool that addresses one of eight neighboring
cells and calls `write`, `append`, or `clear`. `printer.object` is a 100-durability
surface machine that calls `write` at its configured output delta, initially
`(0,-1)`. `paper.object` is an ordinary movable implementation of the same writable
function interface. Compatibility comes from function audience and signature, not
target type.

## 13. Agents and occupancy

Agent identity, world membership, and AI profile attachment are independent. A
user-level `UserAgentRecord` owns the runtime-issued identity, display name, action
preference, genesis IDs, AI profile, and optional
`AgentWorldAssignment`. It has no coordinate or concrete possession state.

`agent create` changes only the user-level catalog. `agent add` uses the current
world or a temporary `--world` selection, records the first exact world assignment,
registers a concrete agent snapshot in that world, and performs placement. An
assigned identity cannot be registered in another world. Removing it from the world
surface keeps its assignment and concrete world state, allowing later re-entry into
the same world.

Concrete registration creates the infinite backpack, native Wallet, Scratchpad,
Messenger, and calculator using the catalog’s stable genesis IDs. The Wallet is
placed in the backpack at `(4,0)` and is registered against the exact agent, world,
and backpack identities. First world entry puts a genesis `eye.object` in holding 1.
Later entry preserves the agent’s concrete equipment, all four holdings, Wallet ID,
and wallet history. World replay uses its concrete snapshot and journal, then applies
the current user-level profile and action preference.

Profile mutation for an assigned agent follows its exact world assignment. A
conflicting explicit world selection fails. The runtime updates the user record and concrete agent together, then immediately
processes the latest eligible unread carried notification. An unassigned agent may
receive a profile in the user catalog before its first world placement.

An agent has exactly four independent holding positions. The primary position is a
small integer (`1...4`) and selecting it is O(1); the runtime never searches for a
held object by type, name, or coordinate. `pickup` and `drop` operate on the primary
position, while the other occupied positions remain carried and participate in
ownership and broadcast eligibility. The holding roots are nonmaterial: they do not
block a world coordinate, prevent movement, or turn the bearer/object pair into a
material occupant. A standing object remains a separate world-space surface.

Property rights are universal and recursive. `ObjectLocationIndex` traverses every
world root, every holding root, and every backpack subtree, including inactive
agents, and assigns each concrete object a canonical path and optional bearer. A
nested child has the same bearer as its root. World-owned objects have no bearer;
agent-owned objects are accessible only to that exact agent. Duplicate placement,
ambiguous bearer, cycle, orphan, and depth-limit states fail closed. Names, object
types, coordinates, package lineage, and human selectors are never ownership
authority.

World mutations use a ticketed first-come-first-served queue. Competing pickups
resolve in queue order, and the first successful removal owns that concrete object.

## 14. Perception and object surfaces

Automatic self-state contains agent identity, structural path, all four holding
surfaces with the primary slot, standing surface, and the exact Wallet ID, balance,
mode, and debt projection. A model sees only its own bearer subtree; private wallet
records, treasury credentials, custody commitments, and another agent’s holdings are
not projected.

The genesis eye’s `look` function returns a 5×5 area centered on the agent. The eye
is a normal object with possession, durability, lock, sale, storage, and replacement
semantics.

Object surfaces include ID, type, name, summary, condition, current/full durability,
container capability, origin, and small public data. `inspect` adds pickup-lock,
lineage, captured grants, invocation access, and exact public function signatures.

## 15. Agent request and action protocol

The agent system field defines world-action syntax and safety boundaries. The input
field contains current quoted notifications and self-state. Provider adapters
preserve role separation.

After model-history compaction, the runtime adds a data-only checkpoint and rebuilds
the complete system field for the next request. Mutable world data is not promoted
into the system role.

The action grammar is:

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

A model response is split into nonempty lines. The accepted prefix is bounded by the
smaller of the agent preference and runtime ceiling. Excess lines produce a warning.
Accepted actions execute in order and stop at the first error. Successful commands
are quoted in their result receipt. Failed or rejected action text is omitted.

Results and interleaved notifications form one ordered YAML-compatible event stream.
Stable error codes carry bounded details and concrete generic recovery hints.

## 16. Messenger and broadcasts

Each agent’s genesis Messenger has a stable runtime identity. Messages route by
recipient agent ID and thread ID. Threads use Python-style reads, including negative
indices and ranges. Reads create receipts.

A Broadcastable object has a listener interface. Notification eligibility requires
the exact source object to be in one of the recipient’s four holdings or recursively
inside that recipient’s backpack. Putting the source back into possession, entering
the world with it, or attaching an AI profile queues a bounded oldest-first
enumeration of unread events. Every event is durable world state: it survives
provider failure, profile detachment, restart, and replay, and remains pending until
the bearer can receive it. Delivery acknowledges an exact event ID only after
accepted model output is persisted. Every delivery revalidates the source’s current
bearer through `ObjectLocationIndex` and projects only bounded public preview data.

Messenger priority markers are labels: `!`, `!!`, and `!!!`. Ordinary messages
may omit priority. The agent decides how to respond. A human funding request or
announcement uses this ordinary Messenger surface; message text never mints credit,
changes wallet mode, or bypasses the signed treasury operation. The recipient and
any wallet named in a subsequent transfer are resolved to complete runtime IDs.

### 16.1 Wallet economy, treasury, and custody

The wallet is a bearer capability represented by a native `wallet.object` attached to
one agent’s backpack at `(4,0)`. Its object data contains no balance and cannot be
copied through `freshCopy`, package deployment, or a fabricated package manifest.
Spend authority is valid only when all of these agree:

1. the wallet registration names the exact wallet, agent, world, issuer, and backpack;
2. `ObjectLocationIndex` currently resolves that wallet beneath one of the agent’s
   four holdings or backpack attachment root (not a name, type, coordinate, or stale
   registration); and
3. the invoking agent is the exact registered bearer.

Credit uses strict decimal parsing (at most two fractional digits) and signed 64-bit
minor units. A finite wallet rejects agent transfers and merchant purchases that
would make its balance negative. Unlimited mode bypasses sufficiency only for an
explicitly priced merchant purchase, whose nominal amount remains positive but whose
applied amount is zero. An unlimited wallet’s peer transfers still consume its
retained finite shadow balance. Both modes remain bounded by integer overflow, exact
wallet identity, exposure caps, and record validation. Human funding is an ordinary
authorized deposit operation reached through the Messenger/object-management
workflow, not an agent-controlled mint.

One root treasury authority is stored outside the world file. Its public key is
Ed25519, its key ID is domain-separated and derived from that key, and its private key
is retained only through an opaque credential handle. The authority is bootstrapped
once only with explicit confirmation that no economy state already exists; loading
never rotates or reseeds it. The default authority document is limited to 1 MiB.

Every world-local credit record is signed by that authority and binds the exact world
ID, key ID, operation ID, transaction ID, action index, actor, mode, account IDs,
amounts, post-balances, treasury delta/balance, and causal object/function/merchant/
item IDs. Records hash their canonical signed bytes and form a strict chain from the
64-zero genesis prior hash. Verification rejects a wrong world, key, signature,
prior hash, duplicate record ID, unknown field, malformed time, or over-limit payload.
The ledger invariant is explicit: the signed treasury balance equals
`totalDebt - totalPositive`, the negative of net wallet issuance. A transfer/purchase
or funding operation is committed only if the wallet balances, treasury contribution,
object mutation, and durable notifications agree with that invariant.

World event persistence carries a `WorldOperationEnvelope` containing the exact
operation ID, world, actor, timestamp, action index, optional idempotency key, signed
credit records, object revision mutations, receipts, unread/acknowledgement changes,
and sanitized activity. The product lock serializes application. Replaying an
envelope verifies the world and each signed record, rejects revision regression and
invalid bearer notifications, and treats an already-seen operation or record as a
no-op. A missing or mismatched private credential loads the authority and signed
history in verify-only mode; inspection and verification remain available, while all
mutations fail closed.

Custody entries are signed in the same chain. Each entry names the exact wallet, old
and new bearer, old and new canonical location commitments, and the prior custody
commitment. A custody change is valid only when the old commitment matches the
recorded chain and the new commitment comes from the current `ObjectLocationIndex`.
This is local tamper evidence and replay protection; it is not a blockchain, network
consensus protocol, or external settlement/finality layer.

The economy enforces bounded identifiers and notes (256 characters), at most 512
causal IDs, at most 10,000 accounts/custody entries per record, integral-second
timestamps, and the configured world/document limits. These caps protect parsing,
canonicalization, persistence, and model projection; they do not create a second
authority or a package finance API.

## 17. Bare worlds and `default-khoros`

The root `world.object` is an empty infinite sparse container when created. Core
constructors, missing-world reads, `status`, `doctor`, and template discovery do
not synthesize facilities. `world create` persists a bare world named `world` unless
the human supplies another name.

`WorldCatalogStore` owns the user-global `worlds/index.json` document. World file
locations are derived only from runtime-issued IDs. The catalog’s current-world ID
is a human interface selection, never agent or model authority. Creation selects the
new world, `world use` changes the saved selection, and `--world` captures a temporary
exact selection for one command or console queue item. World deletion removes only
the chosen concrete world, clears affected agent assignments and artifact-retention
references, and leaves user-global sources and identities intact. With one remaining
world it becomes current; with zero or multiple worlds the pointer is empty.

`WorldTemplateCatalog` exposes trusted host-registered definitions.
`WorldTemplateService` performs read-only preflight and atomic application. The
installed CLI registers one definition, `default-khoros@1.0.0`, composed from five
ordinary first-party object packages:

| Component | Requested root coordinate | Package-owned child |
| --- | ---: | --- |
| Athena | `(0,-2)` | none |
| Objective Board | `(1,-2)` | Objective Index at local `(0,0)` |
| Library | `(-2,2)` | Library Catalog at local `(0,0)` |
| Warehouse | `(2,2)` | Warehouse Directory at local `(1,0)` |
| Marketplace | `(0,2)` | Merchant at local `(0,0)` |

Applying the template installs or reactivates only its exact trusted packages,
creates `/Templates/default-khoros`, and maintains one active canonical Inventory
source per component. Canonical selection uses immutable
`InventoryTemplateSourceProvenance`; names, folder paths, compatible user sources,
and package types do not confer a template role. Moving or renaming a source keeps
its role. Deleting it leaves concrete facilities unchanged and makes the source
eligible for explicit recreation.

Every facility deployment has distinct package, Inventory, deployment, concrete,
and template-component lineage. Top-level facilities use ordinary package locks.
Their declared service children belong to the package graph and are not separate
Inventory sources. Objective, Library, and Athena events record exact facility IDs,
so replay never resolves authority by name or coordinate.

Preflight reserves placements in manifest order. An unrelated occupant causes
`world_template.placement_conflict`. Explicit `--auto-adapt` assigns only missing
conflicting components to deterministic nearest-free coordinates and records both
requested and actual positions. Healthy components retain their identities,
coordinates, state, listeners, reports, and descendants. Reapplication is a
zero-mutation success; repair deploys only missing components from the canonical
source’s current revision.

Template setup spans package visibility, Inventory, world, configuration, and
agent documents. A product transaction records exact targets, prior existence,
validated backups, staged hashes, and commit state. The next locked CLI invocation
rolls back an interrupted prepared transaction or completes cleanup of a committed
transaction before loading product state.

`khoros init` is the no-prompt composition of configuration creation, canonical
package/source setup, a world named `default-khoros`, template application, and one
unprofiled `agent` at root origin when the world has no registered agent. It makes no
provider call, never auto-adapts, and is idempotent. The agent’s Eye, backpack,
native Wallet at `(4,0)`, four holding positions, Scratchpad, Messenger, and
calculator are created by the agent lifecycle rather than the world template.

The schema transition is intentionally a clean break: only world schema 7, AgentStore
schema 3, and administrative snapshot schema 2 are supported. Coin/single-hand world
documents, older agent catalogs, and older administrative snapshots fail closed. No
automatic migration, legacy import, or compatibility conversion is part of this
runtime; a new product root/world must be initialized instead.

Built-in object families also include portals/keys, summoners, containers,
merchants, objectives, Library catalogs/documents, and Warehouse directories.

## 18. Configuration and diagnostics

`RuntimeLimits` owns every published numeric boundary:

- action and response characters/count;
- provider response bytes;
- model field/input/history/context characters and messages;
- notifications per request;
- protected verbatim overlap window;
- package, agent-catalog, Inventory, world, and report bytes; and
- Inventory folders, nested object calls, mounted folders, projected entries/tree
  depth, and projected file read/write bytes; and
- retained report count;
- console-history bytes; and
- console input characters, queue depth, history entries, and suggestions.

The economy adds fixed structural limits for two-decimal minor-unit amounts,
256-character wallet/record/custody identifiers and notes, 512 causal references,
10,000 accounts/custody entries per signed record, integral-second timestamps, and
the 1 MiB treasury-authority document. The world-byte limit bounds the retained credit
snapshot, signed chain, operation envelopes, and activity projection together.

All are positive installed-product settings exposed by
`config keys/get/set/reset`. Cross-field relationships are validated before save.

`khoros doctor` validates runtime configuration, the user-level agent catalog and
assignments, world replay, package-cache hashes and manifests, Inventory/package
lineage, credential-handle availability, deployment snapshots, template hashes and
event order, canonical source provenance, component placement and lineage,
listeners, reports, restock rules, and pending product-transaction recovery.

## 19. Security posture

The human is the ultimate authority. Runtime-issued identity, exact possession,
containment, `ObjectLocationIndex` bearer rights, locks, captured grants, signed
treasury records, and capability-mediated services authorize operations. Model text,
object metadata, package metadata, reports, remote results, wallet messages, and
persisted files before validation are untrusted data. Full wallet IDs are resolved
before authorization, and safe projections omit private records, credential handles,
and other bearers’ recursive subtrees.

The system contract contains no credential or authority secret. Prompt-context
overlap screening is defense in depth around outbound model actions; complete
mediation at runtime services remains the authorization boundary.

See [`security.md`](security.md) for the full threat model and verification matrix.

## 20. Future interfaces

The planned `khoros web` command starts a native macOS, Linux, or Windows host for a
loopback browser interface. The browser is a thin projection of the exhaustive human
command catalog, typed application services, `ObjectManagementInterface`, and the
runtime-owned base interface. The existing exhaustive catalog defines browser and
CLI inputs, and typed application results drive browser rendering.

The application shell has one app-view button whose custom menu contains World,
Agent Manager, Inventory, Packages, and Templates. World renders the persistent
world picker. Agent identities, Inventory sources, packages, and trusted template
definitions retain their user-global catalog scope. Forms for a global-view action
that requires a world collect one exact target locally and preserve the temporary
selection semantics of `--world`; changing the saved pointer remains the explicit
`world use` operation.

The World view renders exact world state, structural paths, agents, concrete
objects, reports, and object interfaces. The Templates view renders trusted catalog
definitions; template status, application, and repair resolve the exact world chosen
inside the action. Every object-specific field, action, view, and report surface is
generated from the selected object's structured interface and the runtime-owned base
description. Package-controlled values remain bounded untrusted data and never
become executable markup or browser code.

The browser transport calls the same locked and transactional services as the CLI.
It binds loopback by default, validates Host and Origin, makes an explicit local
session-authentication decision, protects mutations against CSRF, uses restrictive
content security policy, keeps credentials write-only, resolves complete identities
before authorization, and preserves canonical confirmation, cancellation,
capability, revalidation, and error boundaries. The visual and interaction contract
is [`ui-design-draft.txt`](ui-design-draft.txt); complete view placement and command
coverage are specified in [`design-v2.txt`](design-v2.txt).

The Hall and cross-world network require authenticated peer identity, message
integrity, replay protection, explicit cross-world authorization, and isolation.

The bearer-wallet slice deliberately does not provide network wallets, blockchain
consensus, external settlement or finality, cross-world credit transfer, custodial
key export, package-controlled finance, or a payment gate on Objective Board work.
Those are non-goals, not hidden guarantees. Any future Hall or cross-world economy
would need a separately authenticated protocol and a new versioned contract; it
cannot reinterpret this world-local signed chain as external money.
