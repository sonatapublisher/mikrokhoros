# Changelog

All notable changes to MikroKhoros will be documented here. The project intends to
follow [Semantic Versioning](https://semver.org/) once numbered releases begin.

## Unreleased

### Changed

- `khoros web` now serves bounded canonical root-document route hints for
  active-session same-origin deep links and reloads, keeps static assets and API
  query handling fail-closed, isolates loopback session-cookie names by bound
  port, gives every primary view one independent scroll workspace, and adds a
  keyboard-accessible desktop sidebar resize boundary with bounded persisted
  presentation width.
- MikroKhoros Web now binds stable `127.0.0.1:47567` by default, accepts one strict
  custom port through `--port`, and selects an operating-system port only through
  `--available-port`. Exact-port collisions never fall back silently; bounded
  loopback diagnostics distinguish a reachable MikroKhoros Web listener from another
  local service without treating the diagnostic marker as authority.
- Standardized the `khoros web` standalone control contract: actions, dialogs,
  icon controls, domain search, and closed custom selectors are complete 32px
  capsules; custom text-only filter, autocomplete, and choice rows keep their full
  labels; Agent Manager filters now open start-aligned, content-bounded opaque menus.
- Aligned every non-World web header, transient state, and content surface
  to one responsive 1080px workspace frame with an 18px...36px inline gutter;
  compact pages use the same edge contract and the shared 16px/8px/6px detail
  rhythm. Every non-circular web radius, including pill-radius capsules and clipped
  transparent-glass layers, now uses the shared `superellipse(1.78)` smooth-corner
  construction; only the three semantic circle/dot selectors retain round geometry.

### Added

- MikroKhoros Web, served by the existing native `khoros` executable. Its
  custom menu provides World, Agent Manager, Inventory, Packages, and Templates,
  with fixed Settings and searchable Help. Agent Manager, Inventory, Packages,
  Templates, and Settings are domain-native typed views.
  The shared capability catalog drives contextual controls, typed fields, custom
  choices, dynamic completion, explicit confirmation, write-only credentials,
  bounded agent actions, private views, downloads, and cancellable report following
  through the in-process command engine. World keeps exact world/container routes,
  focus/follow, map controls, reports, local pins, generic object inspection,
  bare-world creation, existing-agent entry, and its bounded command dock.
- World projections now cap picker entries at 128, other-agent rows at 128,
  selected-space objects at 256, and the newest retained reports at one aggregate
  256 KiB encoded budget. Agent-selection options have a hard maximum of 256.
- Bounded authenticated typed projections for Agent Manager, Inventory, Packages,
  Templates, and Settings at `/api/v1/agents`, `/api/v1/inventory`,
  `/api/v1/packages`, `/api/v1/templates`, and `/api/v1/settings`. The views reload
  authoritative domain data after relevant
  actions; projection responses omit credential data, private histories, raw
  persistence documents, executable paths, capability closures, and administrative
  authority material. Settings exposes only typed non-secret runtime values.
- Exact object interfaces now project complete bounded field, action, view, and
  report metadata for their declared scope, and host controls execute that metadata
  through the capability gateway. Placed, held, nested, and agent-attached objects
  share the exact interface route with truthful optional coordinates, structural
  paths, and move availability; raw action implementations and unsafe defaults remain
  outside the browser contract. Inventory presents readiness gaps, requested and
  granted capabilities, exact fork/template provenance, and world binding without
  exposing source configuration or credential values. Agent Retry is derived only
  from a content-free pending-work count. Package detail includes runtime, requested
  capabilities, installation/retention metadata, content identity, and source usage;
  its install field is labelled **Trusted package source**, accepts only exact
  built-ins or HTTPS, and reapplies that browser policy to every redirect. Template
  composition now shows every root and owned object's package, requested parent
  space, and coordinate with a neutral Phosphor Cube rather than a synthesized
  pre-instantiation identity, with Create World in overflow and exact-world
  status/application forms.
- A presentation-neutral web capability protocol and CLIKit gateway with
  exhaustive command placement, trusted layout/world globals, bounded inert output,
  single-flight execution, session- and persistent-state-bound single-use plans,
  bounded plan/stream state, write-only secret limits, inert display previews,
  and filesystem-free completion. The SwiftNIO transport adds authenticated catalog,
  completion, execute, prepare/commit, secret, agent-controller, download, and
  backpressured session-expiring report routes with recursive duplicate-key rejection,
  JSON depth/node limits, accepted-only attachment delivery, and generic failures.
  Web capability requests use their documented 64 KiB transport bound, and a private
  export is attached only when its complete output fits the finite browser budget.
  Raw Inventory configuration and administrative object-snapshot commands are
  disabled browser reference entries. A selected contract with any declared path
  field or path-typed action input keeps its metadata visible while all actions and
  views are CLI-only; configuration-backed views are also CLI-only. Crafted set,
  unset, action, and view requests are rejected at the gateway, and browser-rendered
  Inventory command results expose configuration-key presence rather than values.
- World-page behavior is now documented and implemented: independent deterministic
  shape/color identity using eight original MikroKhoros silhouettes—including Shield,
  Seal, Star, and Heart—with an evenly proportioned Shield, an optically compact
  rounded equilateral Triangle,
  a straight-sided five-point Star with localized rounded outer tips, centered
  geometry, and eight
  evenly repeated broad Seal lobes. Each silhouette is optically sized as part of the
  complete 24px family using apparent keyline, density, negative space, recognition,
  and bright-color behavior. True vector area remains a measured guardrail, and every
  filled-area centroid lands at the exact 256px view-box center. The page also uses
  12 palette colors,
  transparent Project Genie-style capsule controls, equal
  rounded-square world targets, a faded blur transition from sidebar to world, scoped
  live follow with ~1.8s scoped refresh and explicit manual exit, click/double-click
  arbitration
  (200ms) with 6px drag capture, exact-world bounded reports with `latest-seen` and
  client-computed `N`, persistent exact-world My-view camera restoration, and
  icon/interaction updates for held-object silhouettes and one-target occupancy.
- The World page now keeps agent ordering stable across My view restoration, renders
  My view on one line, opens a custom cell menu for occupied and empty positions,
  scales contiguous cells and all cell visuals together with zoom, uses Phosphor
  Bold interface icons, limits Project Genie glass to designated standalone
  controls, gives floating surfaces light-only rims, and uses the plain Phosphor
  Magnifying Glass for search while reserving Plus and Minus variants for zoom. The
  command submit action also uses the Phosphor Arrow Elbow Down Left rather than a
  text glyph. Clipped 32px glass controls use a 20px label line box so rounded
  Google Sans Flex descenders remain complete without changing their one-line
  ellipsis or compact control geometry. Repeating domain rows retain the local 12px
  surface radius, while domain search uses the standalone-control capsule.
- The loopback host atomically owns one listener lifecycle per server instance,
  rejects a concurrent start, performs token-matched resource shutdown, joins
  overlapping stops through the idle transition, supports immediate restart after
  stop, and suppresses launch callbacks when shutdown wins first.
- An object-bearing World-cell dropdown dismisses on the next empty-cell click and
  consumes that click, while a subsequent activation opens the empty-cell dropdown
  normally and drag capture continues into ordinary panning.
- A floating World command console with a separate monospace input capsule and
  resizable/minimizable Output, Agent, and Object information panel. Hover-selected
  Agent/Object context stays exclusively in the panel; `C` keeps or releases the
  current detail after pointer exit, while `1`, `2`, and `3` switch the three tabs
  outside editable and modal/menu surfaces. Completion and syntax styling
  come from the canonical command catalog, and the in-process console uses
  the shared CLI tokenizer, parser, and executor with an exhaustive deny-by-default
  allowlist: `help`, `world show`, `world template status`, `world object list`,
  `world object view list`, and `world object move`. Typed object interfaces remain
  behind the bounded object projection. Execution is one-in-flight, FIFO,
  nonretrying, exact-world bound, and keeps only a bounded inert transcript in page
  memory; successful object moves reload the authoritative World projection.
- A user-global world catalog under `~/.mikrokhoros/worlds`, persistent current-world
  selection, temporary `--world` overrides, multi-world create/list/use/rename/delete,
  and recoverable world-file transactions without changing runtime identities.
- Bearer Wallet Economy, Property Rights, and Four-Slot Holdings: every registered
  agent now receives a native Wallet at backpack coordinate `(4,0)` and four
  nonmaterial holding positions, with O(1) primary selection via `holding select`.
  Bearer ownership is derived recursively from the world `ObjectLocationIndex`,
  while wallet balances and modes remain in the signed world-local credit record
  chain rather than in the Wallet object itself.
- Root-treasury-authorized finite and unlimited wallets, exact full wallet IDs,
  signed custody records, idempotent operation envelopes, replay and verify-only
  checks, durable bearer-scoped Messenger broadcasts, and native Wallet, Messenger,
  Objective Board, and Merchant object surfaces. Funding requests use ordinary
  Messenger messages; objectives have no payment gate. This is local signed
  accounting, not a network blockchain or external settlement system.
- Swift Crypto `4.3.1` (Apache-2.0) for Ed25519 signing and SHA-256 record-chain
  verification, with attribution recorded in the repository `NOTICE` and dependency
  metadata.
- Classic project badges in the README, plus a note on the Ancient Greek roots of
  the MikroKhoros name.
- Dependency-free Swift 6 library and installable `khoros` CLI product for macOS,
  Linux, and Windows.
- Infinite sparse worlds and containers, material occupancy, nested paths, ordered
  multi-agent actions, and typed YAML-compatible results.
- Genesis eye, backpack, native Wallet, four holding positions, scratchpad,
  Messenger, and calculator objects.
- Bare infinite worlds and the trusted `default-khoros` template, with five
  independent canonical Inventory sources for Athena, Objective Board, Library,
  Warehouse, and Marketplace.
- Collaborative spatial objectives, sourced/paged document objects, shared warehouse
  inventory discovery, Athena world-change notices, and CLI orientation/objective/
  library workflows.
- Portal/key, summoner, shop, merchant, pickup locks, concrete world objects, and
  deterministic Marketplace behavior.
- Replaceable AI profiles; direct OpenAI Responses, OpenAI-compatible, Azure OpenAI,
  Anthropic, and Gemini transports; and an OpenDesign-derived adapter catalog.
- User-global agent identities and AI profiles in a bounded `agents.json` catalog,
  explicit world-ID assignment, concrete world registration, and deterministic
  same-world re-entry.
- Request-driven Messenger delivery, Python-style reads, read receipts, unread
  recovery, and immediate profile-attachment delivery.
- Agent-ID/thread Messenger routing with stable recipient-device identity, matching
  sender/recipient copies, automatic persistent thread creation, and dropped-device
  unread delivery.
- A unified versioned declarative object-package format with package-selected
  Inventory creation, content-addressed retention, strict decoding, runtime
  availability checks, and streamed HTTPS-or-loopback installation.
- User-global Inventory source objects with typed configuration, immutable
  credential-version references, capability grants, management actions, management
  views, readiness diagnostics, revisions, and logical deletion.
- Hierarchical Inventory folders, source movement without revision changes, and
  independent source forks permanently bound to one exact world with recorded
  parent provenance and credential isolation.
- Independent world deployments with captured package content, configuration,
  credentials, grants, state, durability, locks, runtime-issued identities, and
  replayable Inventory lineage.
- Human report listeners scoped to one exact world object, structured retained
  reports, world-aware management views, explicit copy-deletion scopes, and
  Inventory-backed manual and purchase-triggered shop restocking.
- Constrained Object SDK contexts and capability-mediated world, network, and
  opaque user-folder services for package runtime adapters; trusted host objects
  retain a separate internal runtime context.
- Exact host-registered runtime adapters, scoped Inventory/world management
  contracts, function audiences, nested invocation identity, exact relative object
  calls, bounded nested-invocation receipts, and success-only source/target durability.
- Built-in user-workspace, pencil, printer, and paper packages; live anchored host
  folder/file projection; opaque folder-binding access; lazy reconciliation; and
  replay-safe external-effect receipts.
- Bounded event-sourced CLI persistence with stable replay identity and entropy.
- Schema-7 persistence for named bare worlds, template applications and repairs,
  four-slot holdings, native Wallets, signed credit records, operation envelopes,
  exact facility-targeted events, adapter-backed deployment and instance state,
  movement, external effects, deletion, listeners, reports, and restock rules;
  AgentStore schema 3 and administrative snapshots schema 2.
- Zero-prompt, idempotent `khoros init`; explicit bare or templated world creation;
  aggregate template Inventory confirmation; dry-run planning; and exact or
  adapted placement. The schema-7/AgentStore-3/admin-snapshot-2 persistence line
  is a clean break: Coin/single-hand and older files are rejected with no
  automatic or explicit migration.
- Crash-recoverable product transactions across configuration, package/Inventory,
  agent-catalog, and world documents for template setup and world creation.
- Per-user validated configuration, global runtime policy, mutable per-agent action
  preferences, `config` management commands, and `doctor` diagnostics.
- Human-only `world inspect` live snapshots covering every agent, object, placement,
  private object state, message/receipt, lock, and profile reference, plus
  `world export` for the complete journal and model-visible histories.
- A dependency-free inline `khoros` console with catalog-driven guided forms,
  completion and ghost defaults, live FIFO execution, `&` error barriers, foreground
  prompts, cancellation controls, Unicode editing, and macOS/Linux/Windows terminal
  backends.
- Adaptive scrollback-preserving terminal frames, terminal-cell-aware Unicode
  layout, hybrid quoted command lines, reliable idle Ctrl-C exit, bracketed paste,
  resize handling, and exact terminal-state restoration.
- Presentation-neutral command results with human, canonical YAML, JSON, and
  streaming YAML/NDJSON renderers; semantic ANSI color policy; readable action
  turns; trusted next steps; and conventional nonzero failed-action status.
- Scoped human selectors for unique names and unique runtime-ID prefixes, contextual
  root/group/leaf help, typo suggestions, and a catalog-driven human agent shell.
- One authoritative exhaustive command catalog shared by generated help, one-shot
  parsing, guided forms, completion, history policy, and named command execution.
- Catalog-driven Inventory folder/fork and exact world-object management commands,
  including dynamic guided inputs for package-defined management actions.
- Versioned, bounded, atomically replaced, user-private console history containing
  only explicitly entered safe fields, plus configurable input, queue, suggestion,
  entry, and history-byte limits.
- Structured quoted object arguments with newline, carriage-return, and tab escapes.
- Role-separated prompt construction, deterministic compaction, quoted mutable
  fields, rejected-output non-persistence, and long verbatim instruction/request
  replay rejection.
- Cross-platform CI, community health files, contributor guidance, security policy,
  documentation index, Apache-2.0 source headers, repository-owned build/install/
  validation scripts, and an opt-in pre-commit hook.
- Progressive isolated-product tours for initialization, package deployment,
  Inventory/source independence, printer-paper-pencil composition, and live host
  folder projection without copied full runtime IDs.

### Documentation

- Reorganized reader documentation around a product-first README, a durable
  human-operator guide, focused hands-on tours, and the generated CLI reference.
- Defined the canonical cross-platform browser shell, its domain-native World,
  Agent Manager, Inventory, Packages, Templates, and Settings hierarchy,
  exact-object interfaces, compact visual system, and complete implemented command
  placement.
- Documented the five enabled web views, fixed Settings, searchable Help,
  domain-native content, contextual action sheets, action-local exact-world
  selection, confirmation, credential, controller, private-view, download, and
  report-stream behavior.
- Added the World-page contract for deterministic identity symbols,
  interaction thresholds, exact-world report state, follow behavior, and My-view
  camera/restorer memory semantics.
- Documented the inline `All X agents` roster behavior, compact add-agent dialog
  fields, and constrained `/api/v1/worlds` and `/api/v1/world-agents` browser mutation
  contracts.
- Documented the World command console layout, exact immediate-command allowlist,
  selected-world binding, bounded completion/output behavior, nonretrying queue, and
  the separate typed domain-projection plus contextual-execution transport.

### Fixed

- Raised the supported Swift toolchain baseline to 6.1 and aligned macOS, Linux, and
  Windows CI so SwiftPM can load the locked `swift-asn1` dependency.
- World construction and read-only missing-world commands no longer create
  facilities or persist implicit worlds; facility commands resolve exact active
  template components.
- Restored atomic persistence replacement on Linux and Windows, and portable
  report-stream flushing across the supported platforms.
- Restocking and deployment now enforce exact world bindings; projected host writes
  cannot cross read-only, symlink, path, encoding, capability, or configured-size
  boundaries and are never repeated during journal replay.
- Corrected raw terminal line endings and physical-row clearing so completion rows
  remain aligned at narrow and wide terminal sizes; the empty console no longer
  floods the screen with the command catalog.
- Removed working-directory and file-path world selection. The retired `--workspace`
  option now fails before mutation with import and world-selection guidance.

### Security

- Added regression coverage preventing a model from copying long protected system or
  provider-visible user context through an otherwise executable action.
- Added structural and size validation for persisted model history and total context,
  data-only compaction markers, Unicode-obfuscation handling, bounded provider JSON,
  decoded-profile validation, TLS/credential transport rules, and provider privacy
  defaults.
- Moved every published model/request/action numeric boundary into human-owned
  configuration while preserving cross-field validation and runtime enforcement.
- Added `external_untrusted` Library labeling, bounded paging,
  HTTPS-or-loopback transport, and a human-owned fetch operation.
- Added write-only credential storage, redacted administrative output, exact
  capability snapshots for deployed copies, authenticated report lineage, package
  redirect validation, atomic Inventory/world storage, and serialized CLI
  mutations.
- Moved package, agent-catalog, Inventory, world, report-size, and
  report-retention limits into installed-product configuration and exposed them
  through `khoros config`.
- Kept secret input, message and objective bodies, raw agent actions,
  credential-bearing URLs, management assignments, output, and queue state outside
  console history and completion data.
- Added strict security claims for World command requests: exact session and same-origin
  checks, strict `{worldID, source}` JSON, 8 KiB request and 4,096-character source
  bounds, eight-suggestion and 65,536-byte output bounds, one in-flight execution,
  no subprocess, inert memory-only transcript, and move-triggered projection reload.

No numbered release has been published yet.
