# MikroKhoros Web design QA

Date: 2026-08-23

This record captures the current implemented browser contract and its local
verification. The verification platform is macOS; the GitHub Actions matrix remains
the authority for Linux and native Windows execution.

## Application structure

The custom MikroKhoros Web menu contains five primary destinations, in order:

1. World
2. Agent Manager
3. Inventory
4. Packages
5. Templates

Settings and searchable Help remain fixed global controls. Only World owns a
persistent World picker. Other views collect an exact World inside the action that
needs it. Package-defined human management appears only through the exact selected
Inventory source or exact selected World object's structured
`ObjectManagementInterface`.

## Shared visual contract

- Chrome uses Google Sans Flex with `ROND` 100. Reading content uses the native
  system sans-serif stack. Structural identifiers, paths, coordinates, and command
  text use the native system monospace stack.
- Routine buttons, dropdown triggers, tabs, and clickable rows are 32px high. Every
  standalone action, pressed toggle, modal or dialog control, icon control, and closed selector is a
  complete capsule; list rows, menu options, cards, console tab segments, and World
  cells retain their local row, card, segmented, or map geometry.
- Clipped 32px glass controls use a 20px text line box, preserving full glyph
  ascenders and descenders with 6px of vertical clearance.
- Capsule controls use a complete pill silhouette, clipped backdrop blur, and a
  light-only directional rim treatment. Menus, popovers, dialogs, and object
  inspectors have no dark border.
- The sidebar and work surface meet through a warm translucent fade and blur rather
  than a full-height divider. Its desktop-only resize separator is a quiet soft grip,
  never a hard divider or a sidebar-row overlay.
- Major overlays use a 32px smooth radius. Rows and ordinary editable inputs use
  the smaller local 12px surface radius; the `--pill-radius` capsule is reserved
  for standalone controls and closed selectors, including domain search.
- Every non-circular `border-radius` uses
  `--smooth-corner: superellipse(1.78)`, including `--pill-radius` capsules,
  menus, overlays, cards, rows, fields, and clipped Project Genie layers. The three
  semantic circle/dot selectors use `round`; Identity Shape SVGs and
  masks keep their authored geometry.
- Every non-World web page resolves its title/action header, transient
  state, and scrollable content to one frame: `--workspace-column-max: 1080px`
  with `--workspace-inline-gutter: clamp(18px, 2.4vw, 36px)`. Compact pages use
  the same frame with exact matching left and right edges. Shared detail sections
  use a 16px section cadence, 8px paired-field/control gap, and 6px label-to-content
  gap without ad-hoc horizontal offsets.
- Phosphor supplies every web control icon. MikroKhoros agent and object
  identities use the original single-body filled shapes.
- The eight deterministic identity shapes and twelve deterministic identity colors
  are independent axes. World zoom scales cells, dots, fills, outlines, held-object
  silhouettes, counts, and labels together.

## World interaction contract

- The World is a continuous warm canvas. Adjacent 48px rounded-square cell targets
  touch without gaps. Empty cells show only a quiet 3px dot; occupied cells suppress
  it.
- Empty-hand agents use their identity-color inner outline. Holding agents use the
  identity-color fill with one high-contrast held-object silhouette. No separate
  agent icon is drawn over the map cell.
- Clicking an agent starts live follow. My view restores its saved container,
  camera, and zoom without changing the stable roster order.
- The direct roster shows every active agent and collapses only when more than three
  are present. Add agent opens the exact-world form.
- Single click, Enter, or Space opens a custom cell menu. Dragging begins only after
  the movement threshold. Double-clicking a container opens that exact container.
- While an object menu is open, the next empty-cell click dismisses the menu and
  consumes the activation. A later click can open the empty-cell menu.
- Selecting an object opens the generic host-owned interface. Its last selected page
  is remembered per exact World and exact object.
- Notifications sit immediately left of View and open recent reports from the exact
  World. Report detail preserves World, object, Inventory, package, and stored report
  lineage.
- The command dock separates a monospace input capsule from the resizable,
  minimizable Output, Agent, and Object information panel. The `1`, `2`, `3`, and
  `C` shortcuts preserve tab selection and frozen context.

## Domain-view contract

- World sidebar middle, domain sidebar content, and the web workspace each
  have exactly one scroll owner. Local headers, search/filter controls, contextual
  actions, and the Settings footer stay fixed; selected view/entity scroll position
  is page memory only.
- The desktop expanded sidebar starts at 240px and resizes from 208px to a dynamic
  352px maximum while preserving a 480px workspace minimum. Its focusable separator
  supports pointer capture/cancel, Arrow keys, Home, End, and `0`; it is disabled
  for the collapsed rail and at 760px or less.

- Agent Manager lists user-owned identities, assignment, concrete presence,
  holdings, and lifecycle equipment. Retry appears only for an active profiled agent
  with projected pending work.
- Inventory lists canonical folders and sources with readiness, capability,
  package, template, binding, and fork provenance. Exact source interfaces render
  typed declared field, action, view, and report metadata without configured or
  credential values.
- Packages separates available, installed, and retained entries. Browser acquisition
  accepts only an exact `builtin:<catalog-name>` source or an HTTPS URL whose redirect
  chain satisfies the same browser policy.
- Templates renders every root and owned object with its package, requested parent
  space, and coordinate. Definition rows use the neutral Phosphor Cube because a
  declaration has no runtime object identity. Status and application are
  action-local exact-world work; Create World remains a compact overflow action.
- Settings exposes bounded non-secret product, diagnostic, adapter, terminal, and
  runtime information. Help is the exhaustive searchable command reference, not an
  additional workspace.

## Browser security boundary

- Typed domain DTOs and typed exact-object interfaces are the source of browser
  content. Raw Inventory configuration and administrative object-snapshot commands
  are disabled reference entries.
- A management contract that declares any filesystem-path field or path-typed action
  input keeps its metadata visible while all actions and views are `CLI only`.
  Configuration-backed views are also `CLI only`. The gateway rejects crafted set,
  unset, action, and view requests, and browser mutation results expose only
  configuration-key presence.
- Secrets are write-only. Private reveal and download paths are explicit. Bounded
  output, strict exact-world context, confirmation-plan revalidation, and
  same-origin/session checks remain enforced by the host.
- One server instance owns one atomic listener lifecycle. A concurrent start is
  rejected without replacing the active listener or its resources. Overlapping
  stops join one completion through the idle transition, and stop-before-launch does
  not emit a stale callback.
- An active-session, same-origin root-document reload accepts only the bounded
  canonical route hints `view`, `world`, `container`, `focus`, `agent`, `source`,
  `folder`, `package`, `version`, `template`, and `setting`. Other static assets and
  API routes retain their fail-closed query rules. Session-cookie names are isolated
  by bound loopback port.

## Automated verification

Required regression coverage:

- Root-document `GET` and `HEAD` accept each canonical route-hint combination while
  unknown, duplicate, malformed, and non-document asset queries reject.
- Concurrent loopback ports issue isolated session-cookie names and do not accept a
  peer host's cookie.
- Scroll contracts keep one owner per designated region, preserve fixed chrome, and
  restore page-memory position only for the open view/entity.
- Sidebar resize clamps pointer and keyboard changes, handles pointer cancellation,
  preserves the workspace minimum, and disables at collapsed/narrow breakpoints.
- Static styling coverage must reject a non-circular `border-radius` declaration
  that does not resolve through `--smooth-corner: superellipse(1.78)`, including
  `--pill-radius` capsules and transparent-glass layers. It must preserve the three
  intended `round` circle/dot selectors and leave Identity Shape SVG/mask geometry
  outside the CSS corner contract.
- At reference desktop and narrow viewports, inspect World-adjacent compact pages
  and Agent Manager, Inventory, Packages, Templates, and Settings. In each page,
  the title/action header, transient state, and scrollable content must share the
  1080px workspace frame and responsive inline gutter with no independent
  horizontal offset. Detail sections must retain the 16/8/6 rhythm while scrolling.

- Strict Swift formatting and repository license-header checks: passed.
- Generated CLI reference check: passed.
- JavaScript syntax and static browser-contract assertions: passed.
- Automated capsule/menu assertions passed for native buttons, modal and dialog
  controls, closed custom selectors, domain search, text-only menu tracks, filter
  anchoring, and the local geometry retained by menu rows and World cells.
- Live control review against the rebuilt release and an isolated populated product:
  passed. Agent Manager, Inventory, Packages, Templates, and Settings exposed 15,
  22, 9, 9, and 10 visible standalone controls respectively, with no height, radius,
  or corner-shape mismatch. Assignment and State filter labels rendered in full;
  the Assignment surface matched its 138.2px trigger width and left edge. The
  generated exact-World selector, Add-agent selector and pressed toggle, World-detail
  actions, Help close action, and dialog actions also resolved to 32px complete
  capsules. Browser diagnostics contained no warning or error.
- Release-browser review against an isolated current-schema populated World,
  Templates, and Agent Manager: passed with no console warning or error. The live
  app-view capsule measured 32px high with a 20px label line box and 6px clearance;
  domain entity rows resolved to 12px local radii.
- Rebuilt shared-frame review at 1516 × 861: Agent Manager, Inventory, Packages,
  Templates, and Settings each measured 0px left- and right-edge drift between the
  title/action header and scrollable content. Available entity headers and first
  detail sections also measured 0px drift. Reviews at 1050 × 861, 759 × 861, and
  390 × 844 retained the common responsive frame with no horizontal overflow;
  long Inventory content scrolled inside the web workspace while the body
  remained fixed. Keyboard sidebar resize produced exact 208px, 240px, and 352px
  widths without changing the content alignment.
- Web capability gateway tests: 28 tests, 0 failures.
- Web backend and static-resource tests: 37 tests, 0 failures.
- Full XCTest suite: 320 tests, 0 failures.
- Preflight with an external SwiftPM scratch path and warnings as errors: passed.
- Release build with warnings as errors: passed.
- CLI lifecycle test: passed.
- Terminal PTY smoke test at 120 by 30: passed.
- `git diff --check`: passed.
- Protected identity shield SHA-256:
  `435db35a8dd31a78156c7094391e1f65cbba048fa368129063b085dac947401d`.
