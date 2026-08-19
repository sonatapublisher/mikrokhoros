# MikroKhoros v2 runtime design

This is the canonical engineering contract for the implemented CLI-first slice.
Document status is indexed in [`README.md`](README.md); security details and known
limitations are in [`security.md`](security.md).

## 1. Product boundary

MikroKhoros is an environment containing agents. The human controls worlds,
identities, profiles, grants, and placement through the CLI or an embedding host. An
attached LLM is the cognition of one already-existing `Agent`.

The implementation has six layers:

1. `Harness` owns one world, agents, object identity, placement, and serialized world
   mutations.
2. `MikroObject` owns object metadata, private state, public functions, locks,
   durability, containment, and invocation identity.
3. `AgentSession` constructs role-separated model requests, validates action batches,
   executes them, and returns the ordered event envelope.
4. `AIProfile` and `AICompletionClient` attach replaceable provider transport to an
   agent without changing the agent’s identity or world state.
5. `RuntimeConfiguration` and `ConfigurationStore` own validated human defaults and
   advanced runtime policy independently of world state.
6. `WorkspaceRuntime` and `WorkspaceStore` make the first-party CLI state persistent
   through a bounded event journal.

A carried Broadcastable object produces an event that permits one ordinary model
request. A model response can contain a bounded action batch, so one request is enough
for several consecutive world actions. All sessions for the same agent share an
asynchronous ticket gate, so triggered model requests are processed
first-come-first-served rather than racing one another. The one-shot CLI immediately
processes the event when a message is delivered to an active profiled agent or a
profile attachment makes unread carried messages eligible. `agent retry` retries a
preserved provider failure.

### 1.1 Product-owned state

The installed product separates four kinds of state:

| Owner | Default location | Contents |
| --- | --- | --- |
| Human defaults and runtime policy | `~/.mikrokhoros/config.json` | New-agent defaults and advanced request/execution limits |
| Concrete world | `~/.mikrokhoros/workspace.json` | World/genesis IDs, agents, profiles, histories, event-reconstructed objects, and the journal |
| Provider credential | Process environment | Secret value named by an AI profile |
| One invocation | Memory only | Effective parsed arguments and queued request/action state |

`--config` and `--workspace` select alternate files. A missing configuration file
uses built-in defaults without creating a file. Configuration changes are fully
validated, atomically saved, and apply on the next CLI invocation. The future browser
UI should call the same typed configuration and runtime surfaces rather than creating
a second product model.

The human CLI and the agent action language are distinct interfaces. `khoros`
manages configuration, identities, placement, profiles, messaging, grants,
objectives, sourced Library documents, diagnostics, and complete administrative
inspection. The attached LLM receives only its structured request and the small
world-action language in section 6.

Configuration schema version 1 has two groups:

- `agents.maximumActionsPerResponse`: preference copied into each new agent;
- `runtime.maximumActionCharacters`, `maximumActionsPerResponse`,
  `maximumResponseCharacters`, `maximumProviderResponseBytes`,
  `maximumModelFieldCharacters`, `maximumModelInputCharacters`,
  `maximumModelHistoryCharacters`, `maximumModelHistoryMessages`,
  `maximumModelContextCharacters`, `maximumBroadcastEventsPerRequest`, and
  `minimumProtectedVerbatimWords`: advanced runtime-wide request and execution
  policy.

All values are user-configurable positive integers. Validation also requires action
characters not to exceed response characters, field characters not to exceed input
characters, and input characters not to exceed total context characters. An agent's
effective response batch is the smaller of its saved preference and the runtime
ceiling. `config show/get/set/reset/keys/path/validate`, `agent configure`, and
`doctor` expose this model without a source-code edit.

### 1.2 Human administrative visibility

The human can read the whole authoritative product state without adopting an
agent's local perception boundary:

- `world show` renders a compact top-level world and active-agent summary;
- `world inspect` renders all registered agents and objects as a complete live JSON
  snapshot;
- `world inspect <agent-or-object-id>` selects one exact or unambiguous identity;
- `world export` renders the complete persisted workspace document.

The live snapshot includes agent membership, coordinates and structural paths,
hand/backpack/coin relationships, AI profile metadata, known object IDs, pending
notifications, every registered object, placement and recursive containment,
durability, installation identity, pickup-lock owner and allow-list, complete public
function metadata, and type-specific private state. Type-specific state includes
Scratchpad text, Messenger threads/messages/read receipts, coin balance, portal/key
links, merchant prices, objective participation/completion, Library document text,
and declarative-object private state.

The persisted export supplies the complementary event journal and model-visible
histories. Credential values are not part of either view because the workspace
stores only credential environment-variable names. Administrative snapshots are
returned directly to the human CLI and never enter model input, model history, or an
object broadcast.

## 2. Authority and trust

The human user is the ultimate authority. Inside the world, system objects are the
highest non-human authority and agents are the lowest:

```text
agent < system < user/human
```

The LLM is never an authority source. It proposes actions. Swift code independently
mediates identity, membership, current possession, containment, occupancy, pickup
locks, purchasing, installation capabilities, and provider request construction.

Provider message roles are part of this security boundary:

- `AgentModelRequest.system` is the stable privileged runtime contract.
- `AgentModelRequest.input` is a mutable YAML-compatible envelope containing
  untrusted broadcasts and current state.
- These fields must not be concatenated.
- Model-visible compaction checkpoints are ordinary user-role data that name the
  current request as the state source. The complete system contract is rebuilt in
  the system role for every request.

The system prompt is not treated as a secret. It contains no credential, capability
handle, private object state, hidden permission fact, or host secret whose disclosure
would grant authority.

## 3. World and containment

### 3.1 Infinite sparse spaces

`world.object` is the root `MikroObject` and has a `Space`. Every container is also a
normal object with a `Space`; there is no parallel container class hierarchy.

A `Space` is an unbounded sparse map:

```text
Coordinate(Int x, Int y) -> zero or one MikroObject
```

Negative and arbitrarily distant coordinates are valid. Missing keys are empty.
There is no finite-bounds API in v2. Because any finite set of occupied cells has
infinitely many empty alternatives, nearest-placement search always has a
solution unless integer arithmetic itself becomes impossible.

Coordinates are local to their containing object. Normal entry starts at local
`(0,0)`. Normal exit resolves the container object’s current parent position. Reentry
does not remember a previous local coordinate. Portal travel is an explicit object
function exception that targets a paired portal instance’s exact current location.

Containment cycles and duplicate object identities are invalid.

### 3.2 Structural paths

Paths carry both location and object identity:

```text
(0,0)@world/(0,1)["Workshop"#w]/(3,-2)["Chest"#c]
```

The coordinate before each name is where that container object resides in its parent
space. The leading coordinate is the agent’s current local coordinate. A private
attached backpack uses a distinct root such as:

```text
(0,0)@backpack["backpack"#b]
```

Names are quoted data; instance IDs are authoritative.

## 4. Agents, material occupancy, and action ordering

Agent creation, world membership, and AI profile attachment are independent:

- `createAgent` creates a concrete persistent identity, attached backpack, coin
  allowance, and genesis-object identities, but does not place it in the world.
- `addAgent` places it at a requested coordinate. Exact placement failure leaves the
  agent outside the world. Optional auto-adapt chooses the nearest available
  coordinate deterministically.
- First world entry places a fresh genesis `eye.object` in hand. Returning to a world
  never creates another eye.
- A profile may be attached, replaced, or removed without changing the agent ID,
  world membership, inventory, balance, messages, known IDs, or object state.

An agent with an empty hand is non-material. Empty-handed agents may share a cell
with one another, pass through one another, and stand on a placed object. An agent
holding an object becomes a loaded material unit: the object follows the agent and
the pair reserves exactly one cell. Loaded agents cannot overlap placed objects or
other loaded agents.

This makes the state representation unambiguous:

- hand empty: `held: none`; `standing_on` may name the placed object at the cell;
- hand occupied: `held` names the object; `standing_on: none`.

All model actions enter `Harness.performQueuedAction`, which uses one serialized,
monotonically numbered queue. This provides first-come-first-served semantics. If two
agents attempt to pick up the same object, the first successful removal wins and the
second observes an empty cell.

## 5. Perception

Perception is an object capability. Automatic self-state contains only:

- agent ID and name;
- full structural path;
- held object surface or `none`;
- standing object surface or `none`;
- coin balance.

An `eye.object` exposes `look`. It must be held, and it returns the fixed 5×5 area
centered on the agent (`x -2...2`, `y -2...2`). Empty cells stay omitted. The eye is
a normal object: it can have durability, be stored, dropped, locked, sold, summoned,
or replaced.

Object surface metadata is deliberately small:

```yaml
id: "instance-id"
type: "eye.object"
name: "Eye"
summary: "A handheld object for seeing the nearby 5-by-5 world."
condition: usable
durability: unlimited
container: false
origin: genesis
```

`inspect` reveals deeper details: public metadata, current/full durability, origin,
invocation access, container capability, pickup lock, installation ID, and exact
public function signatures. Successful inspection adds the exact instance ID to that
agent’s known set for identity-sensitive objects such as summoners.

## 6. Actions and result protocol

The complete built-in shell grammar is:

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

`object` normally invokes the held object. An anchored object may explicitly declare
surface invocation, allowing an empty-handed agent standing on it to call its public
function; the merchant is the built-in example.

A response is split into nonempty lines and bounded by the smaller of the agent's
saved `maximumActionsPerResponse` preference and the runtime-wide configured ceiling.
New agents receive the configured agent default, initially 8:

1. Lines within the limit execute in order.
2. The first error stops later accepted lines.
3. Lines beyond the limit are not run and produce a warning, not an error.
4. Successful commands are echoed as bounded quoted data.
5. The failed/rejected raw command is omitted.
6. Broadcasts produced between actions are inserted at that exact point in the same
   ordered `events` array.

The initial runtime ceiling is 256 actions per response. Both the new-agent default
and the runtime ceiling are editable through the installed CLI; existing agents can
also be updated independently.

Every error is represented as a stable `RuntimeIssue`:

```yaml
error:
  code: "pickup.hand_occupied"
  message: "cannot pick up; the hand already holds an object"
  details:
    held: "object-id"
  try:
    - "run `drop`, then run `pickup`"
  note: "suggested actions are best effort and may not succeed"
```

Hints are generic hard-coded recovery suggestions. They do not speculate about a
merchant, user intent, or hidden world state and never guarantee success.

## 7. Object model and design philosophy

Objects are the product’s capability boundary, not decorative inventory. An object
should have a concrete identity, exist somewhere, expose a discoverable surface, and
make its powers available through narrow functions.

### 7.1 Philosophy

1. **Concrete before abstract.** A tool, phone, merchant, portal, user computer, or
   sensor is an object instance the agent can locate, carry, enter, inspect, or use.
2. **Possession is meaningful.** Holding/backpacking can confer notification or
   invocation eligibility; dropping the object removes that relationship.
3. **Capability is explicit.** World-system authority, network access, and user
   machine access are named grants, never inferred from prose or object type.
4. **Private by default.** Mutable object state and private child objects stay hidden
   unless surfaced through metadata or a public function.
5. **Fresh means fresh.** Shop restock and other copying operations call `freshCopy`,
   producing a new ID and full initial durability rather than sharing worn state.
6. **Failure is transactional where value moves.** Purchase validates identity,
   location, availability, funds, lock transition, and replacement placement; a
   failure restores the prior lock and balance.
7. **No magic duplicate tool.** If perception, messaging, calculation, teleport,
   summoning, commerce, or external-machine control belongs to an object, the LLM is
   not quietly given an equivalent hidden primitive.
8. **Portable core, sandboxed extensions.** Safe declarative behavior ships now.
   Executable portable languages belong behind a real capability sandbox, quotas,
   network policy, and revocation—not a string evaluator inside the world process.

### 7.2 Object fields

Every `MikroObject` has:

- immutable type, name, summary, and unique instance ID;
- origin: `native`, `genesis`, or `package`;
- invocation access: `held` or `surface`;
- optional installation ID;
- public JSON metadata and private class/package state;
- optional current and maximum durability;
- optional container capability;
- optional structured pickup lock;
- a closed set of public functions with signatures, summaries, and durability cost.

Function invocation receives an `ObjectInvocationIdentity` created by the runtime,
not by model/object text. It binds invocation, object, installation, agent, and world
IDs.

### 7.3 Pickup locks

`ObjectLock` supports:

- `deny_all`: no agent may pick up;
- `allow_only`: only named agent IDs may pick up;
- authority and owner checks for replacement/removal;
- optional `clearsOnPickup` for one-time buyer claims.

A generic locked-pickup error says the lock does not permit the agent and suggests
satisfying/removing it. It does not mention a merchant unless the merchant function’s
own successful result is describing a purchase.

## 8. Genesis and built-in objects

Genesis is developer-created provenance. Genesis instances obey ordinary placement,
containment, inspection, invocation, durability, and pickup-lock rules; any trusted
capability remains explicit.

### 8.1 Agent genesis objects

An agent owns a detached infinite `backpack.object` and attached `coin.object`.
Backpack local `(0,0)` stays empty so a loaded agent can open it. Genesis contents:

| Coordinate | Type | Purpose |
| --- | --- | --- |
| `(1,0)` | `scratchpad.object` | bounded persistent private text |
| `(2,0)` | `messager.object` | persistent chat, broadcasts, receipts |
| `(3,0)` | `calculator.object` | arithmetic parser without code execution |

### 8.2 World genesis district

Every first-party world contains four stable landmarks within the default entry
eye's 5×5 view:

| World coordinate | Type | Contract |
| --- | --- | --- |
| `(0,-2)` | `athena.object` | system-locked surface steward with deterministic `brief` |
| `(1,-2)` | `objective-board.object` | system-locked shared objective container |
| `(-2,2)` | `library.object` | system-locked sourced-document container |
| `(2,2)` | `warehouse.object` | system-locked shared object storage |

Athena is a deterministic surface-callable genesis steward compiled into
`athena.object`. A human-authored world membership, objective, or library mutation
writes a message from Athena into the `#athena` thread of each active agent's stable
genesis messenger. A carried messenger emits the notification under the standard
Broadcastable possession rules, and the per-agent request gate processes it with
ordinary priority.

The Objective Board contains a locked surface-callable index at local `(0,0)`.
Each posted `objective.object` is a concrete system-locked item at a deterministic
nearest available coordinate. It stores title, body, creation time, participant
agent IDs, state (`open`, `in_progress`, or `completed`), and the completing agent.
Its surface functions are:

- `read`: return bounded objective data;
- `register`: add the invoking agent as a participant, idempotently;
- `complete`: complete only when the invoking agent is registered.

Several agents may register the same unfinished objective. Completion is a normal
queued world mutation and persists through canonical action replay.

The Library contains a locked surface-callable catalog at local `(0,0)`. Human CLI
fetches accept HTTPS or plaintext loopback HTTP, refuse URL credentials/fragments,
enforce `maximumProviderResponseBytes`, and require non-empty UTF-8 text. The final
source URL, fetch time, title, and content become a locked `document.object` at a
deterministic nearest available coordinate. `read` and `read_range <start> <length>`
return configurable bounded pages with `trust: external_untrusted`. The pages enter
the model request as quoted mutable data. Runtime identity and capability checks
remain the action authority boundary.

The Warehouse starts with a locked directory at local `(1,0)` and otherwise uses
ordinary infinite container mechanics. Its `list` function reports concrete direct
children and their local coordinates. Agents share tools by moving the actual object
instances through their backpacks.

### 8.3 Other built-ins

Other native objects:

- `portal.object` + `key.object`: the key identifies one portal instance, stores
  itself, then teleports the now-empty-handed agent to the portal’s exact location.
- `summoner.object`: requires a previously inspected exact ID, stores itself, and
  moves that existing unlocked instance to the agent. It never copies.
- `apple.object`: a small durable function example.
- `merchant.object`: anchored surface-callable shop controller.

## 9. Messenger and broadcast protocol

`messager.object` is analogous to a smartphone messaging application. Its threads
and messages are private state/children not placed visibly on the world surface.

### 9.1 Data and functions

Thread `#1` exists by default. The runtime adds persistent thread `#athena` to a
messenger on its first Athena notice. New chats are persistent threads. A message
contains:

- exact message and thread IDs;
- human/agent sender name and optional sender agent ID;
- timestamp;
- body;
- optional priority label: `!`, `!!`, or `!!!`;
- read state.

No marker means ordinary priority. Priority is descriptive only and never compels a
response.

`read` accepts Python semantics:

- `-1`: latest message;
- `0`: first message;
- `-10:`: last ten when present;
- `2:6`: half-open range.

It returns YAML message records including sender, timestamp, body, priority, and seen
state. Reading an unread message creates a read receipt; receipts are not
configuration. `send` uses:

```text
object (send (<recipient-agent-id>) (<thread>) (<body>) [<!|!!|!!!>])
```

The recipient agent ID resolves to that agent's stable genesis Messenger object.
The same message ID and timestamp are written to a read sender copy and an unread
recipient copy. A named thread materializes in both Messenger objects on first use,
with local conversation titles. Self-addressed delivery records one read copy.

### 9.2 Broadcast eligibility and request trigger

Broadcastable is an object capability/interface. The built-in messenger implements
it. A notification may reach an agent only when the exact source object is:

- in the agent’s hand; or
- anywhere under the agent’s backpack containment tree.

The runtime resolves this from containment. A claimed agent ID in message text has no
effect.

Message routing and notification eligibility are separate. Routing uses the
recipient agent ID and stable genesis Messenger identity. Notification eligibility
uses the exact Messenger object's current hand/backpack carrier. A message can remain
unread on a dropped device and become eligible when the device is carried again.

On message arrival, one latest unread preview is queued only when a profile is
attached. Messages arriving while profile-less stay unread. The latest unread is
also queued when:

- a previously uncarried source becomes carried; or
- a profile is attached/replaced while an eligible source has unread messages.
- an already-profiled agent with unread carried sources enters the world.

Notification does not mark read. Continuous hand/backpack transfer is deduplicated
by message/event ID. Provider failure reinserts the pending event. The broadcast is a
normal user-role event with title/body preview and optional priority, and immediately
permits the ordinary model request.

## 10. Shops and restocking

A shop is a locked ordinary container. The merchant is an anchored object at local
`(0,0)`. Inventory consists of concrete placed objects with prices keyed by exact
instance IDs.

Purchase flow:

1. Resolve an exact or unambiguous catalog ID.
2. Verify the item still resides directly in that merchant’s shop.
3. Verify the item still has the merchant’s unsold inventory lock.
4. Verify coin allowance.
5. Prepare a fresh replacement when auto-restock is enabled.
6. Replace the inventory lock with a system-authority buyer-only pickup claim.
7. Deduct coin.
8. Place the replacement at the deterministic nearest available cell around the
   merchant and add its price.
9. Roll back the lock, balance, and partial replacement if any step fails.

The sold item does not teleport into inventory. It remains at its cell until the
buyer picks it up. First successful buyer pickup clears the claim. If not picked up,
it stays reserved there.

## 11. AI profiles and request lifecycle

`AIProfile` stores provider-neutral configuration:

- stable profile ID and display name;
- adapter ID and transport;
- model;
- optional endpoint;
- credential environment-variable name;
- optional temperature and maximum output tokens.
- optional reasoning effort (`none`, `low`, `medium`, `high`, `xhigh`, or `max`).

Credential values never enter the profile, world state, model input, or workspace.
The adapter definition must exist and its transport must match the profile. Coding
CLI adapters connect through a configured role-separated HTTP bridge whose exposed
action surface is the MikroKhoros object protocol.

OpenAI uses the Responses API recommended for GPT-5.6 reasoning/multi-turn work.
Direct transports preserve system/input roles for OpenAI Responses,
OpenAI-compatible Chat Completions, Azure OpenAI,
Anthropic, and Gemini request formats. The bridge format likewise sends distinct
`system`, `input`, `history`, and profile/model fields.

For each pending request:

1. Drain pending carried-object events.
2. Revalidate exact source ID, type, and current possession.
3. Build fresh privileged instructions and quoted mutable input.
4. Compact only model-visible history if over budget.
5. Call the configured provider once.
6. On provider error, restore pending events and preserve unread messages.
7. Execute the returned bounded action batch.
8. Retain successful canonical commands and structured results in model-visible
   history; never retain rejected raw output.
9. Compact again if necessary.

OpenAI’s GPT-5.6 guidance informed the prompt shape: lean instructions, no repeated
tool descriptions, explicit autonomy/authority boundaries, current relevant state,
and evaluation-driven reasoning effort. GPT-5.6 Sol is represented as an ordinary
profile/model option, not hard-coded into world behavior.

## 12. Adapter catalog

The catalog is a data registry modeled after OpenDesign’s adapter-definition
architecture. Provider/local-server entries define direct transport defaults.
Coding-agent entries define names, executable probes, and the requirement for a
role-separated bridge. PATH detection does not execute a discovered binary.

Current coding-agent IDs:

```text
amr, claude, codex, devin, opencode, byok-opencode, hermes, trae-cli,
grok-build, kimi, cursor-agent, qwen, qoder, copilot, amp, pi, kiro,
kilo, vibe, deepseek, deepseek-harness, aider, antigravity, reasonix,
codebuddy, mimo, atomcode
```

Registry initialization asserts unique IDs, and tests pin the expected set.

## 13. Object SDK and package safety

### 13.1 Declarative packages

`BundleRegistry` accepts at most 1 MB of UTF-8 JSON. Unknown fields and action kinds
fail closed. Top-level fields:

| Field | Meaning |
| --- | --- |
| `type` | required one-token type ending in `.object` |
| `name`, `description` | optional bounded metadata |
| `public` | model-inspectable JSON |
| `state` | private initial JSON |
| `durability` | optional non-negative budget |
| `container` | optional Boolean; `true` creates an infinite space |
| `functions` | closed declarative function map |

Supported function actions are `return`, `get`, `set`, `append`, `increment`, and
`toggle`. There are no imports, callbacks, shell operations, filesystem access, or
network actions. A durability-consuming function requires a durability budget.
Installed type definitions cannot update in place; removal affects future creation,
not already-created instances.

### 13.2 Installation capabilities

`ObjectPackageManifest` names a declarative, native Swift, or future JavaScript
runtime and requests a set of capabilities:

```text
private-children, broadcast, world-read, world-write, world-system,
network, user-machine
```

Installation is world-scoped. Grants must be a subset of requests and can be
approved/revoked individually. `require` fails with
`object.capability_denied` when absent.

The registry is authorization metadata, not an executable sandbox. Declarative
packages run through the closed interpreter. Native Swift objects are trusted host
code. A JavaScript manifest can be registered for future compatibility but is not
executed by this package. Shipping execution requires isolation, CPU/memory/time
quotas, network/SSRF policy, user-machine mediation, audit records, and revocation at
every external sink.

## 14. Persistence

The first-party CLI workspace is a bounded event-sourced document with schema
version, stable world ID, stable world-genesis IDs, agent records, ordered events,
and compacted model-visible history. Schema 1 workspaces derive the new genesis IDs
deterministically from their existing world ID and encode as schema 2 on the next
save.

Agent records preserve:

- durable agent identity and name;
- initial coin allowance and action limit;
- stable backpack, coin, eye, scratchpad, messenger, and calculator IDs.

Events preserve membership transitions, per-agent preference changes, profile
attachment/removal, successful canonical action effects, notification consumption,
external messenger delivery, coin grants, objective/document placement, and exact
Athena notice delivery IDs/timestamps. Per-action entropy tapes preserve
runtime-generated IDs and dates, so model-sent message identities and restocked
object identities do not drift during
replay. Replaying those events rebuilds the same CLI-owned world state and fails
closed if a previously successful command no longer succeeds.
Rejected raw model text is not journaled. External message IDs and timestamps are
stored explicitly so unread/reacquisition/profile-attachment deduplication survives a
restart.

`world inspect` reconstructs and renders the live domain state after replay.
`world export` renders the underlying persisted document. Together they give the
human a complete read path across current object/agent state and the events/history
that produced it without widening any agent's perception.

Journal replay validates stored canonical actions against the workspace storage
boundary and applies them in their original event order. A later runtime limit change
governs new model requests/actions; it does not reinterpret an earlier successful
batch or prevent the world from loading. Restored model history receives the same
storage-safe structural validation, then is compacted to the active configuration
before the next provider call.

Storage limits and policies:

- workspace file: 64 MB;
- agents: 10,000;
- events: 1,000,000;
- restored model-visible history is storage-validated, then uses the active runtime
  character/message settings before provider use;
- atomic JSON replacement;
- POSIX permission `0600` where available;
- unknown schema or corrupt replay fails closed with a bounded diagnostic.

The event store owns the first-party CLI’s genesis world. Embedding hosts that add
arbitrary custom native object graphs should provide their own object snapshot/event
adapter rather than assuming Swift closures can be serialized.

## 15. Prompt injection and leakage controls

Threat model: object metadata, function results, messenger bodies, sender names,
internet results, model history, and model output may all be adversarial.

Controls:

1. Stable system and mutable input use separate provider fields/roles.
2. All mutable YAML fields use JSON-string encoding, valid as a YAML 1.2 quoted
   scalar. Embedded newline, colon, quote, or document marker cannot create an
   envelope field.
3. Mutable request input, broadcast count, and total provider-visible context use
   independent validated runtime settings. If request construction fails, drained
   events are restored before the error is returned.
4. Response bytes, response characters, action count, and action characters are
   bounded before execution. Control characters and invisible Unicode formatting
   controls fail closed; compatibility-normalized copies cannot bypass screening.
5. Failed/rejected commands use stable codes and do not echo attacker-supplied text.
6. Only successful validated commands appear in history or the persistence journal.
7. Broadcast source identity and possession are revalidated at request construction.
8. Profiles refer to credential environment names, never values.
9. Runtime authorization does not depend on the LLM following the prompt.
10. Persisted history is bounded and structurally validated before restore or a
    provider call. Compaction emits a user-role `context_scope` marker naming
    `current_request` as the state source; the complete system contract is supplied
    separately on every request.
11. External sinks remain object functions subject to deterministic capability and
    identity checks.
12. Library content is labeled external/untrusted, JSON-quoted in result envelopes,
    and page-bounded before entering model-visible history. The human administration
    CLI owns the fetch operation.
13. Before model output executes, the session rejects long verbatim word windows
    copied from the privileged system contract, current request, or earlier
    provider-visible user context. The rejection uses a stable code and never
    reproduces matched text.
14. Decoded profiles are revalidated. Remote endpoints require HTTPS, plaintext is
    loopback-only and credential-free, Gemini credentials use a header rather than a
    URL, OpenAI Responses storage is disabled, and provider response JSON is bounded.

Exact-overlap screening, detection regexes, or model classifiers can support defense
in depth and telemetry, but none is an authorization boundary or a guarantee against
paraphrased leakage. Model-visible text therefore contains no secret whose disclosure
grants authority. See [`security.md`](security.md) for the full threat model.

## 16. Platform discipline

The SwiftPM executable product and resulting terminal command are named `khoros`.
Its default files are `~/.mikrokhoros/config.json` and
`~/.mikrokhoros/workspace.json`; callers may select alternatives with the global
`--config` and `--workspace` options.

The library has no AppKit, UIKit, Objective-C runtime, Darwin-only filesystem API,
subprocess-based agent loop, or third-party dependency. `FoundationNetworking` is
conditional. CLI exit imports are selected for Windows, Darwin, or Glibc. SwiftPM’s
macOS platform declaration does not exclude Linux/Windows builds.

Release validation consists of debug tests, release build, CLI smoke tests against an
isolated workspace, JSON validation, and static scans for stale Python artifacts,
secrets, unsafe process execution, and accidental finite-space behavior. GitHub
Actions repeats formatting, tests, and release builds on macOS, Linux, and Windows.

## 17. Explicit future boundaries

The following belong after the CLI/product contract stabilizes:

- localhost browser UI over the same runtime/workspace API;
- a real sandboxed portable executable Object SDK;
- richer messenger routing between users, agents, and external chat systems;
- inspectable goal, planning, writing, pen, and editing object families;
- audit UI and approval flows for network, purchase, user-machine, and system-level
  object actions;
- the multi-agent network/Hall and any blockchain-backed identity/economy layer.

These extensions reuse concrete agent/object identities, possession-based
broadcasts, capability grants, infinite container coordinates, and ordered action
events.
