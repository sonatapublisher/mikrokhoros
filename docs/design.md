# MikroKhoros runtime and Object SDK design

This document is the canonical engineering contract for the implemented product,
including its CLI and MikroKhoros Web browser interface. Security invariants are
specified in [`security.md`](security.md).

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

`ObjectManagementInterface` supplies structured metadata for the CLI and local
MikroKhoros Web:

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
MikroKhoros Web consumes the same service for its selected exact object panel.

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
the same world. `agent add` never creates a new identity. The World browser action
does not change focus or follow state and does not run provider processing; provider
follow-up remains a separate CLI workflow.

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

## 20. MikroKhoros Web

`khoros web` serves a native macOS, Linux, or Windows loopback host from the same
`khoros` executable as the CLI. MikroKhoros Web is a browser interface, not a
separate `.app` bundle or Node process. It has five primary views in one custom menu:
World, Agent Manager, Inventory, Packages, and Templates. Settings is fixed in the
sidebar footer, and Help is a searchable global overlay. All rows are operational.
One server instance owns at most one listener lifecycle; listener startup is reserved
atomically, a repeated start fails explicitly, and shutdown releases only the
resources owned by that lifecycle. Overlapping stop callers join one completion
signal that resolves only after the lifecycle is idle, so an immediate restart is
well-defined. A start stopped before callback delivery never announces a stale URL.
The web adapter never invokes a CLI subprocess, opens an operating-system shell,
parses presentation output as state, or edits JSON files as an alternate runtime.

World is the spatial default and the only view with a persistent world picker.
Choosing a world changes the browser route without mutating the persisted
current-world pointer; `world use` remains the explicit state-changing operation.
The picker always ends with `Create new world`, including with an empty catalog or an
unavailable projection. Creation registers the issued exact bare world as current and
opens its exact route. Agent Manager, Inventory, Packages, and Templates remain
user-global catalogs. An operation that needs a world collects or inherits one exact
target inside the operation and never acquires a hidden persistent world context.

### 20.1 Capability catalog and execution

`CLIWebCapabilityRegistry` projects every live `CommandKind` exactly once
into a presentation-neutral descriptor. A descriptor supplies its canonical command
path, scope, interaction mode, fields, history policy, completion provider, refresh
targets, enabled state, and stable test references. The registry is execution and
Help infrastructure. Typed domain projections define browser navigation. Adding
a command to `CommandKind` is a compile-time exhaustiveness obligation for safe
execution and Help coverage. A disabled descriptor remains searchable reference
material and cannot be executed through the browser gateway.

MikroKhoros Web is built from five typed domain projections:

- `GET /api/v1/agents` supplies user-global identity, assignment,
  active-presence, visual, exact-equipment-link, and content-free pending-work
  availability data for Agent Manager. Retry is available only when the exact active
  agent has a profile and a positive bounded pending-work count; queue contents,
  sender, priority, and profile data remain absent.
- `GET /api/v1/inventory` supplies global folders, sources, readiness,
  field-presence metadata, bounded typed management fields, actions, views, and
  reports, lineage, and bounded identity data for Inventory. Each field carries its
  label, summary, kind, required/deployable state, safe declared default, choices,
  and numeric or text limits. Each action carries ordered parameters, input kinds,
  safe defaults and choices, mutability, required capabilities, scope, and a result
  schema. Views carry their source, scope, and result schema; reports carry their
  type, summary, title/body/payload bounds, and payload schema. Package-declared
  defaults are omitted for secret and path fields; configured source values remain
  private.
- `GET /api/v1/packages` supplies available and retained package
  identity/version, display metadata, runtime, requested capabilities, installation
  state, retained content hash and installation time where applicable, source
  retention counts, and management counts.
- `GET /api/v1/templates` supplies trusted definitions and every
  requested root and owned-object placement, including the requested parent space
  and coordinate for every row. Definitions have no runtime object identity, so the
  browser uses the neutral Phosphor Cube rather than synthesizing an identity
  silhouette.
- `GET /api/v1/settings` supplies semantic setting groups, typed
  non-secret values, product counts, a ready/current-world status summary, the
  current-world summary, and adapter declared/detected status.

All projection arrays are bounded and built under the canonical product lock after
pending-transaction recovery. The projections are read-only, do not parse CLI
presentation output, and omit credential handles and values, Inventory configuration
values, profile endpoints/history, private world state, treasury/admin material,
local executable paths, raw persistence documents, and capability closures. Settings
is the sole projection that presents current non-secret runtime configuration values.

The generic object panel is reached only from one selected exact Inventory source or
one selected exact concrete World object. It consumes the same bounded management
contract above, filtering declarations by their exact Inventory, World, or shared
scope. Host-owned controls render types and choices, enforce declared local bounds,
collect browser-safe ordered action inputs, and route the exact IDs and typed values
through the capability gateway. If the selected contract declares any filesystem-
path field or path-typed action input, its declaration remains visible but every
action and view in that contract is CLI-only. A configuration-backed view is
CLI-only even when the remaining contract is path-free. The gateway applies the same
rule after resolving the exact contract, rejects both setting and unsetting declared
path fields, and keeps path-free typed actions and non-configuration views available.
Package labels, schemas, reports, and results are inert data; package HTML,
JavaScript, and source-configured values do not become part of the interface.

The exact World-object projection covers placed, directly held, nested, and
agent-attached objects without inventing spatial placement. A coordinate is present
only when the object is actually placed in a `Space`; every result carries its
canonical structural path and a runtime-derived `canMove` flag. The endpoint rebuilds
the base summary from a bounded allowlist and projects the declared interface through
the same redacted management contract used by Inventory. Raw declarative action
implementations, private object state, configured values, credentials, and unsafe
path or secret defaults never enter the response.

Contextual interactions are finite forms, read-only projections, prepare/confirm
operations, write-only credential entry, explicit agent action submission, report
following, private reveal/close viewers, downloads, host status, and Help. Exact-ID
fields use bounded dynamic completion from the same completion resolvers as the CLI.
Filesystem completion is never exposed. Package installation accepts a built-in
package or a browser-safe HTTPS source. Its visible field label is **Trusted package
source**; valid values are an exact trusted `builtin:<catalog-name>` source or an
HTTPS URL with a host and no user information. Every redirect target is revalidated
under that same browser policy before it is followed. Secret set forces
noninteractive standard input inside the trusted adapter; environment sourcing and
raw secret command options are unavailable to the browser. Confirmation forms omit
`--yes`; commit injects it only after a session-bound single-use plan is explicitly
confirmed.

The neutral web capability protocol receives a trusted `ProductLayout`, opaque session
identity, and host lifecycle state out of band. `CLIWebCapabilityGateway`
converts typed values into one `InteractiveCommandSubmission`, supplies trusted
configuration/world/output/color globals, and invokes `CommandExecutor` in process.
It serializes finite execution, bounds values and captured output, never retries, and
returns inert stdout/stderr separately. Display commands include only fields whose
catalog history policy permits storage. Mutating successes identify the authoritative
views that must be refreshed.

Prepared plans expire after 90 seconds, bind to one authenticated session, normalized
targets, and the persistent-product SHA-256 fingerprint, and are consumed exactly
once. Commit revalidates that fingerprint inside the canonical product lock. The
gateway caps pending and consumed plan state. A request from another session cannot
consume the plan. Credential bytes are capped at 16 KiB, passed once through bounded
in-memory standard input, cleared by the client after every outcome, omitted from
display commands and persistence, and never returned by the transport. Report
following is a cancellable, session-expiring chunked text stream of canonical
exact-world report projections. It has a global concurrency cap, a newest-snapshot
buffer, and one awaited transport write at a time. Agent control remains an in-world
action channel and cannot expand into an operating-system shell.

Named controls in a selected domain view open only a compact contextual action
surface. Agent Manager covers identity, profile, assignment, and active presence;
equipment links open the exact object interface, where Wallet, Messenger, and
object-management interaction lives. Inventory and World use the generic
`ObjectManagementInterface` renderer only after a source or concrete object is
selected. Templates collect an exact target World within status/application actions
and never own persistent World chrome. Template composition lists each root and owned
object by package and requested parent-space coordinate; Create World is a compact
overflow action, while status and application remain visible action-local forms.
Each definition row uses the neutral Phosphor Cube until application creates a
concrete object with canonical identity.
Settings uses fixed semantic sections.

The Help command is represented by the searchable full command reference: topic
search and the complete catalog present command documentation. `web` is represented
by finite Local host status, and `config path`
reports selection without returning a host filesystem path. World retains its
spatial map and bounded immediate console; World management and object actions remain
in their selected context. Raw `inventory show` configuration output is disabled in
the browser. Raw `inventory copies show` and `world object show` administrative
output is also disabled; bounded domain and exact-object projections are the browser
representation for those targets. When an allowed browser mutation prints an
Inventory object, its configuration map contains only a presence boolean per key;
the local terminal retains the full human-management presentation.

### 20.2 World projection and interaction

For each data request the projection service acquires the canonical product lock,
recovers any pending product transaction, loads configuration, catalog, Inventory,
and the exact persisted world, then constructs a verify-only `WorldRuntime` with no
treasury signer or credential store. The bounded projection contains the world
catalog, selected container and structural path, exact-world active agents in stable
order, visible objects, report summaries, and the global Inventory-source count.
One response retains at most 128 world-picker entries, 128 other-agent rows, and 256
objects from the selected space. Retained reports form the newest-first prefix that
fits both the configured count limit and one aggregate 256 KiB encoded budget.
Missing or invalid signed world material fails closed and is never repaired by the
browser.

Every retained report summary is exact-world data: it includes the report ID and
timestamp, world and concrete-object IDs, Inventory source and revision, package and
version, declared report type, title, body, and structured payload. The reports
popover is a quick World entry point; opening its object uses the report's exact
concrete-object ID rather than a name, coordinate, or inferred lineage.

The sidebar keeps My view separate from the active-agent roster. The collapsed roster
shows the first three agents in stable per-world order. At three or more active agents,
`All X agents` expands the complete roster inline with the same row treatment and no
trailing count badge. Explicit agent selection starts scoped follow without changing
the saved My-view container, camera, zoom, or roster order. Selecting My view restores
that saved state. Adding an agent is a separate exact-world action and never starts
focus, follow, or provider processing.

The World page supports focus and follow, pan, zoom, recenter, label visibility,
activation-opened coordinates and summaries for both empty and occupied positions,
nested-container navigation, local pinned-object shortcuts, and a reports popover.
When an object-bearing cell dropdown is open, the next primary click on an empty
cell closes that dropdown and is consumed; a later activation opens the empty-cell
dropdown normally. Crossing the drag threshold continues into ordinary World
panning.
Pointer and keyboard-cell context updates the Agent/Object information tabs;
`C` keeps the current or most recently pointed-to coordinate after pointer exit and
releases it back to live pointer/keyboard context. `1`, `2`, and `3` select Output,
Agent, and Object outside editable, modal, inspector, and menu surfaces. Activation
opens a cell menu or inspector. A selected object opens one generic
inspector sourced from its exact `WorldRuntime.worldManagementInterface`. Package
values are rendered as inert text through host-owned components; package HTML and
JavaScript are never accepted. Consequential object operations execute only through
catalog-derived typed forms and ordinary runtime authorization.

The client may retain bounded presentation preferences for exact-world pins, the
latest-seen report ID, My-view container/camera/zoom/keyboard state, and the last
inspector tab for an exact world/object pair. These are validated route and rendering
hints. They are not product persistence, current-world selection, identity,
authorization, or command history.

The browser shell has one scroll owner for each independently usable region: the
World sidebar's middle, a domain sidebar's content, and the web workspace.
Their header, search/filter area, contextual actions, and footer remain fixed within
their own regions. Each view and selected domain entity restores a page-memory scroll
position only while that page remains open; no scroll position enters persistent
preferences. On desktop the sidebar may be resized through its focusable vertical
separator. The expanded width is a clamped presentation hint with a 208px minimum,
240px default, and a dynamic maximum of 352px that always leaves at least 480px for
the main workspace. Pointer dragging uses capture and cancellation; Arrow keys,
Home, End, and `0` provide an equivalent keyboard resize/reset path. The separator is
disabled when the sidebar is collapsed or the viewport is at most 760px wide.

### 20.3 World command console

The World view has a floating dock at the bottom of the map. Its input is a separate
40px-high monospace capsule; its output/context panel is a separate surface that can
be resized from a centered top pill within its bounded range or minimized. The
selected panel body scrolls internally. The panel presents horizontal `Output`,
`Agent`, and `Object` tabs. Short vertical separators divide the tabs, and the
selected tab owns the panel body. Output is a bounded transcript of command results.
Agent and Object context is selected from the World cell under the pointer and is
rendered exclusively in the corresponding panel tab while the World field keeps
quiet target feedback. Cell menus and inspectors require activation. Context is
derived from the currently selected exact World. Each context tab exposes a compact
`Press C to keep detail` control; the same key or control keeps the current or most
recent coordinate after pointer exit, then releases it back to live hover/keyboard
context. The tabs expose `1`, `2`, and `3` shortcuts for Output, Agent, and Object.
These shortcuts do not run inside editable fields, dialogs, inspectors, or open
menus. Kept context is page-memory presentation state and clears when the World or
shown container changes.

The input is a bounded exact-world catalog editor rather than a general shell. Its
autocomplete returns at most eight complete suggestions from the allowlisted
`CommandCatalog` definitions and their bounded completion providers. Syntax styling
is likewise a bounded rendering of the command line; it does not interpret or execute
arbitrary markup. The browser keeps at most 60 output entries and inserts returned
output and errors as inert text in memory. The transcript is not console history,
local storage, or a persistence document.

Each submitted line follows the same `CommandLineTokenizer`, `CommandParser`, and
`CommandExecutor` path as the terminal CLI. The host invokes the executor in process,
with no operating-system shell or subprocess. The exhaustive deny-by-default World
allowlist contains only:

- `help`;
- `world show`;
- `world template status`;
- `world object list`;
- `world object view list`; and
- `world object move`.

No other command becomes callable through this immediate console when added to the
catalog; the complete typed web capability catalog is a separate boundary. The console
supplies configuration, output, color, and the exact selected World as
trusted execution context; user input cannot provide alternate global options. Every
request carries the selected World ID, which is validated against the catalog and
world file before execution. `world show` must resolve its selector to that same ID,
and no command can cross the selected-world boundary.

The client keeps submissions in a bounded FIFO queue and never retries a failed or
busy request. The service permits one in-flight command; a concurrent request is
rejected as busy. Source, request, suggestion, output, and transcript bounds are
enforced independently. A successful `world object move` marks the result for
refresh, after which the browser reloads the authoritative projection for the same
selected World; read-only commands do not mutate the projection.

`WorldCreationService` is the shared service boundary for bare creation. Its
public entry validates the name before any side effect, acquires the exact product
lock, recovers pending transactions before loading product documents, and loads the
configuration, agent catalog, world catalog, and Inventory from one `ProductLayout`.
It loads the canonical treasury authority or bootstraps it only when both catalogs
are empty. Treasury bootstrap commits through its own recoverable transaction and is
never rotated or removed by a later world-write failure.

The shared assuming-locked core is also used by the CLI's bare `world create` path.
It constructs `WorldRuntime` with the canonical treasury authority, then wraps the
Inventory document, world catalog, and new exact world file in one product
transaction. It preserves active Inventory artifact references, persists the
runtime-produced schema-7 world document, registers it as current, and commits. A
failure restores the prior catalog and Inventory state and rolls back the new world
target. Template creation remains in the existing trusted-template command path.

### 20.4 Loopback transport

The default host binds exactly `127.0.0.1:47567`. `--port <1...65535>` selects one
other exact port with no fallback, while `--available-port` is the only mode that
atomically asks the operating system for an available port. The options are mutually
exclusive. The host prints one fragment-bearing, short-lived launch URL after
binding. The bootstrap value is cleared from browser history before a same-origin
exchange for an opaque,
nonpersistent, `HttpOnly`, `SameSite=Strict` session cookie whose name is scoped to
the actual bound port. Every data endpoint requires that session; the server validates
the exact Host and same-origin Origin, serves a fixed resource allowlist, applies
restrictive browser security headers, and keeps `/api/v1/world` and
`/api/v1/object` GET/HEAD-only. The printed
`127.0.0.1:<bound-port>` authority is exact: `localhost`, a different port,
comma-joined Hosts, and forwarded-host aliases are rejected with the same bounded
generic error.

Stable and explicit-port startup never retries on another port. After a bind
collision, a bounded loopback-only `HEAD /` probe may classify a reachable listener
as MikroKhoros Web through `x-mikrokhoros-listener: khoros-web/1` or as another local
service so the CLI can give useful recovery guidance. The marker is advisory only:
it grants no authority, carries no session, and never causes the new process to
attach to an existing listener. A bind failure without a confirmed reachable
listener remains a generic bind failure rather than a false port-collision claim.

`GET` and `HEAD` of the root document accept a bounded, non-authorizing route-hint
query only: `view`, `world`, `container`, `focus`, `agent`, `source`, `folder`,
`package`, `version`, `template`, and `setting`. Each key appears at most once and
the normal route-value bounds apply. This serves the fixed shell for an active-session
same-origin deep link or reload without treating the query as authority. Every
non-document static asset and every API route retains its endpoint-specific
fail-closed query policy.

The browser agent contract includes:

- `GET /api/v1/world-agents?world=<exact-world-id>`: exact query selection returns a
  bounded list of user-owned agent identities with their availability for that exact
  World. Private profiles, genesis equipment, credentials, and runtime state are absent.
- `POST /api/v1/worlds`: accepts one exact bounded JSON object containing one
  string `name` and creates a bare world.
- `POST /api/v1/world-agents`: accepts one exact bounded JSON object with only
  `{worldID, agentID, x, y, autoAdapt}` and places an existing identity at a target
  coordinate in the selected world.
- `POST /api/v1/world-command/completions`: accepts one exact bounded JSON object
  `{worldID, source}` and returns at most eight catalog-derived suggestions for the
  selected World.
- `POST /api/v1/world-command/execute`: accepts the same exact body and executes one
  allowlisted command against the selected World, returning bounded standard output,
  standard error, status, and a refresh flag.
- `GET /api/v1/agents`: returns bounded user-global identity,
  assignment, active-presence, visual, and exact equipment-link summaries for Agent
  Manager, plus a content-free bounded pending-work count and safe retry availability.
  It excludes profile details, messages, balances, and private object data.
- `GET /api/v1/inventory`: returns bounded global folder/source,
  readiness, field-presence, complete declared management metadata, lineage, and
  visual data for Inventory. It excludes configuration values, credential handles or
  values, and management state.
- `GET /api/v1/packages`: returns bounded available and retained package
  catalog metadata, installation state, retention counts, and management counts.
- `GET /api/v1/templates`: returns bounded trusted template definitions,
  components, and root/owned-object placement summaries with requested parent spaces
  and coordinates.
- `GET /api/v1/settings`: returns bounded semantic setting groups with
  current non-secret runtime values, product counts, ready/current-world status,
  current-world summary, and adapter declared/detected state.
- `GET /api/v1/web/capabilities`: returns the exhaustive bounded descriptor
  catalog for the authenticated session as execution and Help infrastructure.
- `POST /api/v1/web/completions`: returns bounded catalog values for one
  declared field and trusted product/world context.
- `POST /api/v1/web/execute`: runs finite form, projection, private-view,
  download, or host-status operations. A complete accepted download is an
  attachment; command failures and outputs that exceed the finite browser transfer
  budget are ordinary rejected JSON execution results.
- `POST /api/v1/web/prepare` and `/api/v1/web/commit`: create and
  consume one explicit session-bound confirmation plan.
- `POST /api/v1/web/secret`: submits one write-only credential value.
- `POST /api/v1/web/agent-controller`: submits one explicit bounded in-world
  action.
- `POST /api/v1/web/report-follow`: returns a cancellable chunked exact-world
  report stream.

All authenticated data POST endpoints enforce exact same-origin/session checks,
content type, query/body bounds, recursive duplicate-key rejection, exact top-level
keys, bounded string arrays, and typed bodies before mutation or execution. Unknown
fields and browser-supplied globals fail closed. The world-agent endpoint has a 1 KiB
payload ceiling. Command bodies have an 8 KiB ceiling and source has a
4,096-character ceiling; web capability bodies have a 64 KiB ceiling; captured web
capability stdout and stderr share one aggregate 256 KiB cap. Malformed, expired,
changed, busy, and transient
requests return only bounded generic status bodies. `agent add` remains distinct from
`agent create`: it does not create identities, alter focus/follow state, or run
provider processing. Successful mutations refresh only the relevant authoritative
projections.

The visual and interaction contract is [`ui-design-draft.txt`](ui-design-draft.txt),
the complete view and command placement is [`design-v2.txt`](design-v2.txt), and the
source-backed association rationale is [`web-ux-decisions.md`](web-ux-decisions.md).
World-required forms retain the temporary exact-target semantics of `--world` and
canonical confirmation, capability, transaction, and revalidation boundaries.

The Hall and cross-world network require authenticated peer identity, message
integrity, replay protection, explicit cross-world authorization, and isolation.

The bearer-wallet slice deliberately does not provide network wallets, blockchain
consensus, external settlement or finality, cross-world credit transfer, custodial
key export, package-controlled finance, or a payment gate on Objective Board work.
Those are non-goals, not hidden guarantees. Any future Hall or cross-world economy
would need a separately authenticated protocol and a new versioned contract; it
cannot reinterpret this world-local signed chain as external money.
