# mikrokhoros documentation

This directory organizes the active mikrokhoros product documentation. Choose the
entry point that matches the question you have, then follow links to the canonical
detail when needed.

## Start by goal

| If you are… | Start here | Then use |
| --- | --- | --- |
| Learning what mikrokhoros is, what is available now, or how to install it | [Repository README](../README.md) | This index for the complete map |
| Installing or operating a local product | [Operating mikrokhoros](human-guide.md) | [hands-on tours](tours/README.md) and the [CLI reference](cli-reference.md) |
| Looking for a reproducible exercise | [Hands-on tours](tours/README.md) | The operator guide for context and recovery |
| Looking up exact command syntax or options | [CLI reference](cli-reference.md) | The operator guide for workflow and safety context |
| Creating packages or runtime adapters | [Object SDK guide](object-sdk.md) | [canonical design](design.md) and the declarative [lamp example](../examples/lamp.package.json) |
| Reviewing runtime behavior or security | [Runtime design](design.md) | [security architecture](security.md) |
| Changing the repository | [Contributing guide](../CONTRIBUTING.md) | The design, security, and applicable source contracts |

## Active documentation

| Document | Status | Purpose |
| --- | --- | --- |
| [`human-guide.md`](human-guide.md) | User guide | Human operating model, installation, administration, and routes to focused material |
| [`tours/`](tours/README.md) | Hands-on | Isolated progressive exercises for worlds, packages, tools, and live folders |
| [`cli-reference.md`](cli-reference.md) | Reference | Complete command catalog and global CLI syntax |
| [`object-sdk.md`](object-sdk.md) | Canonical | Package, adapter, management, composition, and capability API guide |
| [`design.md`](design.md) | Canonical | Implemented runtime, CLI, mikrokhoros Web, and future boundaries |
| [`security.md`](security.md) | Canonical | Threat model, controls, validation, and known limitations |
| [`public-facts.json`](public-facts.json) | Machine-readable contract | Canonical public name, slug, executable, category, primary statement, description, license, lifecycle, URLs, and launch-source identity |
| [`shipped-resource-inventory.json`](shipped-resource-inventory.json) | Asset inventory | Hashes and roles for every shipped font, SVG icon/identity shape, and bundled license |

## Browser interface artifacts

| Document | Status | Purpose |
| --- | --- | --- |
| [`ui-design.md`](ui-design.md) | Canonical design | Visual and interaction contract for World and all mikrokhoros Web views |
| [`design-v2.txt`](design-v2.txt) | Canonical product brief | Browser domain scope, contextual command placement, host, and platform contract |
| [`web-ux-decisions.md`](web-ux-decisions.md) | Canonical rationale | Source-backed associations and interaction decisions for mikrokhoros Web |
| [`web-design-qa.md`](web-design-qa.md) | Verification record | Current browser design, interaction, security-boundary, and automated-check results |

## Active state

The repository README, this active documentation set, tests, and runtime define the
current product. Ordinary worlds are bare; the built-in `default-khoros` template,
when applied, composes five Inventory-backed facilities, while agent equipment
follows a separate lifecycle. `khoros web` provides the five primary destinations—
World, Agent Manager, Inventory, Packages, and Templates—from one custom web
menu; Settings is fixed in the sidebar footer, and searchable Help is the complete
command reference. Its pages use domain-native projections and contextual action
sheets; only a selected exact Inventory source or exact world object is rendered
through its declared `ObjectManagementInterface`. The World's bounded command dock
remains a focused exact-world surface. The CLI remains an equal interface over the
same native services. The [human guide](human-guide.md) describes mikrokhoros Web
workflow; [runtime design](design.md) defines the typed projection, exact-object,
template-placement, and loopback contracts; [security architecture](security.md)
defines the safe browser execution boundary.

The documentation index covers public product behavior, operating guidance, and
contribution material. The repository contributor guide records the conventions
for maintaining those sources.
