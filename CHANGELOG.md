# Changelog

All notable changes to MikroKhoros will be documented here. The project intends to
follow [Semantic Versioning](https://semver.org/) once numbered releases begin.

## Unreleased

### Added

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
- Defined the canonical cross-platform `khoros web` shell, its single app-view
  dropdown, view-specific world scope, generic structured object interfaces, compact
  visual system, exhaustive command placement, and selected Templates catalog state.

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

No numbered release has been published yet.
