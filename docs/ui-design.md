mikrokhoros browser UI design specification

Status: Canonical visual and interaction contract
Version: 2.0
Command: khoros web
Platforms: macOS, Linux, and native Windows
Runtime authority: ../README.md, design.md, security.md, and the exhaustive
human command catalog
View, scope, and command-coverage authority: design-v2.txt
Current delivery: World, Agent Manager, Inventory, Packages, Templates, Settings,
and searchable Help are implemented through typed services.


1. PRODUCT EXPRESSION

The browser is the graphical human-management surface for the installed
mikrokhoros product. It projects typed services into deliberately
designed domain views. The command catalog supplies execution and searchable Help
infrastructure; typed domain projections supply the visible browser hierarchy.
A selected Inventory source or concrete world object uses
`ObjectManagementInterface` and the runtime-owned base management interface.

The visible product name is always lowercase mikrokhoros.

The shell presents five app views:

1. World
2. Agent Manager
3. Inventory
4. Packages
5. Templates

Settings is a fixed global destination in the sidebar footer.

The current world is a default command target. User-global catalogs remain
user-global. Exact-world forms collect or inherit one exact target according to the
same rules as the CLI.

Only object interfaces are generated from structured contracts. The host owns their
controls, layout, validation, confirmation, encoding, focus behavior, and service
calls. Package identity selects data and runtime behavior while the shared contracts
generate the selected object surface.


2. COLOR SYSTEM

The interface uses a warm continuous canvas with white reserved for raised menus,
inspectors, and substantial content surfaces.


2.1 FOUNDATION COLORS

Token                  Value      Intended use
---------------------  ---------  ----------------------------------------------
canvas                 #F3EFEA    Application and world canvas
surface-subtle         #F8F5F1    Sidebar and quiet inset regions
surface-primary        #FFFFFF    Raised menus, panels, and floating controls
surface-hover          #ECE7E1    Neutral hover treatment
surface-selected       #E4E8FF    Selected row, tab, or navigation state
border-subtle          #DED8D1    Quiet local boundary
border-strong          #BEB6AE    Focused or important boundary
text-primary           #25221F    Titles, values, and primary labels
text-secondary         #625C55    Descriptions, timestamps, and metadata
text-tertiary          #857E76    Placeholders and disabled supporting text
icon-muted             #756F68    Inactive monochrome icons


2.2 INTERACTION AND FEEDBACK COLORS

Token                  Value      Intended use
---------------------  ---------  ----------------------------------------------
accent                 #4057D6    Focus, link, selection marker, unread state
accent-soft            #E4E8FF    Quiet selected background
button-glass           transparent Resting capsule surface
button-glass-text      #25221F    Capsule label
button-glass-hover     #FFFFFF2E  Hover and focus wash
button-glass-pressed   #25221F0F  Pressed wash
button-glass-edge      #FFFFFFDB  Diffused light inset reflection
success                #13795B    Healthy, connected, complete, usable
success-soft           #DBF1E8    Success background
warning                #A84F00    Waiting, degraded, attention needed
warning-soft           #FCE8D0    Warning background
danger                 #C0362C    Failed, blocked, destructive, disconnected
danger-soft            #F7DDD9    Danger background
focus-ring             #4057D6    Keyboard focus ring


2.3 WORLD SYMBOL COLORS

Token                  Value      Intended use
---------------------  ---------  ----------------------------------------------
dot-empty              #D4CEC7    Empty visible world position
symbol-selected-ring   #25221F    Selected world target ring
symbol-unknown         #756F68    Unknown or undisclosed state
symbol-contrast-dark   #151515    Held-object glyph over a bright agent marker
symbol-contrast-light  #FFFFFF    Held-object glyph over a dark agent marker

Stable bright identity palette:

Index  Token            Value
-----  ---------------  --------
0      bright-blue      #246BFE
1      bright-violet    #6C4DFF
2      bright-purple    #A33CFF
3      bright-magenta   #D82D86
4      bright-red       #E54D42
5      bright-orange    #E26400
6      bright-amber     #9A6A00
7      bright-lime      #5E7F00
8      bright-green     #009B65
9      bright-teal      #00969B
10     bright-cyan      #007DB3
11     bright-indigo    #4A57D1

Interface chrome uses the vendored Phosphor Bold set at the compact 14...16px
control scale. Entity identity uses the original mikrokhoros Identity Shapes set.
Search fields use the plain Phosphor Magnifying Glass. Magnifying Glass Plus and
Minus are reserved for the explicit World zoom actions.

The shape/color identity is independent:

- The first canonical identity byte selects one of eight deterministic mikrokhoros
  Identity Shapes by integer-division buckets of 0x20.
- The second canonical identity byte selects one of 12 canonical colors by modulo 12.
- The two axes are independent; remaining bytes do not change shape or color.
- Identity symbols are project-owned, filled, single-body SVG silhouettes from the
  exact bundled allowlist; no runtime external source is permitted.

The visual origin of identity symbols is the `mikrokhoros Identity Shapes` set, not
an interface-control or agent-/object-specific glyph library.

2.4 CONTRAST RULES

- text-primary on canvas is approximately 13.8:1.
- text-secondary on canvas is approximately 5.8:1.
- accent on canvas is approximately 5.2:1.
- success, warning, and danger on canvas each exceed 4.5:1.
- text-tertiary is reserved for placeholders and disabled supporting text.
- Status, priority, selection, readiness, and occupancy always include a non-color
  cue.
- Transparent controls are contrast-tested against their composited background.


3. TYPOGRAPHY


3.1 INTERFACE TYPE

Google Sans Flex is used for the wordmark, app chrome, titles, headings, section
labels, buttons, dropdowns, tabs, and compact navigation labels.

Every Google Sans Flex size and weight uses:

  font-variation-settings: "ROND" 100;


3.2 BODY TYPE

Descriptions, explanatory copy, form values, report prose, table prose, notification
previews, and other reading-heavy content use the native system UI stack:

  -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif


3.3 MONOSPACE TYPE

Structural paths, coordinates, complete runtime IDs, package identifiers, object
types, CLI commands, raw actions, and structured data use the native cross-platform
system monospace stack.


4. GEOMETRY AND DENSITY

The interface is compact, rounded, and content-led.

Token or element                    Value
----------------------------------  ---------------------------------------------
Routine control height              32px
Routine icon-only control           32px by 32px
World command input height          40px
Capsule corner radius               `--pill-radius`; resolves as a complete smooth capsule
Major overlay corner radius         32px
World command panel corner radius   24px
Menu or compact popover radius      16px
Row, input, and small surface radius 12px
Standard pane padding               8px
Reading-heavy pane padding          12px
Spacing scale                       4, 6, 8, 12, 16, and 24px
Routine icon size                   14...16px
Routine label size                  14px, medium weight

Rules:

- Buttons, dropdown triggers, clickable rows, tabs, compact actions, and modal
  actions share the 32px routine height. Every standalone action, pressed toggle,
  dialog, icon, and closed selector trigger is a complete capsule; Project Genie refraction remains
  limited to its designated chrome controls. Repeating sidebar rows, menu items,
  report rows, tabs, and world cells use flat row or map treatments.
- The domain search control is a complete capsule. Editable fields and content
  surfaces keep the local-radius treatment unless they are a closed selector trigger.
- Labels can make a control wider while its height remains fixed.
- Clipped 32px glass controls use a 20px label line box. This preserves complete
  Google Sans Flex descenders while retaining one-line horizontal ellipsis.
- Icon-to-label gaps are 4px or 6px.
- Top-level controls sit 12...16px from the viewport edge.
- Header and footer bands wrap their 32px controls with approximately 6px vertical
  inset.
- Settings is the full-sidebar-width capsule exception; other routine controls are
  content-sized.
- `--smooth-corner: superellipse(1.78)` applies to every non-circular
  `border-radius` declaration, including `--pill-radius` capsules, cards, menus,
  overlays, rows, fields, and their clipped transparent-glass layers. The three
  semantic circle/dot selectors explicitly use `round`; original
  Identity Shape SVGs and their masks remain their own geometry.
- Numeric radius tokens remain authoritative. A capsule keeps its full capsule
  silhouette while using the shared smooth-corner construction.
- Major content groups use alignment, typography, and restrained tonal shifts.
- Reading space belongs to content rather than decorative padding.

Shared web workspace frame

Every non-World web page uses one horizontal frame after the sidebar. The frame is
bounded by `--workspace-column-max: 1080px` and
`--workspace-inline-gutter: clamp(18px, 2.4vw, 36px)`. Header, transient state,
and workspace content use exactly the same left and right edges. Compact views
use that same frame; no view adds a second content column or a local horizontal
offset.

Shared detail sections use a 16px section cadence, 8px between paired fields or
controls, and 6px between a label and its immediate supporting content. Alignment
carries hierarchy; a detail surface does not create hierarchy through arbitrary
left margins.

World interactions use an equal-width, equal-height rounded-square target with a
60% superellipse profile. The base cell is 48px square. Cell centers are one cell
width apart, so adjacent cells touch without gaps. Zoom scales the complete cell
grammar together: target, empty dot, identity shape, outline, count, and label.
Ordinary border-radius remains the fallback when corner-shape is unavailable.


5. TRANSPARENT-GLASS CONTROLS


5.1 CONSTRUCTION

Every designated capsule rests on a transparent surface so the warm canvas remains
visible. The Project Genie construction is literal: the complete pill clips
approximately 20px of backdrop blur; an inset pseudo-element supplies the diffused
one-pixel inner reflection; and two non-interactive masked edge layers provide the
upper-left and lower-right light refractions. All three edges remain translucent and
form the complete perimeter treatment.

Only designated standalone controls use this construction. Floating menus,
popovers, the object interface, toasts, repeating rows, tabs, and selected world
targets do not. Floating surfaces use their separate rounded treatment with a soft
light-only rim. Selected world targets use the outer ring defined by the World symbol
grammar.


5.2 STATES

Rest
  Transparent surface, dark label, clipped backdrop blur, and diffused light inset
  reflection.

Hover
  #FFFFFF2E wash with a steady reflected edge.

Pressed
  #25221F0F wash, reduced highlight, and at most 1px downward content movement.

Keyboard focus
  Two-pixel accent ring with a two-pixel canvas-colored offset.

Loading
  Original width is preserved and accessible status text is exposed.

Disabled
  Legible reduced contrast and a persistent disabled cue.

Destructive
  Shared geometry with danger semantics after the action is identified.


6. CUSTOM DROPDOWNS AND POPOVERS

A dropdown consists of one closed button and one anchored floating menu.

Closed trigger:

- exactly 32px high;
- transparent-glass capsule;
- selected icon, selected label, and a small chevron;
- content-sized width; and
- an accessible name describing the selected context.

Open menu:

- surface-primary with a 16px outer radius;
- restrained light-only directional rim and 6px outer padding;
- 32px flat selectable rows with 8...10px horizontal insets;
- restrained flat hover and selected tints without capsule blur or reflection;
- checkmark and text weight for the current selection; and
- internal scrolling after eight visible options.

Text-only option rows use `minmax(0, 1fr) auto`: their label occupies the first
flexible track and optional state occupies the trailing track. Icon-bearing rows
keep their leading icon track. Menus start-align with their trigger unless an
explicit end-aligned overflow action defines otherwise, fit their bounded content,
and use an opaque surface that keeps underlying list rows visually separate.

One dropdown or popover is open at a time. Escape and outside activation close it.
Choosing an item closes it and restores focus to the trigger.

Short, soft separators appear only between distinct action groups. Ordinary menu
rows use spacing and selection treatment.


7. APP SHELL

The desktop shell has two persistent regions:

1. an expanded 240px sidebar in the canonical 1536 by 1024 state; and
2. the active app view filling the remaining viewport.

The sidebar can collapse to a compact rail. Responsive desktop widths may reduce the
expanded width while preserving complete labels and 32px controls.

The sidebar and active view meet through a warm surface shift, a narrow soft edge
fade, and restrained 16...20px backdrop blur. There is no hard divider. At desktop
widths an otherwise quiet, focusable vertical separator becomes a small soft grip on
hover, keyboard focus, or active drag; it never overlaps a sidebar row.


7.1 SIDEBAR ZONES

Fixed header
  Lowercase mikrokhoros wordmark.
  Compact sidebar toggle.
  App-view button.
  View-owned context immediately below the app-view button.

Scrollable middle
  The active app view's navigation, catalog, filters, and shortcuts.
  The scroll gutter and edge fade reserve their own space and never cover a row's
  icon, label, status, disclosure, or hit target.

Fixed footer
  Full-width Settings capsule.

The header and footer stay fixed while the middle region scrolls. The World sidebar
middle and a domain sidebar's content each have exactly one scroll owner. The active
web workspace has its own single scroll owner, so an item detail can scroll
without moving its sidebar header, search/filter controls, contextual action strip,
or Settings footer. A view or selected entity may restore its current page-memory
scroll position while open; scroll position is never a persistent preference.

The expanded desktop sidebar defaults to 240px and can be resized from 208px to a
dynamic maximum of 352px while preserving at least 480px of main workspace. Pointer
dragging captures the pointer and honours cancellation. The separator supports Arrow
Left/Right, Home, End, and `0` for equivalent keyboard resize/reset behavior. The
resize affordance is unavailable for the collapsed rail and at viewport widths of
760px or less. The clamped expanded width is a presentation hint only.


7.2 APP-VIEW BUTTON

The app-view button is the first 32px control below the wordmark. Its closed state
contains the current view icon, current view label, and chevron.

Its one anchored menu contains these rows in this order:

1. World
2. Agent Manager
3. Inventory
4. Packages
5. Templates

The current view row uses a checkmark and selected tint. Selecting a row navigates to
that view and returns focus to the app-view button.

Every row is enabled. Selection closes the menu, updates the route, and restores
focus to the app-view button. World returns to its saved map route; every other view
opens its user-global domain catalog.


7.3 VIEW-OWNED CONTEXT

World
  The app-view button is followed by the persistent world picker.
  Its custom menu always ends with Create new world, including when no managed
  worlds exist or the selected projection cannot open.
  The action opens a compact custom dialog with one labelled name field and 32px
  Cancel/Create controls. Dialog actions are flat host controls, not Project Genie
  glass controls. Successful creation makes the issued bare world current and opens
  its exact route.

Agent Manager
  The app-view button is followed by the user-global agent catalog.

Inventory
  The app-view button is followed by the user-global folder and source tree.

Packages
  The app-view button is followed by the user-global package catalog.

Templates
  The app-view button is followed by the trusted template catalog.

Settings
  The footer button opens global settings navigation.

An operation that needs an exact world presents that field inside its compact action
surface. The selected value applies to that operation. A persistent current-world
change is exposed as the explicit Make current command in World.


7.4 ACTIVE-VIEW HEADER

The active view header is content-tight and sits close to the top edge. Titles,
descriptions, exact identifiers, and actions use the minimum height required by the
content. The lower edge resolves through spacing and the background surface.


7.5 DOMAIN CONTENT AND CONTEXTUAL ACTIONS

Each non-World view begins with its own domain browser:
Agent Manager has identity search and filters; Inventory has its folder/source tree;
Packages has Available and Installed lists; Templates has trusted definitions; and
Settings has fixed semantic sections. The selected entity defines the main detail
region. Search refines that domain’s data only.

Named contextual controls open compact action surfaces for the selected entity.
Those surfaces render only the required typed fields, consequence review, result, or
stream. Fixed choices and exact World selection use custom dropdowns; exact identity
fields use a custom editable autocomplete list. Credentials are write-only and clear
after every outcome. Consequential changes render Prepare and explicit Confirm or
Cancel. Agent controller output is a bounded memory-only transcript; report following
has Start/Stop; private results have Reveal/Close; and exports use a host-chosen
bounded filename with an explicit sensitivity warning.

Searchable Help is the full command reference. It documents scope and routes a user
to the relevant contextual control without replacing the current domain view. World
retains its map while World and object controls stay with the selected context.


8. WORLD VIEW


8.1 SIDEBAR

Header
  App-view button: World.
  Persistent world picker directly below it.
  The picker remains enabled in empty and projection-error states and always exposes
  Create new world as its final row.

Agents section
  The sidebar keeps one persistent My view row separate from the exact world's
  active-agent roster. The collapsed roster shows the first three agents in its
  stable per-world order.
  My view is one flat, single-line row containing only its icon and visible label;
  camera, path, coordinate, and zoom remain accessibility metadata.
  The first exact-world projection seeds the visible agent order. Explicit agent
  selection promotes that agent; follow refresh and My view restoration preserve
  the surviving order. Newly visible agents append and unavailable agents disappear.
  Explicit selection is the sole focus-changing interaction.
  The typed service supplies this ordered projection.
  A compact `All X agents` disclosure appears after the collapsed rows, where X is
  the live active count. It contains no separate trailing count badge and is absent
  when fewer than three agents are active. Expanding it replaces the collapsed roster
  with every active agent in the same row treatment and stable per-world order.
  Selecting an agent focuses it and starts scoped live follow through the ordinary World
  projection, refreshing approximately every 1.8 seconds without overlap.
  The same control collapses back to the three-row state.
  Manual panning pauses and exits follow until another explicit focus selection.
  A compact Add agent control opens a custom dialog tied to the viewed world. It
  requires an exact existing-agent selector, integer `x` and `y` coordinates, and an
  explicit `auto-adapt` option. It submits the add request and then reloads the
  authoritative world projection while preserving the prior focus and follow state.
  Agent focus and follow preserve the saved My-view container, camera, and zoom.
  Selecting My view restores that saved state while preserving roster order.

Objects section
  Inventory is the first row and opens the global Inventory view.
  Exact world-level pinned objects continue immediately after Inventory as one
  uninterrupted Objects list.
  Each pin resolves to one complete world-object ID in the viewed world.
  Selecting a pin focuses that object and opens its generic human interface.

Settings remains fixed at the bottom.


8.2 WORLD HEADER

Left
  Complete CLI structural path for the shown container or focused entity.

Right
  Notifications followed immediately by View.

The My view container, camera, zoom, and keyboard coordinate are a bounded
browser-local presentation preference keyed by exact world ID. Selecting My view or
reopening that world uses the preference as a route/camera hint, then reloads the
ordinary authoritative projection. An unavailable saved container resolves to the
world root.

Example structural path:

  (0,0)@world/(0,1)["Workshop"#7a2f4d8c1b6e4a0f9c3d2e5b8a7f1c04]

The path uses native system monospace. Complete 32-character lowercase IDs remain
selectable. Long paths reveal horizontally while preserving the CLI grammar.


8.3 NOTIFICATIONS

The 32px Notifications control contains:

- a bell icon;
- a non-color unread cue with accessible text; and
- one line previewing the latest stored human object report in the viewed world.

Overflow is clipped with an ellipsis. The preview uses the system body font.
Activation opens one anchored world-report popover. Report rows preserve complete
report, object, Inventory, package, deployment, and world lineage. The popover is
exact-world scoped. Its unread dot is a boolean derived from that world's stored
latest-seen marker, and its displayed `N` is computed from the returned bounded
recent-report slice.
Selecting a row opens the generic human-management detail for that report and object.


8.4 VIEW CONTROL

View is one 32px transparent-glass button and one anchored custom dropdown.
Its closed state contains the View label and chevron.
Activating the button opens zoom, recenter, visibility, display, and context-valid
inspection actions. Choosing an action runs it, closes the menu, and restores focus
to View.


8.5 WORLD FIELD

The world is a continuous warm canvas. Empty visible positions are quiet 3px dots.
Only empty visible positions show dots. Every visible coordinate has one 48px base
rounded-square hit target; adjacent targets touch without spacing. Occupied targets
replace the dot with the applicable state body. Zoom scales the target and every
internal visual proportionally. A placed object remains independently reachable
through the occupant menu when a colocated holding agent's held-object silhouette
owns the visible body.

An empty or ordinary nonholding target stays transparent. Hover, keyboard focus, and
a stationary press or hold use the same brightness-only target feedback.

Every visible position has a pointer and keyboard target. Hover and focus provide
only quiet state feedback in the World field. Context detail is rendered in the
command-information panel, while activated coordinates and summaries are rendered
in the anchored menu.
Click, Enter, or Space opens one anchored custom cell dropdown. The dropdown shows
the local coordinate and one short summary. Empty cells open the same dropdown and
identify themselves as Empty position.

Pointer and keyboard arbitration:

- Drag capture starts only after travel exceeds 6px from the pointer-down point.
- A single click on any cell opens the custom cell dropdown.
- When an object-bearing cell dropdown is open, the next primary click on an empty
  World cell closes the open dropdown and is consumed. The empty-cell dropdown
  becomes available on the next activation of that cell.
- A drag that begins with this dismissal still becomes ordinary World panning after
  crossing the 6px capture threshold.
- For a generic container, its menu waits 200ms; a valid double-click on the same
  object cancels the menu and opens the container directly.

Selecting an object opens the generic object human interface while the world remains
visible and visually recedes.
The same exact object in the same exact world restores its last selected inspector tab.


8.6 WORLD COMMAND CONSOLE

The World view has one floating command dock anchored to the bottom of the World
field. The dock is separate from the map content and keeps a small bottom occlusion
so the last visible World row remains usable. It contains two independent surfaces:

- a standalone 40px-high monospace input capsule; and
- a separate command-information panel above it.

The input capsule remains available while the panel is minimized. The panel is
resizable from a centered pill handle on its top edge (140px minimum, 520px maximum,
and a responsive viewport ceiling) and can be minimized without clearing its
in-memory output. The selected panel body scrolls internally; resizing never moves
scrolling into the World field.

The panel uses one horizontal tab row with exactly three tabs, in this order:

  Output  |  Agent  |  Object

The tabs expose compact `1`, `2`, and `3` key hints and those unmodified keys switch
to Output, Agent, and Object respectively while focus is outside an editable field,
dialog, inspector, or open menu. A shortcut expands a minimized information panel
without moving keyboard focus away from the World field.

Short vertical separators appear between the tabs and disappear where the selected
tab's surface meets its neighbor. Output is the selected initial tab and contains
bounded command entries with the display command, exit status, standard output,
standard error, and a truncation note. Output and error are rendered as inert
monospace text. Agent and Object are context tabs: they show the Agent/Object
occupants at the most recently hovered World cell, complete identity, path, state,
and bounded descriptive fields. Hover-selected context appears only in this panel;
the World field keeps only its quiet target feedback. Context is exact-world scoped
and is cleared when the selected World or shown container changes. Each context tab
starts with one compact `Press C to keep detail` control. Pressing `C`, or activating
that control, keeps the current or most recently pointed-to coordinate while the
pointer moves away. The control then reads `Press C to follow hover`, includes the
kept coordinate, and releases back to the current pointer/keyboard coordinate when
activated again. Kept context is page-memory presentation state only. A cell menu or
object inspector requires activation; hover and keyboard-cell focus update the
information panel.

Command entry is a bounded editor over the canonical human-command catalog. The
completion popover returns no more than eight complete catalog-derived suggestions,
including only fields and values available from the command definition's bounded
completion provider. It never invokes an object, provider, remote endpoint, or
subprocess. Syntax styling marks command path, options, quoted strings, numbers,
ordinary text, and malformed quoted input using bounded text spans; it accepts no
HTML or arbitrary markup. The input is limited to 4,096 characters and rejects
newlines and NULs.

Submission semantics are deliberately smaller than the terminal guided console.
Each entered line is queued in browser memory in FIFO order, with a bounded queue;
the browser does not retry a failed, rejected, or busy request. The in-process service
permits one command in flight and rejects a concurrent request as busy. The service
uses the same `CommandLineTokenizer`, `CommandParser`, and `CommandExecutor` as the
CLI, supplies the selected World, configuration, human output, and no-color globals,
and never invokes an operating-system shell or subprocess. The allowlist is
exhaustive and deny-by-default:

  help
  world show
  world template status
  world object list
  world object interface
  world object action list
  world object view list
  world object move

No other human command is implied by autocomplete or accepted by the endpoint. The
request carries the exact route-selected World ID, and the host validates that ID
against the catalog and world file before parsing or executing. A `world show`
selector must resolve to that same ID. A successful `world object move` reloads the
authoritative projection for the same selected World; a read-only result does not
reload or mutate the projection.

The transcript is bounded to 60 entries in page memory and each host-captured
standard-output/error channel is bounded to 65,536 bytes. The transcript is not
console history, local storage, a world document, a URL, or a tooltip. It is an inert
view of the current page session and is discarded with that page.


8.7 WORLD SYMBOL GRAMMAR

Every identity symbol is an SVG with a shared 256 by 256 viewBox, smooth curves or
rounded joins, and currentColor. The silhouettes share one true center and coherent
optical weight. Canonical sizing is judged with the complete family rendered at its
actual 24px World size, in monochrome and representative bright identity colors.
Apparent keyline, density, negative space, silhouette recognition, antialiasing, and
family rhythm are the primary criteria. True filled area supplies a measured
reference and guardrail. The resulting reference areas are
23,328 for the shield, 22,472 for the square, 17,858.743 for the triangle, 20,000 each
for the pentagon, hexagon, seal, and heart, and 19,570.72 for the star, in square SVG
units. Each silhouette is uniformly scaled about its measured filled-area centroid
and translated until that centroid is exactly (128,128). Outer bounds and filled
areas therefore vary deliberately with compactness and visual reach. Polygonal bodies
use mathematically regular geometry and localized corner softening calibrated to the
star's perceived outer-tip rounding at the actual 24px World size: the optically
smaller triangle is equilateral, the square has equal sides, and the pentagon and
hexagon use equally spaced vertices. The star retains its project-owned straight-sided
five-point construction and crisp inner transitions. Localized cubic caps soften the
five outer tips; the top cap is slightly broader so the upward tip reads as round as
the four diagonal tips at the 24px World size.
Its apparent mass is balanced with the rest of the family.
The scalloped seal repeats eight identical broad lobes at 45-degree
intervals. The shield uses square optical bounds, balanced shoulders, a shorter
centered point, and exact bilateral symmetry. The heart remains the intentional
organic exception while retaining exact bilateral balance.
Symbols use deterministic identity-derived shape and color across the world, lists,
pins, and interfaces.

Leading hash byte  Shape
-----------------  --------------------------
00...1F            Evenly proportioned rounded shield
20...3F            Rounded square
40...5F            Rounded equilateral triangle
60...7F            Rounded pentagon
80...9F            Rounded hexagon
A0...BF            Scalloped seal
C0...DF            Soft five-point star
E0...FF            Rounded heart

The first canonical identity byte selects the shape by integer division by 32.
The second byte modulo 12 selects the bright palette color. This mapping is explicit
for all valid identities and does not depend on world or object state.

State                    Treatment
-----------------------  ------------------------------------------------------
Empty position           Quiet 3px dot
Placed object            14px filled identity SVG marker
Agent with empty hand    Cell inner outline in the agent identity color; no glyph
Agent standing on object Placed-object body plus the agent-color inner outline
Agent holding object     Cell filled in the agent color plus one high-contrast held-
                        object silhouette; a colocated placed object stays reachable
Selected target          Separate outer ring preserving identity color
Blocked target           Shape plus explicit error indicator


9. AGENT MANAGER VIEW

Agent Manager is the complete user-global identity catalog.

Sidebar middle:

- search and catalog filters;
- all user-owned identities;
- assignment and active-presence metadata; and
- Create agent.

Agent detail:

- complete identity and genesis IDs;
- display name and creation metadata;
- maximum actions;
- AI-profile presence;
- exact assigned-world link;
- active presence and structural path when present;
- read-only lifecycle equipment, four holding-slot links, and primary-holding state;
  and
- unread or retryable notification state.

Actions project the existing identity, profile, placement, retry, and bounded
agent-shell commands through typed forms. The first placement of an unassigned identity includes
an explicit World field. An assigned identity displays its exact assignment and its
world-bound operations follow that assignment.

Agent Manager presents identity, profile, assignment, presence, and lifecycle-link
information. Equipment and holdings link to the exact object interface in the
assigned World, where Wallet, Messenger, and object-management interaction lives.


10. INVENTORY VIEW

Inventory is the user-global folder and source-object catalog.

Sidebar middle:

- permanent folder tree;
- source rows;
- global catalog filters; and
- source creation entry points.

Source detail:

- exact Inventory ID and revision;
- package ID, version, and content hash;
- folder and fork provenance;
- optional exact-world binding;
- readiness and missing requirements;
- declared configuration and credential-field presence;
- requested and granted capabilities;
- runtime-owned base management data; and
- declared fields, actions, views, and report contracts.

Copies, listeners, reports, and restock rules appear inside a World activity section
labelled with one locally chosen exact world. An exact-world action collects its
target in that section or in its compact action surface. A world-bound fork fixes
the eligible target to its binding.

Source, folder, configuration, credential, capability, action, view, fork,
deployment, copy, listener, report, and restock commands use the shared command
catalog and typed services.


11. PACKAGES VIEW

Packages is the user-global package catalog.

Sidebar middle:

- Available packages;
- Installed packages; and
- package filters.

Package detail includes package identity, semantic version, display name, summary,
runtime, requested capabilities, installation state, management field/action/view
counts, and retained usage. Retained versions additionally show their content hash
and installed timestamp.

Install, inspect, and remove actions preserve CLI validation, built-in package
selection or browser-safe HTTPS acquisition, retention semantics, and confirmation.


12. TEMPLATES VIEW

Templates is the trusted host template catalog.

Sidebar header:
  App-view button: Templates.

Sidebar middle:
  Templates section immediately below the app-view button.
  Selected row: default-khoros.

Main header:
  Template title.
  Template ID and version in system monospace.
  Trust classification and object count in system body text.
  Check status in world... action.
  Apply to world... primary action.
  Compact overflow action menu.

Template content:
  One Objects heading.
  One substantial rounded table surface.
  Columns for Object, Package, and Placement.
  Every root and package-owned object appears as its own row.
  Each declaration uses the neutral Phosphor Cube; it does not fabricate an object
  identity before instantiation.
  Explanatory template sentence below the table.


12.1 DEFAULT-KHOROS DEFINITION

Title
  default-khoros

Identifier
  default-khoros@1.0.0

Summary
  Trusted host template · 9 objects

Object                Package                           Placement
--------------------  --------------------------------  ----------------------------
Athena                org.mikrokhoros.athena            world (0,-2)
Objective Board       org.mikrokhoros.objective-board   world (1,-2)
Objective Index       org.mikrokhoros.objective-board   Objective Board (0,0)
Library               org.mikrokhoros.library           world (-2,2)
Library Catalog       org.mikrokhoros.library           Library (0,0)
Warehouse             org.mikrokhoros.warehouse         world (2,2)
Warehouse Directory   org.mikrokhoros.warehouse         Warehouse (1,0)
Marketplace           org.mikrokhoros.marketplace       world (0,2)
Merchant              org.mikrokhoros.marketplace       Marketplace (0,0)

Footer copy
  Applying this template creates the canonical Inventory sources and deploys the
  five facilities to the chosen world.


12.2 TEMPLATE ACTIONS

Check status in world...
  Opens a compact target surface with one required World field. The result renders
  exact component health, requested and actual coordinates, and complete lineage.

Apply to world...
  Opens a compact target surface containing World, Auto-adapt, Preview, and Apply.
  Preview invokes the canonical dry run. Apply submits its fingerprinted plan and
  canonical confirmation.

Overflow menu
  Contains Create world from template... and context-valid template help.

Create world from template...
  Collects the new world name and implemented template-creation options. The newly
  created world follows the CLI's current-world semantics.

The catalog shows trusted host definitions. Application status and repair results
are computed for the exact world selected by the action.


12.3 CANONICAL DESKTOP COMPOSITION

At 1536 by 1024:

- the expanded sidebar occupies approximately 240px;
- its soft edge separator is available for a 208px...352px desktop adjustment while
  preserving the main workspace minimum;
- the wordmark and sidebar toggle sit in one tight top row;
- the Templates app-view button sits directly below;
- its anchored menu aligns to the trigger and shows the five app views;
- the Templates section and selected default-khoros row begin the scrollable middle;
- Settings remains fixed near the bottom edge;
- template title and metadata align to the main content column;
- action capsules align at the upper right in the order shown above;
- the Objects table occupies the principal reading width; and
- the warm canvas remains visible around the table and through capsule controls.


13. SETTINGS

Settings is a fixed full-sidebar-width 32px capsule. It opens global sections for:

- product setup and status;
- diagnostics and recovery state;
- agent defaults;
- runtime limits;
- AI adapter availability;
- terminal presentation; and
- effective configuration, keys, path, reset, and validation.

Runtime, terminal, and host distinctions remain visible in section labels and help
text.


14. GENERIC OBJECT HUMAN INTERFACE

Every selected Inventory source and selected concrete world object uses one host-
owned interface shell. The selected entity supplies structured management metadata
and values.

The shell includes:

- deterministic identity symbol;
- display name and exact object type;
- complete Inventory or world-object ID;
- scope and revision;
- package, source, deployment, and template lineage;
- runtime-owned base details;
- declared configuration fields;
- declared actions;
- declared views; and
- declared report definitions and results.

Navigation is generated from available content:

- Overview is always present.
- Configuration appears for declared non-secret fields.
- Credentials appears for declared secret fields and exposes presence and usability.
- Capabilities appears for requested capabilities.
- Declared views render from their stable ID, summary, scope, and typed result.
- Declared actions render from their stable ID, summary, scope, typed inputs,
  mutation behavior, capabilities, and typed result.
- Copies, listening, reports, deployment, and restock appear when the runtime-owned
  base interface exposes them.

Supported field controls:

Type       Host control
---------  --------------------------------
text       Bounded text field
integer    Bounded integer field
decimal    Bounded decimal field
boolean    Switch
choice     Custom dropdown
url        Validated URL field
path       CLI-only contract row; browser supplies no host filesystem value
secret     Write-only secure field

If the selected contract contains any declared `path` field or `path` action input,
all of its actions and views remain visible with `CLI only` status and have no
browser execution control. A view sourced from configuration is also CLI only. The
path field itself has no browser set or unset control.

Inventory scope changes one source revision. World scope changes one exact concrete
instance revision. Both scopes render the action in each applicable selected
interface.

The interface opens as a substantial centered surface with a 32px outer radius.
Its navigation and content use spacing, alignment, local tonal shifts, and blur.
Buttons and selectable navigation rows remain 32px high.

Package content supplies bounded structured data. The host supplies reusable visual
primitives and encodes content as inert text and typed values.


15. DATA, ACTION, AND ERROR PRESENTATION

- Complete runtime identities remain selectable and authoritative.
- Display names remain human-readable labels.
- CLI structural paths and coordinates retain their exact grammar.
- Forms preserve required and optional fields, cardinality, default resolution,
  completion, validation, foreground input, and history policy from the shared
  command definition.
- Mutations preserve locking, transaction, confirmation, capability, credential,
  cancellation, and revalidation boundaries.
- Errors render stable code, bounded detail, and runtime-authored recovery guidance.
- Reports, package metadata, object metadata, remote results, and persisted content
  render as untrusted structured data.
- Secret fields expose collection, replacement, clearing, presence, and usability;
  values remain write-only.
- Live report following streams through the host and keeps the same exact-world
  scope as the command.
- Browser-local presentation preferences contain only bounded exact-world pin IDs,
  latest-seen report IDs, My-view state, and last inspector tabs. They are validated
  hints and never product state or authorization input.


16. RESPONSIVE AND PLATFORM BEHAVIOR

Wide desktop
  Expanded sidebar and full active-view content.

Compact desktop
  Reduced expanded sidebar width, condensed table columns, and horizontally
  scrollable exact identifiers.

Collapsed rail
  Icons and accessible names preserve app-view and Settings access. Opening a
  catalog uses one temporary anchored surface.

Keyboard
  Every function is reachable without a pointer. Focus order follows visible
  reading order. Menus, dialogs, tables, and generated forms use their native ARIA
  interaction models.

Coarse pointer
  Invisible hit regions may reach the platform target size while the visible
  routine control remains 32px high.

Motion
  State changes use short 100ms ease-in-out transitions. Reduced-motion preference
  removes spatial animation.

Platform host
  The implemented khoros web host is a native Swift executable on macOS, Linux, and
  Windows. The browser surface and typed transport preserve identical product
  semantics on each host.


17. ACCEPTANCE CRITERIA

- The shell has one app-view button and one custom dropdown menu.
- The menu contains World, Agent Manager, Inventory, Packages, and Templates.
- All five rows are enabled; Settings and searchable Help remain fixed global
  destinations.
- Help is the searchable full command reference. Contextual controls bind relevant
  commands to selected domain entities without replacing any view with a generated
  operation page.
- World presents the persistent world picker beneath the app-view button.
- The World picker remains actionable with zero worlds and always ends with Create
  new world. Its single-name creation dialog uses compact 32px non-Genie controls,
  a warm translucent light surface, and a light-only rim.
- Global catalogs begin directly beneath their selected app-view button.
- Settings remains fixed while the sidebar middle scrolls.
- Every routine interactive target retains the 32px height. Only designated
  standalone controls use the `--pill-radius` Project Genie capsule; repeating navigation,
  menu, report, and tab rows remain flat.
- Header and footer chrome stays tight to the viewport edges.
- The sidebar edge uses a warm blur and fade treatment.
- World shows a CLI structural path, Notifications, and View in one compact header.
- Notifications precedes View and shows a one-line ellipsized preview.
- World shows one floating bottom command dock with a separate monospace input
  capsule and a resizable/minimizable output/context panel.
- The panel has horizontal Output, Agent, and Object tabs with short vertical
  separators and visible `1`, `2`, and `3` shortcuts. Hover-selected Agent/Object
  context appears exclusively in its panel tab while the World field keeps quiet
  target feedback. Each context tab exposes the `C` keep/follow control, and kept
  context survives pointer exit until released or the exact World/container changes.
- Autocomplete is bounded to eight suggestions from the canonical command catalog,
  syntax styling is inert and bounded, and command source is capped at 4,096
  characters.
- World console submissions use the shared CLI tokenizer/parser/executor, an
  exhaustive deny-by-default allowlist, one in-flight execution, FIFO nonretrying
  scheduling, and a memory-only inert transcript.
- A successful allowlisted world-object move reloads the exact selected-World
  projection.
- Activating any occupied or empty cell opens its anchored custom dropdown with
  coordinates and a short summary. Hover and keyboard-cell focus update only the
  Agent/Object information panel; activation opens menus and inspectors.
- Container interactions use 200ms click/double-click arbitration and 6px drag
  capture threshold.
- A selected agent is refreshed approximately every 1.8 seconds while follow stays
  active; manual camera actions explicitly exit follow.
- The Objects section contains Inventory followed directly by exact pinned objects.
- The collapsed World roster shows the first three active agents in stable per-world
  order. `All X agents` appears at three or more agents, has no trailing count badge,
  and expands all active agents inline with the same row treatment.
- Agent selection focuses and follows that agent in the world only by explicit action.
- Templates renders default-khoros@1.0.0 with all nine object, package, and placement
  definitions.
- Template status and application collect their exact world within the action.
- Object interfaces derive from ObjectManagementInterface and the runtime-owned base
  interface.
- Agent Manager, Inventory, Packages, Templates, and Settings render their typed
  domain projections before any action is chosen. Agent equipment links open exact
  object interfaces; Wallet, Messenger, and object-management features remain with
  their selected objects.
- Google Sans Flex uses ROND 100 for interface text; body and monospace roles use
  native system fonts.
- Every non-World workspace header, state surface, and content surface resolves
  to the shared 1080px workspace frame and responsive inline gutter. Compact
  views preserve those exact horizontal edges and the 16/8/6 detail rhythm.
- Every non-circular rounded surface, including a capsule using `--pill-radius`,
  resolves through `--smooth-corner: superellipse(1.78)`. Only the three semantic
  circle/dot selectors use `round`; Identity Shape SVGs and masks
  retain their authored silhouettes.
- User-global and exact-world scope match docs/design.md and the shared command
  catalog.
- Complete paths, IDs, confirmations, security checks, and error semantics remain
  faithful to the CLI.
