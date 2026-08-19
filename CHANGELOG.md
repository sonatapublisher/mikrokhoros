# Changelog

All notable changes to MikroKhoros will be documented here. The project intends to
follow [Semantic Versioning](https://semver.org/) once numbered releases begin.

## Unreleased

### Added

- Dependency-free Swift 6 library and installable `khoros` CLI product for macOS,
  Linux, and Windows.
- Infinite sparse worlds and containers, material occupancy, nested paths, ordered
  multi-agent actions, and typed YAML-compatible results.
- Genesis eye, backpack, coin, scratchpad, Messenger, and calculator objects.
- Persistent world genesis district with locked Athena, Objective Board, Library,
  and Warehouse landmarks visible in the first eye view.
- Collaborative spatial objectives, sourced/paged document objects, shared warehouse
  inventory discovery, Athena world-change notices, and CLI orientation/objective/
  library workflows.
- Portal/key, summoner, shop, merchant, pickup locks, concrete inventory, and
  deterministic restocking behaviors.
- Replaceable AI profiles; direct OpenAI Responses, OpenAI-compatible, Azure OpenAI,
  Anthropic, and Gemini transports; and an OpenDesign-derived adapter catalog.
- Request-driven Messenger delivery, Python-style reads, read receipts, unread
  recovery, and immediate profile-attachment delivery.
- Agent-ID/thread Messenger routing with stable recipient-device identity, matching
  sender/recipient copies, automatic persistent thread creation, and dropped-device
  unread delivery.
- Declarative object bundles, trusted native objects, and explicit Object SDK
  installation capabilities.
- Bounded event-sourced CLI persistence with stable replay identity and entropy.
- Schema-2 persistence for world-genesis identities, objective/document placement,
  and exact Athena notification replay, with deterministic schema-1 migration.
- Per-user validated configuration, global runtime policy, mutable per-agent action
  preferences, `config` management commands, and `doctor` diagnostics.
- Human-only `world inspect` live snapshots covering every agent, object, placement,
  private object state, message/receipt, lock, and profile reference, plus
  `world export` for the complete journal and model-visible histories.
- Structured quoted object arguments with newline, carriage-return, and tab escapes.
- Role-separated prompt construction, deterministic compaction, quoted mutable
  fields, rejected-output non-persistence, and long verbatim instruction/request
  replay rejection.
- Cross-platform CI, community health files, contributor guidance, security policy,
  documentation index, and Apache-2.0 licensing.

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

No numbered release has been published yet.
