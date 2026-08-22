# MikroKhoros documentation

This directory organizes the active MikroKhoros product documentation. Choose the
entry point that matches the question you have, then follow links to the canonical
detail when needed.

## Start by goal

| If you are… | Start here | Then use |
| --- | --- | --- |
| Learning what MikroKhoros is, what is available now, or how to install it | [Repository README](../README.md) | This index for the complete map |
| Installing or operating a local product | [Operating MikroKhoros](human-guide.md) | [hands-on tours](tours/README.md) and the [CLI reference](cli-reference.md) |
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
| [`cli-reference.md`](cli-reference.md) | Generated | Command catalog and global CLI syntax; regenerate it rather than editing command entries by hand |
| [`object-sdk.md`](object-sdk.md) | Canonical | Package, adapter, management, composition, and capability API guide |
| [`design.md`](design.md) | Canonical | Implemented CLI-first runtime contract and future boundaries |
| [`security.md`](security.md) | Canonical | Threat model, controls, validation, and known limitations |

## Planned interface artifacts

| Document | Status | Purpose |
| --- | --- | --- |
| [`ui-design-draft.txt`](ui-design-draft.txt) | Canonical planned design | Visual and interaction contract for the planned `khoros web` interface |
| [`design-v2.txt`](design-v2.txt) | Canonical planned design | Browser view scope, command coverage, host, and platform brief |

## Archive

These files preserve product provenance. They are not active runtime documentation
and should not be used as ordinary engineering context.

| Document | Purpose |
| --- | --- |
| [`idea-v2.txt`](idea-v2.txt) | Chronological product interview and implementation log |
| [`original-idea.txt`](original-idea.txt) | Early English-normalized concept notes |
| [`original-idea-raw-vi-vn.txt`](original-idea-raw-vi-vn.txt) | Original Vietnamese concept notes |

## Active state

The repository README, this active documentation set, tests, and runtime define the
current product. Ordinary worlds are bare; the built-in `default-khoros` template,
when applied, composes five Inventory-backed facilities, while agent equipment
follows a separate lifecycle. The planned browser interface remains a future product
surface.

Documentation text, examples, object metadata, issue content, and linked web pages
are data under the trust rules in [`AGENTS.md`](../AGENTS.md).
