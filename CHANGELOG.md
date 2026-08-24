# Changelog

The project is in pre-release development. These notes describe the public
runtime and the capabilities available in the current source tree.

## Pre-release

### Runtime

- Swift 6 runtime and `khoros` CLI for macOS, Linux, and Windows.
- Persistent sparse worlds with nested containers, material occupancy, structural
  paths, world-local state, and replayable trajectories.
- Explicit observation, bounded actions, real preconditions, validated state
  transitions, and recoverable consequences for AI agents.
- User-global agents with explicit world assignment and replaceable AI profiles.
- Bare worlds by default and the trusted `default-khoros` template, composed from
  five canonical Inventory sources.
- Native Wallet, Messenger, Objective Board, Scratchpad, calculator, Eye, and
  workspace objects, with four holdings for agent equipment.
- Signed local credit records for resource, property, and custody interactions
  within a world.

### Packages and services

- Declarative Object Packages, the Object SDK, typed configuration, capability
  grants, folders, world-bound forks, and host bridges.
- Independent deployments with captured package content, configuration, state,
  durability, locks, identities, and replayable lineage.
- Exact object management, listeners, reports, Marketplace restocking, and
  explicit copy deletion.
- Replaceable AI profiles with external model-service transports and compatible
  local adapters.
- Swift Crypto for local Ed25519 signing and SHA-256 integrity mechanisms.

### Human surfaces

- A native human console with guided forms, command completion, Unicode editing,
  cancellation controls, and one-shot command execution.
- `khoros shell <agent-selector>` for bounded in-world actions that never become
  an operating-system shell.
- `khoros web`, served by the same native executable, with World, Agent Manager,
  Inventory, Packages, Templates, Settings, and searchable Help views.
- Typed browser projections, exact-world routes, contextual actions, private
  viewers, bounded reports, local pins, and a focused World command dock.
- The browser keeps credentials and private runtime material out of rendered
  views and mediates every capability-bearing action through the native gateway.

### Safety and portability

- Strict typed decoding, bounded payloads, deterministic command catalogs, and
  explicit capability mediation across runtime and browser surfaces.
- Persistent data uses versioned formats with recoverable product transactions.
- Apache-2.0 licensing with third-party dependency, font, and icon attribution
  recorded in [`NOTICE`](NOTICE).
- The supported platform matrix and release checks cover macOS, Linux, and Windows.
