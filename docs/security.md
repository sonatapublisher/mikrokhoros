# MikroKhoros security architecture

This document describes the implemented CLI-first threat model. It complements the
private-reporting instructions in [`SECURITY.md`](../SECURITY.md) and the normative
runtime behavior in [`design.md`](design.md).

## Security goal

An LLM proposes bounded world actions. It is never trusted to authorize itself,
identify its caller, prove possession, protect a secret prompt, or decide whether a
side effect is allowed. Swift code validates every state transition against the
authoritative world.

Prompt injection remains possible at the model-behavior layer. The security goal is
that injected or echoed text cannot independently grant capabilities or escape the
MikroKhoros action/object boundary.

## Trust boundaries

Higher-trust components:

- the human administration surface;
- compiled runtime code and its validated configuration;
- runtime-issued world, agent, object, installation, and invocation identities; and
- explicit capability grants stored outside model-visible text.

Untrusted or lower-trust data:

- human and agent Messenger bodies and sender labels;
- object names, summaries, public metadata, function results, and bundle content;
- Library source URLs and fetched document text;
- provider output, previous model-visible history, and compaction checkpoints;
- internet or user-machine results returned by future object bridges;
- workspace files before schema validation and deterministic replay; and
- repository issues, pull requests, linked documents, and examples consumed by a
  coding agent.

The system contract has higher model-message authority than mutable events, but it
is not a secret and is not an authorization database.

## Implemented controls

### Role and data separation

- `AgentModelRequest.system` contains only the stable action/world contract.
- `AgentModelRequest.input` contains the current quoted event and self-state
  envelope.
- Provider adapters preserve those roles instead of concatenating them.
- The final user-role request is the canonical source for live world state.
- The complete system field is rebuilt on every request, including after history
  compaction.
- Compaction inserts a data-only `context_scope` marker that names
  `current_request` as the state source. It carries no generated summary.

### Input and output validation

- Mutable model-facing values are bounded and emitted as JSON strings, which are
  valid YAML 1.2 quoted scalars.
- Model responses, provider payloads, history, total context, action count, and
  individual actions have independent user-configurable runtime limits.
- A failed request build restores drained events before returning, including failures
  caused by the configured broadcast, input, history, or total-context limits.
- Invisible Unicode formatting controls are rendered visibly in mutable fields and
  rejected in model output. Compatibility normalization is applied during overlap
  screening.
- Persisted model history must have canonical event-envelope or action-line shape and
  fit the workspace storage boundary before restore. It is compacted to the active
  history character/message settings before provider use.
- Every nonempty response line must be a complete MikroKhoros action. Markdown,
  prose, and operating-system shell syntax are rejected.
- Only the configured action prefix can run, and the first action error stops the
  remaining prefix.
- Before execution, model output is screened for long verbatim word windows copied
  from the privileged system contract, current request, or earlier provider-visible
  user context. A match is rejected without reproducing the matched text.
- This exact-overlap screening is defense in depth. Reworded or fragmented leakage
  may evade it, and it must not be used as an authorization check.

### Complete mediation and least privilege

- Identity, containment, possession, material occupancy, pickup locks, payments,
  world membership, and object capabilities are enforced in the runtime.
- Broadcast source ID, type, unread event ID, and current hand/backpack possession
  are revalidated when building a request.
- Agent-to-agent messages resolve the recipient agent ID to its runtime-registered
  genesis Messenger. Notification delivery separately revalidates the exact
  Messenger object's current carrier.
- Object invocations receive trusted caller/world/install identities from the
  runtime, never from model arguments.
- Installation grants must be requested explicitly, are scoped to one world, and can
  be revoked.
- Coding-agent CLIs require a role-separated bridge and are not launched with their
  ordinary filesystem or shell tools.
- Declarative object packages expose only a closed action set. A JavaScript manifest
  is metadata and cannot execute.
- The human administration CLI owns Library network fetching. It accepts
  credential-free, fragment-free HTTPS or plaintext loopback HTTP sources, uses an
  ephemeral cookie-free session, byte-bounds the response with the configured
  provider/external response limit, and requires non-empty UTF-8 text.
- Stored document functions return configurable bounded pages labeled
  `external_untrusted`. The result remains quoted mutable data while runtime-issued
  identity and capability checks mediate world actions.
- Decoded profiles pass the same validation as profiles created interactively.
  Remote endpoints require HTTPS; plaintext endpoints are loopback-only and cannot
  receive environment credentials.

### Persistence and diagnostics

- Human defaults and advanced runtime policy are loaded from a separately validated
  configuration file. Every published numeric request/execution boundary is
  configurable through `khoros config`; structural relationships between values are
  validated before an atomic save.
- A missing configuration file selects documented defaults. Corrupt, unsupported, or
  structurally invalid configuration fails closed. `khoros doctor` validates the
  effective configuration and workspace without mutating either.
- The runtime ceiling and per-agent action preference are separate. The smaller value
  is effective, so lowering a global ceiling does not make existing agent records
  unloadable.
- Credential values are resolved from environment variables only at provider-call
  time and are never placed in profiles or workspaces.
- Rejected raw model output is not persisted, echoed, or included in error details.
- Model history stores successful canonical action lines and bounded result
  envelopes. Failed action text stays outside provider-visible history.
- Successful canonical action effects, externally issued message IDs/timestamps, and
  runtime-generated entropy are journaled for deterministic replay.
- World-genesis IDs, objective/document placements, and exact Athena notice delivery
  IDs/timestamps are persisted. Schema 1 worlds derive stable facility IDs from the
  existing world identity during migration.
- Corrupt, oversized, unsupported, or semantically unreplayable workspaces fail
  closed.
- Provider errors use bounded stable categories and do not include response bodies,
  headers, tokens, or mutable endpoint content.
- Built-in and declarative-object failure messages do not interpolate object names,
  private-state keys, rejected actions, or other attacker-controlled payload text.
- Provider JSON is byte-bounded, Gemini credentials are sent in a header instead of
  the URL, and direct OpenAI Responses requests set `store: false`.

### Human administrative reads

- `world inspect` is a human-only live-state view. It includes object-private state,
  private messages and receipts, pending notifications, and AI profile metadata; it
  is never included in an LLM request or broadcast.
- `world export` exposes the complete persistent journal and model-visible histories
  to the human. Its output has the same confidentiality boundary as
  `~/.mikrokhoros/workspace.json`.
- Administrative JSON uses structured encoding, so stored newlines and terminal
  control characters remain encoded rather than becoming output structure or
  terminal commands.
- Neither view resolves credential environment variables. A profile can reveal the
  variable name it references, while the secret value remains process-only.
- Object designers cannot invoke these CLI reads as an object capability. A future
  browser UI must authenticate the human administration boundary before exposing the
  same typed snapshots.

The human owns advanced policy and can deliberately trade resource use against
strictness. Larger size/count settings increase memory, provider, and execution
exposure. A smaller `minimumProtectedVerbatimWords` value makes exact-overlap
screening stricter; a larger value makes that defense-in-depth check less sensitive.
Runtime authorization remains independent of every such setting.

## Prompt echoing policy

MikroKhoros distinguishes a required action receipt from uncontrolled prompt echo:

- A successfully validated action is quoted once in its result so the agent can map
  output to the action it chose.
- A failed or rejected action omits the command entirely.
- Raw model responses are never automatically sent to Messenger, another agent, an
  external service, or a log.
- Long direct copies of system or provider-visible user context are rejected before
  any action can reach an object function.
- A future outbound sink must validate its arguments and effective capability at the
  sink. Sensitive, destructive, financial, or data-sharing sinks require a separate
  human-approval design.

No model-level defense guarantees that an LLM will never paraphrase or disclose
something it has seen. Therefore model-visible text contains no secret whose
disclosure grants authority.

## Verification

The test suite includes adversarial cases for:

- fake YAML/system fields in Messenger and object metadata;
- rejected command non-echo and non-persistence;
- attacker-controlled object metadata omitted from model-visible failures;
- direct system-instruction replay inside a candidate object action;
- current request-envelope echo inside a candidate object action;
- earlier request/result-context echo across turns;
- compatibility-encoded replay and invisible formatting controls;
- oversized model output rejection before overlap scanning;
- oversized broadcast-batch rejection with pending-event preservation;
- broadcast possession and source-identity validation;
- provider-failure restoration;
- Athena delivery to stable messenger identity while notification remains
  possession-gated;
- agent-ID/thread message routing, stable device identity, sender/recipient copies,
  and dropped-device unread delivery;
- external document trust labeling, quoted paging, TLS-or-loopback source policy,
  and response bounds;
- data-only compaction with system-contract reinjection;
- forged/orphaned persisted history and revalidated decoded profiles;
- plaintext endpoint and credential-transport restrictions;
- capability grants and trusted invocation identities;
- world-genesis identity validation and deterministic schema migration; and
- corrupt workspace fail-closed behavior.

The CI matrix runs tests and release builds on macOS, Linux, and Windows. Prompt,
object-capability, provider, persistence, or external-sink changes should add a
focused regression case before merge.

## Known limitations and future requirements

- Exact-overlap screening cannot detect every paraphrase, encoding, distributed
  fragment, or semantic exfiltration attempt.
- The system prompt is intentionally assumed discoverable.
- Remote endpoints use TLS, but custom HTTPS endpoints are still user configuration;
  production deployments should add allowlists, rate limits, redirect policy, and
  network egress controls suited to their environment.
- The current CLI workspace is a local single-user store, not a multi-tenant access
  control system.
- Native Swift objects are trusted host code.
- Executable community objects require process/runtime isolation, CPU/memory/time
  quotas, filesystem and network policy, SSRF protection, audited capability handles,
  revocation at every sink, and adversarial testing before they can ship.
- The future browser UI requires localhost origin/Host validation, CSRF protection,
  authentication decisions, output encoding, and safe rendering of model/object
  content.
- The future Hall requires authenticated peer identity, message integrity, replay
  protection, per-world authorization, and cross-agent isolation.

## Research basis

The design follows defense-in-depth themes from:

- [OWASP LLM Prompt Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/LLM_Prompt_Injection_Prevention_Cheat_Sheet.html): structured separation, validation, least privilege, monitoring, and adversarial testing.
- [OWASP AI Agent Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html): complete mediation, scoped tools, memory-poisoning controls, and CI regression gates.
- [OWASP MCP Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/MCP_Security_Cheat_Sheet.html): untrusted tool outputs, external-sink validation, sandboxing, and explicit approval for consequential actions.
- [OpenAI, Improving instruction hierarchy in frontier LLMs](https://openai.com/index/instruction-hierarchy-challenge/): preserve trust ordering and treat tool/data instructions as lower authority.
- [OpenAI, Understanding prompt injections](https://openai.com/safety/prompt-injections/): layered protection, limited access, explicit requests, review, monitoring, and red teaming.
- [Anthropic, Context editing](https://platform.claude.com/docs/en/build-with-claude/context-editing): active context curation, whole-result clearing, and compaction for long-running sessions.
- [Cheng et al., Contextual Drag](https://arxiv.org/abs/2602.04288): failed attempts can bias later reasoning toward structurally similar errors.
- [Lou and Sun, Anchoring Bias in Large Language Models](https://arxiv.org/abs/2412.06593): initial hints can disproportionately influence later judgments.
- [Peng et al., RepeatLeakage](https://doi.org/10.1609/aaai.v39i25.34832): repetition requests can extract system and conversation context.

These references inform the architecture; deterministic tests and code remain the
project's enforceable contract.
