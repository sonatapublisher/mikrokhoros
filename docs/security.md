# MikroKhoros security architecture

This document defines the implemented trust model for the CLI and complete local
MikroKhoros Web browser interface. Private vulnerability reporting is described in
[`SECURITY.md`](../SECURITY.md), and product behavior is specified in
[`design.md`](design.md).

## Security objective

An LLM proposes bounded actions for one concrete agent. It cannot identify its own
caller, grant capabilities, select another world, access a human-management surface,
or authorize a side effect. Swift runtime state is authoritative for identity,
possession, placement, recursive bearer property, locks, payment, package lineage,
capability grants, listeners, signed treasury state, and persistence. A Wallet is
spendable only when its exact registration and current `ObjectLocationIndex` bearer
agree with the invoking agent.

Prompt injection can influence model behavior. The enforceable boundary is that
model-visible or package-controlled text cannot independently acquire authority or
escape the world action and mediated object-service boundaries.

## Trust boundaries

Higher-trust components are:

- the human administration CLI and its validated configuration;
- compiled MikroKhoros runtime code;
- runtime-issued world, agent, object, Inventory, deployment, report, and invocation
  identities;
- the root treasury authority’s pinned Ed25519 public key and verified world-local
  signed-record chain;
- the canonical `ObjectLocationIndex` computed from registered containment, four
  holding roots, and agent backpacks;
- credential versions stored outside model-visible and exportable data; and
- capability grants captured by a concrete deployment.

Untrusted structured data includes:

- Messenger messages, object names, summaries, public metadata, and function results;
- package files, package-declared management contracts, reports, and remote results;
- Library documents and other fetched content;
- provider output, earlier model-visible history, and compaction records;
- configuration, agent-catalog, Inventory, credential-handle, and world files
  before validation;
- wallet messages, requested funding text, wallet selectors, package/object names,
  and management inputs before exact-ID and bearer checks; and
- repository issues, examples, linked pages, and quoted text used by coding agents.

The agent system contract has greater model-message authority than mutable world
data. It is public protocol text, never a credential or authorization database.

## Agent request and output boundary

- `AgentModelRequest.system` contains the stable action and world contract.
- `AgentModelRequest.input` contains a quoted event and current-state envelope.
- Provider adapters preserve distinct message roles end to end.
- Every request rebuilds the complete system contract, including requests made after
  history compaction.
- The current user-role request is the only source of live state. Compaction emits a
  bounded data-only checkpoint and does not generate a prose state summary.
- Mutable values are bounded and JSON-quoted. Invisible Unicode formatting controls
  are rendered visibly in input and rejected in model output.
- Provider response bytes, response characters, action count, individual action
  characters, input, history, total context, and carried notification count are
  independently configurable.
- Every nonempty output line must parse as one complete world action. Markdown,
  prose, operating-system shell syntax, and undeclared actions fail before execution.
- The configured action prefix executes in order and stops at its first runtime
  error. Excess lines produce a bounded warning and are not executed.
- Rejected provider output is not persisted, reflected into the next request, or
  reproduced in error details.

Successful action results contain the validated command once as an action receipt.
Rejected or failed actions omit the candidate command. Raw provider output is never
forwarded automatically to Messenger, an object, another agent, a report, a remote
service, or a log.

Before execution, candidate output is screened for long normalized word windows
copied from the system contract, the current request, or earlier provider-visible
user context. A match fails without reproducing it. This overlap test is defense in
depth: fragmented, encoded, or paraphrased disclosure can evade exact comparison, so
authorization never depends on it.

## Runtime mediation

Identity and authority are derived from exact runtime instances:

- agent operations use the registered agent object;
- object invocation uses the registered concrete object, world, and caller;
- package and Inventory lineage is metadata, not caller authority;
- `ObjectLocationIndex` derives recursive bearer ownership from exact containment,
  four holdings, and backpacks; ambiguous, orphaned, cyclic, or over-depth graphs
  fail closed;
- pickup locks, containment, possession, material occupancy, wallet authority,
  custody, and payments are checked at their state-transition boundary;
- holding roots are nonmaterial, but their recursive contents remain private to the
  bearer; holding selection never changes ownership;
- broadcast source, unread event, and exact holding/backpack possession are
  revalidated while building each model request; and
- a Messenger address resolves to the recipient agent’s stable genesis Messenger,
  while notification eligibility depends on that exact object’s current carrier.

Human Inventory actions and views never invoke the agent-facing function registry.
Native generic world-object actions and views use exact object identity, typed bounded
inputs, current revision, and a safe projection. Human management data remains
outside agent prompts and histories.

## Wallet, treasury, and property-rights boundary

The economy is a local signed ledger, not an external money system. The runtime
creates one reserved native `wallet.object` per agent and places it in the agent’s
backpack at exact coordinate `(4,0)`. The object contains no spendable balance and
cannot be copied, fabricated, deployed from an Object SDK package, or deleted as an
independent object. A wallet debit requires the exact registered wallet ID, current
agent bearer, world ID, issuer/key ID, original backpack provenance, and agreement
between the signed custody commitment and the current `ObjectLocationIndex` owner.
A stale registration or custody record, copied type, name, prefix, or coordinate is
not authority. A valid journaled move may deliberately transfer bearer rights.

Credit amounts use at most two decimal places and signed 64-bit minor units. Finite
wallets reject agent transfers and merchant purchases that would produce a negative
post-balance. Unlimited wallets bypass sufficiency only for explicitly priced
merchant purchases, which apply zero while recording the positive nominal amount;
peer transfers remain limited by the retained finite shadow balance. All modes use
the same exact IDs, signed records, integer-overflow and exposure checks, and
persistence limits. A normal Messenger message can request or announce funding;
message text is untrusted and cannot mint credit, alter wallet mode, or authorize a
deposit. Human funding must cross the typed native management/treasury boundary.
Objective posting is human-only through the exact Objective Board management
provider. Agents may discover human-posted work through Objective Board/Index and
invoke `read`, `register`, `progress`, `final`, and `revision` on a child Objective;
none of those work operations has a payment gate.

The root treasury authority is generated once and never silently rotated. Its
authority document contains an Ed25519 public key, a domain-separated derived key ID,
creation time, and an opaque private-credential handle; the private key bytes are
outside world/model/export data. Bootstrap requires explicit confirmation that no
economy state already exists. The authority document is capped at 1 MiB and is
written under the product lock with recoverable atomic replacement.

Every credit record is signed by the pinned authority and binds the exact world and
key IDs, operation/transaction/action IDs, actor, wallet account IDs, signed deltas,
post-balances, mode, treasury delta/balance, and bounded causal references. Canonical
bytes sort account/custody data before hashing. The chain starts at a 64-zero genesis
prior hash; each next record must name the previous signed-record hash. Verification
rejects wrong world, authority key, signature, prior hash, duplicate record ID,
unknown fields, malformed time, malformed balances, and over-limit records. The
treasury invariant is `treasuryBalance = totalDebt - totalPositive`: the treasury
holds the exact signed negative of net wallet issuance, and every accepted operation
must preserve it.

World event persistence groups cross-surface changes in an operation envelope. The
envelope carries exact operation/world/actor identity, timestamp and action index,
optional idempotency key, signed credit records, object revision mutations, receipts,
unread/acknowledgement changes, and sanitized activity. The world lock serializes
application. Replay verifies each signed record and current object/bearer state,
rejects revision regression and invalid notification possession, and treats a
previously applied operation or record ID as idempotent. A missing or mismatched
private credential enters verify-only mode: signed history and balances can be
inspected and verified, but credit mutation fails closed.

Signed custody entries bind an exact wallet to the old and new bearer, old and new
canonical location commitments, and the previous custody commitment. They are
accepted only when the old commitment matches the chain and the new commitment is
derived from the current location index. This prevents a raw move, stale snapshot,
or package-controlled metadata from silently changing property rights.

Security/resource bounds include 256-character wallet, record, custody, and note
identifiers; 512 causal references; 10,000 accounts and custody entries per record;
integral-second record time; configured world/document bytes; and the 1 MiB authority
document. These protections provide local integrity, replay safety, and privacy. They
do not provide blockchain consensus, network settlement, external finality, or
cross-world wallet transfer.

## Guided human console boundary

The guided console is a presentation and scheduling layer over the ordinary human
command path. It does not parse or execute the agent action language and cannot run
operating-system shell syntax. Both one-shot tokens and completed forms pass through
the same `CommandParser`, `ParsedCommand`, `CommandExecutor`, product lock, typed
handlers, output encoding, confirmation rules, and secret handling.

Form collection intentionally does not authorize or validate a command. Defaults and
global context are captured in the queue item, then each execution reloads validated
product state. Completion providers perform bounded reads of local catalogs,
world IDs, declared choices, and filesystem names. They do not invoke objects,
AI profiles, package actions, remote endpoints, or subprocesses.

The console renderer is the sole terminal writer while the editor is active. A command
that requests a confirmation, hidden secret, or raw agent action becomes a
foreground barrier. Hidden values are not placed in drafts, completion data, queue
summaries, output, errors, or history. Terminal modes are restored on success,
ordinary failure, cancellation, forced exit, termination signals, and object
deinitialization. Untrusted strings are stripped of terminal control characters before
human rendering. Machine renderers never emit ANSI.

Console history is versioned, byte- and entry-bounded, structurally validated, locked
against concurrent writers, synchronized, atomically replaced, and owner-only on
POSIX systems. It stores only explicit safe values selected by the command definition.
It omits secret data, hidden input, messages, objectives, raw actions, URLs that may
carry credentials, management `field=value` payloads, command output, accepted
defaults, context paths, wallet funding bodies, full wallet IDs, custody material,
and queue state. Wallet balances and signed statements are exposed only through
explicit human reads or an agent’s own bounded Wallet surface.

An `&` prefix is session scheduling metadata only. It cannot change command authority;
it pauses pending FIFO work after that item returns an error. Console controls are an
exhaustive separate type and never reach the product parser.

Unique names and shortened identities are display and input conveniences. Resolution
is scoped to the selected entity store, world, or container; ambiguity is a
typed no-mutation failure. The resolved complete runtime identity is the only value
used for authorization, event creation, or persistence.

## Object packages and SDK services

Package installation strictly decodes the unified manifest, validates identifiers,
semantic versions, contracts, capabilities, and runtime availability, and commits a
package plus any package-selected default Inventory object atomically.

The installed declarative adapter exposes a closed action set. It cannot import code,
launch a process, access files, or contact the network. JavaScript packages fail at
installation until a sandboxed adapter exists. Native Swift objects are trusted code
compiled and registered by the host; package metadata cannot activate native code.

The finance boundary is not an SDK capability. Package code cannot mint/debit/deposit
credit, change finite/unlimited mode, sign or append treasury records, forge custody,
derive bearer rights, or create/copy the reserved Wallet type. It can expose ordinary
functions and typed human-management contracts. Exact native generic human-management
providers are limited to Wallet, Messenger, and Objective Board; their actions are
mediated by exact object identity, current revision, typed limits, and the
treasury/property-rights checks above. Agent-owned Wallet `transfer` and trusted
Merchant `buy` are separately mediated agent object functions, and `buy` requires an
exact full payer Wallet ID. Objective Index and Merchant have no native generic
human-management provider.

External runtime adapters receive constrained contexts:

- `AgentObjectContext` for an agent-facing invocation;
- `UserObjectContext` for human actions and views;
- `ObjectDeploymentContext` while constructing a copy; and
- invocation-scoped `ObjectReportEmitter` for human-facing reports.

Protected world, network, and user-machine operations are available only through
mediated services. `ObjectCapabilityBroker` checks the concrete object’s captured
grant at every protected operation. World-instance actions receive a constrained
management context with exact identity and bounded mutation services. External
package APIs never expose `Harness`.
Changing an Inventory grant affects future deployments; existing copies retain their
captured grant set.

Public functions declare whether agents, other objects, or both may call them.
Nested calls preserve the runtime-issued original agent, calling object, target,
world, lineage, root/current invocation IDs, and depth. Relative resolution selects
only the exact coordinate in the caller’s immediate space. The configured depth
limit bounds recursion, and durability changes only after success.

## Live host-folder bindings

A user-workspace source accepts a host folder only after it is forked and bound to
one exact world. The canonical host path remains human management data. Deployment
captures opaque binding IDs, aliases, access modes, coordinates, and the source’s
`user-machine` grant.

Object code accesses host data through `ObjectUserFolderService`. Every list, read,
write, append, or clear operation verifies:

- the concrete instance’s captured `user-machine` grant;
- ownership of the opaque binding ID;
- canonical containment beneath the mounted root;
- absence of followed symbolic-link components;
- the current host entry type;
- read-only or read-write mount policy; and
- configured entry, depth, read-byte, and write-byte limits.

Projected objects expose aliases and relative paths to agents. Absolute host paths
stay in human administrative state. Symbolic links are visible non-traversable
objects. Unsupported entries do not become traversable world objects. UTF-8 text
operations fail without replacement when existing content has another encoding.
Writes use atomic replacement where supported and restore POSIX permissions when
available.

Folder contents reconcile at ordinary interaction boundaries. External filenames,
file contents, errors, and object results remain bounded untrusted data. They do not
enter the system contract or acquire instruction authority.

## Package acquisition and retention

- Package byte limits are configured by the installed user.
- Local files are size-checked before decoding.
- Remote downloads use an ephemeral session and enforce the limit incrementally.
- Remote sources require HTTPS, except plaintext loopback URLs for development.
- Every redirect target is validated before following it.
- Package ID/version collisions with different content fail closed.
- Package bytes are addressed by SHA-256 content hash and retained for referenced
  Inventory objects and immutable deployment snapshots.
- Removing a catalog entry hides that version without invalidating existing state.

## Inventory, credentials, and deployments

An Inventory object has no world location, bearer/holding state, lock, Wallet
authority, or agent-visible function surface. Mutations require an explicit human
command and increment its revision after complete validation.

Secret fields use immutable credential versions:

- interactive entry disables terminal echo;
- automation reads stdin or a named environment variable at command execution;
- Inventory and world documents store only opaque handles;
- a deployment captures the selected handle versions;
- output reports only presence and usability;
- secret values are excluded from prompts, model history, package metadata,
  administrative snapshots, world exports, logs, errors, and reports; and
- deleting or replacing a source reference does not alter an existing copy.

Deployment validates package availability, complete configuration, credential
handles, grants, and destination before mutating a world. The journal stores a
self-contained snapshot with package content, configuration, credential handles,
grants, initial state, durability, lock, and runtime-issued lineage. Replay builds
the copy from that snapshot rather than consulting current Inventory state.

Copy deletion resolves an explicit object, deployment, or all-descendants scope in
the selected world. The CLI previews recursive containment consequences,
confirms destructive execution, and revalidates targets immediately before an atomic
world mutation.

## Human listeners and reports

A listener belongs to one exact Inventory-backed world-object ID in one world.
The runtime accepts a report only when:

- that exact listener is enabled;
- the emitting object is still registered;
- the report type is declared by its retained package;
- title, body, payload shape, package payload bound, and installed-product report
  bound all validate; and
- world, object, Inventory revision, package, and deployment lineage comes from the
  runtime object rather than report content.

Report text and payload remain quoted untrusted data. Listening does not notify an
agent, invoke a profile, or produce a Messenger message. Disabling a listener stops
future delivery without changing stored reports.

## Persistence and diagnostics

- Configuration, agent-catalog, Inventory, console-history, and world documents are versioned,
  size-bounded, decoded into typed schemas, semantically validated, and atomically
  replaced after storage synchronization.
- The current persistence contract is world schema 7, AgentStore schema 3, and
  administrative snapshot schema 2. Coin/single-hand formats and all other versions
  fail closed; there is no automatic migration, legacy import, or compatibility
  conversion.
- The world catalog maps exact runtime IDs to managed files and owns the human
  current-world pointer. World paths are derived from those IDs; names, caller paths,
  and the process working directory never grant world authority.
- `--world` is a one-command selection. `world use` is the only ordinary command
  that changes the saved current-world pointer. The retired `--workspace` option is
  rejected before stores are mutated.
- Mutating CLI processes serialize through a user-global product lock.
- Agent creation writes a user-level record without world authority. World entry
  resolves the current or temporarily selected world to its complete runtime ID.
  An existing assignment prevents the same identity from being registered in a
  different world.
- World replay rejects duplicate, orphaned, contradictory, oversized, or
  semantically invalid events.
- World replay verifies four-slot holdings and `ObjectLocationIndex` ownership,
  applies signed credit records only in chain order, and rejects invalid operation
  envelopes, custody commitments, treasury invariants, or bearer notifications.
- Template setup uses a recoverable product transaction so interruption exposes either
  the complete prior or committed state. Transaction manifests authenticate affected
  worlds by exact runtime ID. World deletion defers credential garbage collection
  until that transaction commits.
- Package-created copies replay from immutable deployment snapshots and recorded IDs.
- Replay restores recorded projected identities and external-effect receipts without
  reading or writing a host folder. Live reconciliation resumes after replay, so a
  restart cannot repeat a pencil or printer write.
- `khoros doctor` validates configuration, agent identities and assignments, package
  cache hashes and manifests, Inventory identities, credential handles, deployment
  lineage, listeners, reports, and restock rules without mutating state.
- `world inspect` and `world export` are human-only reads. They may reveal private
  messages, notes, documents, and object state, but never credential values.
- Provider errors use bounded stable categories and exclude response bodies, headers,
  tokens, and endpoint-controlled text.
- Direct OpenAI Responses requests disable provider-side storage. Gemini credentials
  use a header. Custom credential-bearing endpoints require TLS.

### World-template integrity

World templates are host-registered trusted definitions, not executable package
metadata. The installed CLI accepts only the exact built-in `default-khoros`
definition and exact content-addressed first-party facility packages. A package,
Inventory source name, world-object name, coordinate, or compatible object type
cannot claim a template component role.

Template authority is carried by runtime-issued application, component, Inventory,
deployment, and concrete identities. Application preflight validates trusted hashes,
canonical-source provenance and readiness, exact selected world identity, replay
version, and occupancy. Commit revalidates the Inventory and world fingerprints.
An exact placement conflict changes no state; adaptation requires an explicit human
option.

Explicit setup presents one aggregate list of the missing Inventory additions.
Approval authorizes only that plan. `khoros init` uses the fixed installed default
composition and accepts no provider, credential, package hash, deployment ID, or
concrete ID input.

Multi-document template operations use a private transaction directory containing a
bounded manifest, prior-existence flags, integrity-checked backups, staged hashes,
and commit state. While holding the product lock, the next CLI process restores a
prepared transaction or verifies and cleans a committed transaction before loading
product state. The journal stores serialized product documents, which contain
credential handles but no credential values.

World replay constructs facilities from captured package snapshots before
events that target them. Objective, Library, and Athena events carry exact facility
IDs. There is no legacy migration path; a schema mismatch is rejected before any
facility or credit state is loaded. Template authority never comes from mutable names
or coordinates.

All published numeric limits are available through `khoros config`. Increasing a
limit deliberately increases memory, provider, persistence, or execution exposure.
Authorization and exact runtime identity checks remain independent of those values.

## Loopback browser boundary

`khoros web` serves MikroKhoros Web from the native `khoros` executable and binds
only `127.0.0.1`. The default is exact port `47567`; `--port <1...65535>` selects one
other exact port without fallback, and `--available-port` is the sole mode that
atomically asks the operating system to select an available port. The options are
mutually exclusive. The host exposes bounded World projections, five typed domain
views, fixed Settings, searchable Help, and contextual capability execution. The host is
in-process, but its presentation adapter receives allowlisted domain DTOs,
capability descriptors, and committed results. Descriptors support contextual
execution and Help; domain DTOs supply browser navigation and view content. The host
atomically reserves one listener lifecycle per server instance, rejects a concurrent
start, and releases only the resources owned by the matching lifecycle during
shutdown. Overlapping stop paths join the same completion and return only after the
matching lifecycle is idle; a stop that wins before launch suppresses the callback.
The listening bootstrap does not opt into cross-process address reuse. Stable and
explicit-port startup never probes for a replacement port. After a bind collision,
a bounded loopback-only `HEAD /` probe may use
`x-mikrokhoros-listener: khoros-web/1` to distinguish a reachable MikroKhoros Web
listener from another reachable local service. This marker is spoofable diagnostic
metadata, not identity, authentication, authorization, or permission to reuse an
existing session. A failure without a confirmed reachable listener stays a generic
bind failure and does not disclose platform error details.
The host does not invoke a shell or CLI subprocess, deserialize live domain
objects into ordinary browser responses, or expose canonical filesystem paths or
treasury key material. Ordinary projections omit credential handles, event journals,
model histories, private object state, and administrative snapshots. Two deliberately
private operations are explicit exceptions: `world inspect` reveals a bounded
administrative snapshot in the current local tab, and `world export` downloads the
private world journal. The export can contain histories, object private state, and
opaque credential handles, but never credential values or treasury signing bytes.
The UI labels these operations private, requires an explicit Reveal or Download,
clears revealed text on close/navigation, and warns the human to protect the
downloaded file.

Static files are a fixed bundled allowlist and contain no product data. Every data
route requires an opaque local session. After the listener is live, the command
prints a cryptographically random bootstrap value in the URL fragment. Browser code
removes the fragment from history before exchanging it once, within its short
lifetime, for a nonpersistent cookie with `Path=/`, `HttpOnly`, and
`SameSite=Strict`. The session-cookie name is derived from the actual bound loopback
port, so simultaneous `127.0.0.1` hosts cannot attach to one another's cookie. Bootstrap
and session values are not placed in local storage, browser responses, logs,
referrers, or subsequent URLs.

The root document is the sole static resource that accepts a route-hint query on
`GET` or `HEAD`. Its exact allowlist is `view`, `world`, `container`, `focus`,
`agent`, `source`, `folder`, `package`, `version`, `template`, and `setting`; each
key is single-valued and bounded. The hint only selects a client projection after the
normal session exchange and never authorizes data access or mutation. All other
static assets reject queries. API routes keep their endpoint-specific query contracts,
including query-free mutation routes. This permits an active-session same-origin
MikroKhoros Web deep link or reload without broadening the resource or API surface.

Local storage is limited to bounded presentation preferences: exact-world pin IDs,
latest-seen report IDs, My-view container/camera/zoom/keyboard state, last
inspector-tab IDs, and a clamped expanded-sidebar width. The client validates every
value before use. These values are untrusted rendering hints and never authorize a
route, selector, object, or mutation. Per-view and per-entity scroll positions remain
page-memory state and never enter local storage.

The server validates the exact printed loopback Host and the exact same-origin Origin
for each request. `localhost`, a changed port, comma-joined Hosts, and forwarded-host
aliases are rejected; forwarded headers never override the socket authority. Every
state-bearing endpoint requires the session and returns restrictive CSP,
no-referrer, MIME-sniffing, frame, permission, origin, and no-store headers.
The singular World/object projections accept GET or HEAD only. The two World command
routes are authenticated POST-only endpoints with no query component.

Authenticated `POST /api/v1/worlds` creates a bare world through one narrowly scoped
mutation route. It rejects a query, transfer encoding, inconsistent content length, a
missing or non-exact `application/json` content type, a body above 512 bytes, duplicate
or unknown JSON members, non-string values, and any name outside the canonical one-line
1–128 character contract. It never echoes a rejected value or internal error. The client
submits once, prevents concurrent submission, and does not automatically retry.

Authenticated `GET /api/v1/world-agents` is the World-actor query route in this slice.
It requires a `world` query, the exact loopback Host, and the local session; any
supplied Origin must match the exact loopback origin.
Malformed selectors, missing/invalid `world` values, and request-size abuse return
generic errors.

Authenticated `POST /api/v1/world-agents` adds an existing user-owned identity to one
exact world at integer coordinates. It requires only `{worldID, agentID, x, y, autoAdapt}`
with exact, typed JSON and no extra fields, and enforces a 1 KiB body ceiling. It
uses a recoverable product transaction; the canonical treasury authority remains
server-side when first entry requires Wallet registration. It returns generic status responses:

- success: 201;
- validation: 400;
- conflict: 409; and
- transient infra: 503.

It rejects malformed selectors, conflicts, and malformed coordinates with the same generic
error envelope. It does not create identities, does not auto-run provider processing, and
does not alter focus/follow state. A successful call returns only a bounded placement
result, after which the client reloads the authoritative World projection.

Authenticated `GET /api/v1/agents`, `/inventory`, `/packages`,
`/templates`, and `/settings` are bounded read-only domain projections. They acquire
the product lock after pending-transaction recovery and accept no browser-supplied
product root, configuration, CLI global, or authority context. Agent data contains
only public identity/assignment/presence, visual, and exact equipment-link summaries;
it excludes profiles, messages, balances, private object state, and object content.
The agent retry affordance derives only from a bounded content-free pending-work count
for an exact active agent with a profile; it does not expose or interpret queued
work. Inventory contains folders, source summaries, readiness, field-presence
metadata, immutable fork/template provenance, and visual identity. Its selected exact
source management contract is bounded declarative metadata: field kind/requiredness/
deployability/safe default/choices/limits; ordered action input types/defaults/
choices/mutation/capability/scope/result declarations; view source/scope/result
declarations; and report type/payload-limit/schema declarations. The source's actual
configuration values, credential handles or values, and management state remain
absent. Packages contain catalog and retention metadata: identity/version/display
summary/runtime/requested capabilities, installation state, retained content hash and
time when available, source counts, and management counts. Templates contain trusted
definitions and bounded root/owned-object rows with their package, requested parent
space, and coordinate. Settings contains explicitly typed non-secret runtime values,
product counts, ready/current-world status, current-world summary, and adapter
declared/detected booleans. None of these routes expose private world state, history,
treasury material, administrative snapshots, local executable paths, raw persistence
files, or executable capability closures. Projection data is inert presentation data
and never authorizes a mutation.

Authenticated `GET /api/v1/object` resolves only one exact non-world object inside
one exact World. Placed, nested, directly held, and agent-attached objects share the
same endpoint. Non-spatial objects expose no fabricated coordinate; the response
contains a bounded structural path and runtime-derived move availability. The host
rebuilds the base summary from allowlisted identity, location, lineage, capability,
and function metadata, then applies the same bounded management-contract projector
used by Inventory. Raw declarative actions, private state, public-data blobs,
configured values, credentials, and unsafe path or secret defaults are excluded.

The World command routes accept exactly the primitive JSON object `{worldID, source}`.
They reject duplicate or unknown members, a query, transfer encoding, inconsistent
content length, a missing or non-exact `application/json` content type, unauthenticated
or cross-origin requests, and malformed IDs. The body is capped at 8 KiB and the
source at 4,096 characters; newlines and NULs are rejected. Completions are capped at
eight catalog-derived suggestions. Execution captures standard output and standard
error through an in-process, noninteractive `CommandExecutor` transcript with each
channel capped at 65,536 bytes. The host never invokes an operating-system shell or
subprocess.

The command policy is exhaustive and deny-by-default. Only `help`, `world show`,
`world template status`, `world object list`, `world object view list`, and
`world object move` are callable from the World page. Management interfaces and
action metadata are available only through the bounded typed object projection, not
through raw command output. A new `CommandKind` remains unavailable until the
explicit policy switch is reviewed. Global options in the browser source are
rejected; the service injects configuration, human output, no color, and the exact
selected World itself. The request World ID must exist in the catalog and have its
world file, and `world show` must resolve any supplied selector to that same ID. This
prevents a route, selector, or stale browser request from crossing the selected-world
boundary.

One World response retains at most 128 picker entries, 128 other-agent rows, and 256
objects from the selected space. Reports are newest-first and share an aggregate
256 KiB encoded budget in addition to their configured count limit. Agent-selection
options use a deterministic caller-clamped prefix with a hard maximum of 256.

The browser keeps a bounded FIFO queue in memory and does not retry failed, rejected,
or busy commands. The service allows one in-flight execution and returns a generic
`409` while another command is running. The browser renders returned command, output,
and error strings with text nodes only; the transcript is inert, memory-only state and
is not written to console history, local storage, a world document, logs, or URLs. A
successful `world object move` returns a refresh flag, and only then does the client
reload the authoritative projection for that same selected World. Read-only console
commands do not mutate or refresh world state.

The web capability route is a separate deny-by-default boundary around the
complete command catalog. `GET /api/v1/web/capabilities` returns only bounded
execution and Help metadata: canonical paths, summaries, scope, interaction mode,
field syntax/cardinality, safe defaults, completion names or fixed choices, refresh
targets, enabled state, and test references. It does not return configuration paths,
environment values, credentials, product bytes, histories, or executable closures.
Descriptor data supports contextual execution and Help. The registry switch is
exhaustive over `CommandKind`, so a new command cannot compile without an explicit
safe execution and Help policy. `inventory show` is a disabled reference because its
terminal output contains configured source values. `inventory copies show` and
`world object show` are disabled references because their terminal output contains
raw administrative object snapshots. Crafted execution requests are rejected before
dispatch; bounded domain and exact-object projections are the browser representation
for those targets.

Web capability POST bodies are capped at 64 KiB. A recursive JSON validator rejects
literal and escaped duplicate keys before Foundation materializes nested objects.
Each endpoint then requires exact top-level keys, bounded field-name to string-array
maps, one capability ID, and an optional exact world ID. Browser requests cannot
supply configuration, output, color, root, session, or other CLI globals; the host
injects those from the authenticated launch context. Filesystem completion is empty.
The install control is labelled **Trusted package source** and accepts only an exact
trusted `builtin:<catalog-name>` source or an HTTPS URL with a host and no user
information; every redirect target must satisfy the same browser policy before it is
followed. Browser-supplied host paths remain unavailable. If an exact management
contract declares any `path` field or path-typed action input, all actions and views
in that contract are CLI-only; a configuration-sourced view is always CLI-only. The
gateway independently resolves the selected exact contract and rejects path-field
set and unset requests as well as action/view execution across that boundary.
Path-free typed actions and non-configuration views remain available. The gateway
resolves a built-in source through the trusted catalog rather than treating its
label or suffix as filesystem input.

Gateway execution establishes a scoped browser-presentation context. When an
allowed command prints an Inventory object, every configuration entry is represented
only as `{present: Bool}`. No configured secret or non-secret value enters an
ordinary browser result. The context ends with that request; local terminal output
retains the full human-management presentation.

Finite execution is serialized and captured in process, with stdout and stderr
sharing one aggregate 256 KiB UTF-8 budget. Only catalog fields whose history policy
permits storage enter the inert command preview; any value containing whitespace or
shell-active punctuation is replaced wholesale with `value_omitted`. Clipboard copy
contains result text only, never the command preview. Returned output is inserted as
inert text. Private viewers require an explicit reveal and are cleared on close or
navigation. An accepted private export uses a bounded host-chosen filename and an
ephemeral browser object URL only when its complete output fits the aggregate finite
budget. Command failure or truncation returns an ordinary rejected bounded JSON
result with no attachment; the human can use the inert local CLI command for a
larger complete export. Host status is a finite projection of the current listener
and cannot recursively start another host. `config path` reports only
`[configuration file]` in the browser-safe presentation.

Consequential commands use prepare/commit. A prepared plan expires after 90 seconds,
binds to the authenticated opaque session, the normalized exact target, and a
SHA-256 fingerprint of the persistent product state, and is consumed exactly once.
Commit checks the fingerprint before execution and again after the command runtime
acquires the canonical product lock; intervening product changes reject the plan.
The gateway retains at most 128 pending plans and 256 recent consumed-plan markers.
A request from another session cannot inspect, commit, or invalidate a plan. `--yes`
is absent from the generated form and is injected only during a valid commit.
Replayed, expired, changed, unknown, or wrong-session plans return bounded generic
errors.

Credential set has one host-owned write-only value capped at 16 KiB. The browser
cannot select an environment source or inject raw stdin flags. The gateway forces
its own noninteractive stdin mode, consumes the bounded bytes once, omits them from
command display and result data, and the client clears the control after success,
failure, abort, or navigation. Agent control accepts only explicit in-world actions.
Report following is a cancellable, session-expiring, chunked exact-world stream and
never polls the filesystem from browser code. The gateway permits at most eight
concurrent report streams, keeps only the newest pending snapshot per stream, and
the NIO transport awaits each flush and closes a slow consumer when the channel is
not writable rather than accumulating outbound chunks.

Each World projection request holds the product lock through pending-transaction
recovery and projection. Persisted world credit is verified by a runtime constructed
without a treasury authority or credential store. Unavailable or invalid material fails
closed;
after canonical recovery, the projection never bootstraps, repairs, signs, or
persists world state. Package, object, and report strings are untrusted display data
and enter the document only through typed node creation and text content.

Creation validates before acquiring the product lock. The service then
recovers pending transactions before loading exact product stores, resolves the
canonical treasury authority, and persists the runtime-produced bare world through a
recoverable transaction covering the Inventory document, world catalog, and new
world file. Treasury bootstrap is a separate recoverable transaction and never
rotates an existing authority. Browser responses contain no signer or credential
material.

## Verification

Regression coverage exercises:

- quoted injection-shaped Messenger, object, Library, and report data;
- rejected output non-echo and non-persistence;
- current and earlier request-context overlap detection;
- compatibility normalization and invisible formatting controls;
- role-preserving provider adapters and system-contract reinjection after compaction;
- capability denial, trusted invocation identity, and grant snapshots;
- function-audience denial, exact relative targeting, nested identity/depth, and
  success-only tool durability;
- strict package decoding, unsupported runtimes, installation policy, and package
  identity/version behavior;
- Inventory configuration, secrets, revision independence, deployment replay, and
  source deletion;
- Inventory folder migration and hierarchy validation, world-bound fork isolation,
  opaque folder bindings, symlink non-traversal, read-only/encoding failures, lazy
  projection reconciliation, and no-I/O replay;
- exact-object listeners, authenticated report lineage, retention, and replay;
- explicit copy deletion and Inventory-backed manual and purchase restocking;
- user-level agent creation, explicit world assignment, concrete registration, and
  catalog/world synchronization;
- per-agent Wallet identity at backpack `(4,0)`, finite/unlimited funds, exact full
  payer/recipient wallet IDs, Ed25519 authority, signed chain order, treasury
  invariant, custody commitments, operation-envelope idempotency, replay, and
  verify-only failure-closed behavior;
- four-slot holding selection, nonmaterial occupancy, recursive
  `ObjectLocationIndex` ownership, duplicate/orphan/cycle/depth rejection, durable
  bearer broadcasts, wallet lifecycle/deletion constraints, and safe projections;
- native generic human management for Wallet, Messenger, and Objective Board,
  separation from agent-owned Wallet transfer and trusted Merchant purchase,
  child Objective work without a payment gate, package finance exclusion,
  message-based funding, bare-world behavior, exact
  template application and repair, and crash recovery;
- catalog completeness, one-shot/form parser equivalence, Unicode cell layout,
  control-sequence escaping, safe history exclusion, pseudoterminal restoration,
  finite/streaming output equivalence, FIFO execution, and `&` pause/resume; and
- corrupt configuration, agent catalog, Inventory, package cache, and world
  failure;
- loopback world creation and exact existing-agent entry with exact Host, Origin,
  session, content-length, content-type, query, route-specific body bounds,
  duplicate-key rejection, generic errors, transaction recovery, treasury stability,
  conflict handling, and no-automatic-retry behavior;
- World command-console allowlist enforcement, exact selected-world binding, strict
  authenticated same-origin command endpoints, duplicate-key and body/source bounds,
  eight-suggestion and 65,536-byte output limits, one-in-flight `409` behavior,
  FIFO/no-retry scheduling, inert memory-only transcript handling, and successful
  move-triggered projection reload; and
- capability-execution denial and Help-reference coverage; required exact-world field
  projection; global-option and cross-world rejection; built-in-or-HTTPS-only
  package acquisition; typed domain-projection redaction; one aggregate output
  budget; inert command previews; bounded plan and stream counts;
  persistent-state-bound confirmation; write-only bounded secret submission; private
  reveal; accepted and failed download transport; recursive duplicate-key and JSON
  depth/node limits; path redaction; and authoritative domain-projection refresh.

CI runs formatting and shell-script checks on Ubuntu. It runs tests, release builds,
and a `khoros --help` CLI smoke test on macOS, Linux, and Windows. macOS and Linux
additionally exercise the release executable in a real 120-by-30 pseudoterminal;
the Windows job does not run that script.

## Current limits

- Exact-overlap screening cannot detect every semantic or encoded disclosure.
- The system contract is assumed discoverable.
- The CLI is a local single-user product, not a multi-tenant access-control system.
- Native Swift objects are fully trusted host code.
- The signed economy is world-local and provides tamper evidence/replay protection,
  not blockchain consensus, network settlement, external finality, or cross-world
  wallet transfer.
- A future JavaScript adapter requires process isolation, CPU/memory/time quotas,
  filesystem and network policy, SSRF controls, audited capability handles, and
  adversarial testing.
- MikroKhoros Web is a local single-user browser interface, not a remote or multi-tenant
  service. Its contextual capability execution does not broaden the authority of the
  corresponding CLI command, capability, lock, transaction, exact-world, or
  confirmation boundary.
- The future Hall requires authenticated peers, message integrity, replay protection,
  per-world authorization, and cross-agent isolation.

## Research basis

- [OWASP LLM01:2025 Prompt Injection](https://genai.owasp.org/llmrisk/llm01-prompt-injection/)
- [OWASP LLM07:2025 System Prompt Leakage](https://genai.owasp.org/llmrisk/llm072025-system-prompt-leakage/)
- [OWASP LLM Prompt Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/LLM_Prompt_Injection_Prevention_Cheat_Sheet.html)
- [OWASP AI Agent Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html)
- [OpenAI: Improving instruction hierarchy in frontier LLMs](https://openai.com/index/instruction-hierarchy-challenge/)
- [OpenAI: Understanding prompt injections](https://openai.com/safety/prompt-injections/)
- [Peng et al.: RepeatLeakage](https://doi.org/10.1609/aaai.v39i25.34832)

These publications inform defense in depth. Runtime validation and regression tests
are the enforceable product contract.
