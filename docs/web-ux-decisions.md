# mikrokhoros Web UX decisions

Status: canonical rationale for the implemented mikrokhoros Web interface

This document records why mikrokhoros Web is organized as it is. Product
behavior remains authoritative in `design.md`, security boundaries in `security.md`,
visual rules in `ui-design.md`, and live operations in the exhaustive command
catalog. The products below are interaction references, not mikrokhoros domain or
visual-design dependencies.

## Association model

| Reference pattern | mikrokhoros relationship | Adopted rule |
| --- | --- | --- |
| VS Code keeps a dominant editor, a primary sidebar, a searchable Command Palette, and a movable bottom Panel for Output and Terminal content. | A world is the dominant spatial work surface; human commands and their output are supporting tools. | World retains the canvas, the catalog-derived command field floats at its bottom edge, and Output, Agent, and Object context share one resizable and minimizable panel. Commands stay searchable and keyboard reachable. |
| Blender divides task work into Areas and gives each editor a prominent main Region with contextual Regions around it. | World, Agent Manager, Inventory, Packages, and Templates are different kinds of work, while selected objects and command output are contextual. | Each primary view has one dominant work region. Contextual information uses bounded panels and overlays instead of permanently subdividing every view. |
| Godot's Inspector follows the selected object and renders the properties that object exposes, with search and grouped sections. | mikrokhoros packages declare `ObjectManagementInterface`; package identity supplies data and behavior rather than host-authored product screens. | Selecting an object opens one host-owned, schema-rendered interface. The host owns controls, validation, focus, confirmation, and encoding; package-specific screens are not hard-coded. |
| Home Assistant distinguishes devices from their entities and organizes large user-owned collections with explicit areas, labels, filters, and selectors. | Agent identities, Inventory sources, packages, templates, deployed objects, and exact worlds have different ownership and lifecycle scopes. | Agent Manager remains a user-global identity catalog. Inventory remains a user-global source catalog with an explicit exact-world activity scope. World presence never replaces either global catalog. |
| Backstage presents a centralized catalog of typed entities and their relationships, while a template describes both parameters and steps. | Packages and trusted templates are user-global definitions; applying or deploying them creates or changes exact-world state. | Packages and Templates are global catalog views. A world selector appears inside an action only when that action needs an exact target. Neither view owns a persistent world picker. |
| Grafana alert history combines a scoped event list, filters, expandable detail, and a live operational view. | Object reports belong to one exact world and can be listed, inspected, or followed. | Notifications are a quick exact-world report preview. Inventory exposes report history and an explicit follow mode with bounded output and clear start/stop state. |
| A property inspector distinguishes declared affordances from live private state. | Object packages declare field/action/view/report metadata while Inventory holds source configuration, credential references, readiness, and capability grants. | The generic interface appears only after selecting one exact source or world object. Host controls render declared types, bounds, choices, browser-safe ordered action inputs, result schemas, and report contracts; source values and credentials remain absent. A path-bearing contract keeps metadata visible while its actions and views are CLI-only. |
| Operational dashboards expose a safe retry only when the system can prove work is pending. | Agent notifications and provider state are private runtime data. | Agent Manager receives only a bounded content-free pending-work count and a derived retry availability flag. The Retry control appears only for an active profiled agent with pending work. |

## Shared web workspace frame

Domain pages carry different data densities, but they share one browser surface.
After the sidebar, every non-World view shares a workspace column bounded by
`--workspace-column-max: 1080px` and an inline gutter of
`clamp(18px, 2.4vw, 36px)`. Its title/action header, transient state, and scrollable
content therefore align on the same left and right edges. Compact pages use this
frame without adding a narrower nested column.

Detail hierarchy is established with a 16px section cadence, 8px between paired
fields or controls, and 6px from a label to its immediate supporting content. This
keeps selection, status, and typography legible without per-view horizontal nudges.

The shape system has one smooth non-circular construction:
`--smooth-corner: superellipse(1.78)`. It applies to every non-circular
`border-radius`, including `--pill-radius` capsules and their clipped transparent
Project Genie layers. The three semantic circle/dot selectors use `round`; original
Identity Shape SVGs and masks preserve their project-owned
silhouettes.

The interaction references are the official [VS Code user-interface guide](https://code.visualstudio.com/docs/editing/userinterface), [VS Code custom-layout guide](https://code.visualstudio.com/docs/configure/custom-layout), [Command Palette guidance](https://code.visualstudio.com/api/ux-guidelines/command-palette), [Blender Areas](https://docs.blender.org/manual/en/4.5/interface/window_system/areas.html) and [Regions](https://docs.blender.org/manual/en/4.5/interface/window_system/regions.html), [Godot Inspector](https://docs.godotengine.org/en/stable/tutorials/editor/inspector_dock.html), [Home Assistant organization](https://www.home-assistant.io/docs/organizing/) and [entity model](https://www.home-assistant.io/docs/configuration/entities_domains/), [Grafana alert history](https://grafana.com/docs/grafana/latest/alerting/monitor-status/view-alert-state-history/), and the [Backstage catalog](https://backstage.io/docs/features/software-catalog/) and [system model](https://backstage.io/docs/features/software-catalog/system-model/). These sources were reviewed on 2026-08-23.

## Product information architecture

The mikrokhoros Web menu contains exactly five primary destinations, in this order:

1. World
2. Agent Manager
3. Inventory
4. Packages
5. Templates

Settings is fixed in the sidebar footer. Help is a global overlay generated from the
same command contract as contextual execution. It is the searchable full command
reference. Only World owns a persistent world picker.

World is a spatial editor. Its sidebar shows My view, the stable active-agent roster,
Inventory, and pinned exact objects. The map remains the primary region. Agent and
object selection changes contextual information without creating parallel domain
models. The command field uses the same catalog, parser, defaults, validation, and
execution path as the CLI, while the browser supplies trusted product and exact-world
context. The bounded dock is immediate exact-world tooling. World management and
object operations stay with their selected context while Help remains the complete
command reference.

Each primary view owns a single scrolling workspace, while the World sidebar middle
and each domain sidebar content region scroll independently beneath fixed local
chrome. This preserves stable navigation and a dominant work region without nested
competing scroll areas. Scroll restoration is page memory keyed to the open view and
selected entity, keeping revisit continuity without turning reading position into
product state. On desktop, a restrained edge separator resizes the expanded sidebar
as a presentation-only hint; its soft blurred boundary preserves one continuous warm
field between navigation and work surface.

Agent Manager is the user-global identity catalog. It distinguishes a user-owned
identity, its optional one-world assignment, and the presence of its concrete agent
inside that world. Exact-world placement is collected only for operations that need
it. Lifecycle equipment is read-only linking to the exact object interface; Wallet,
Messenger, and object management remain with the selected object. Retry is a compact
contextual action only when the projection reports both a profile and safe pending
work; no notification content is displayed here.

Inventory is the user-global source catalog. Source configuration, credentials,
capabilities, actions, and views remain attached to the source. Deployment, copies,
listeners, reports, and restocking capture or inherit one exact-world target without
turning the source catalog into a world-local list. A selected source makes its
readiness gaps, exact fork/template provenance, world binding, requested/granted
capabilities, and declared field/action/view/report contract legible without
revealing configuration values or credential material.

Packages and Templates are global catalogs. Package installation and removal act on
the product catalog. Browser package installation uses the **Trusted package source**
field and accepts an exact `builtin:<catalog-name>` source or an HTTPS URL. Package
detail presents identity/version, runtime, requested capabilities, installation and
retention state, retained content metadata, source usage, and management counts.
Template definition and lineage are global; its composition table makes every root or
owned object, package, requested parent space, and coordinate visible. Definition
rows use the neutral Phosphor Cube because canonical identity belongs to an
instantiated object. Status, application, and repair are exact-world actions and
therefore contain their target selector in the action form; Create World is compact
overflow work.

Settings owns product status, configuration, validation, diagnostics, adapters, and
the running local-host projection. Running `web` from within mikrokhoros Web is
represented as current host status rather than recursive host creation.

Each non-World destination reads a purpose-built bounded projection at
`/api/v1/agents`, `/api/v1/inventory`, `/api/v1/packages`, `/api/v1/templates`, or
`/api/v1/settings`. These projections make the domain hierarchy and detail visible before
an action is chosen. They contain only renderable summaries; command results are not
reused as the browser’s source of truth.

## Contextual actions and command reference

Every live `CommandKind` has one explicit browser policy and one Help reference.
Descriptors retain canonical paths, summaries, field cardinality, safe defaults,
completion kind, history policy, world scope, confirmation mode, and refresh targets.
The browser uses them behind named contextual controls. Typed domain projections
define browser navigation and selected content. The browser sends a capability
identifier and typed field values; it never sends raw process arguments, product
paths, output/color globals, or an executable shell command.

`inventory show` and commands whose terminal output contains a raw administrative
object snapshot are disabled reference entries. Their browser workflows use bounded
domain and exact-object projections instead. If a selected management contract
declares any filesystem-path field or path-typed action input, its actions and views
are CLI-only; configuration-backed views are always CLI-only. Browser mutation
results expose only configuration-key presence, while path-free typed actions and
non-configuration views remain operational.

Ordinary finite operations execute in-process against the exact launch layout.
Destructive or consequence-bearing operations use prepare and commit so the visible
plan, exact world, normalized values, and persistent product fingerprint are bound to
a short-lived single-use plan and revalidated inside the product lock.
Secret values use a write-only request path and never appear in descriptors,
transcript, history, browser storage, URLs, or returned output. The agent controller accepts only
bounded in-world actions. Report follow is an explicit session-expiring bounded
stream with a visible stop control. Private inspection and export use deliberate
reveal/download modes and a data-sensitivity warning.

## Accessible interaction rules

Custom comboboxes follow the WAI-ARIA [Combobox Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/combobox/): the trigger has an accessible name and value, the popup is collapsed by default, arrow keys navigate options, Enter commits, and Escape closes without changing the previous value.

Modal surfaces follow the [Modal Dialog Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/): background content is inert and visually receded, focus enters the dialog, Tab and Shift-Tab remain contained, Escape closes where safe, a visible close or cancel action is present, and focus returns to the invoking control.

Output, Agent, and Object follow the WAI-ARIA [Tabs Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/tabs/): one tab is active, its panel is labelled, arrow keys move within the tab list, and a keyboard shortcut can select each tab. Context can be frozen so pointer movement does not erase information needed for reading or keyboard operation.

## Validation implications

- Verify each contextual control uses the declared safe execution policy and Help
  presents every command through its searchable reference.
- Verify the typed Agent Manager, Inventory, Packages, Templates, and Settings
  projections render domain data without parsing action output or revealing omitted
  private fields.
- Verify keyboard-only app navigation, comboboxes, dialogs, tabs, command completion,
  confirmation, report-follow start/stop, panel/sidebar resizing, minimization, and
  focus restoration.
- Verify each view, selected entity detail, World sidebar middle, and domain sidebar
  content has one independent scroll owner; headers, search/filter controls,
  contextual actions, and Settings remain fixed within their regions.
- Verify sidebar pointer capture/cancel, Arrow keys, Home, End, and `0` honor the
  bounded desktop width, preserve a 480px workspace minimum, and disable resize for
  the collapsed rail and narrow viewports.
- Verify the layout at the reference desktop viewport and a narrow viewport without
  clipping World controls, contextual action sheets, or the fixed Settings
  destination.
- Verify exact-world operations cannot inherit a conflicting route, assignment, or
  browser-supplied global option.
- Verify destructive plans are single-use, expire, are session-bound, and reject
  modified fields or target worlds.
- Verify credentials are write-only and absent from output, diagnostics, HTML, URLs,
  local storage, history, generated help, and error responses.
- Verify untrusted object data, reports, command output, and completion labels render
  only as inert text.
