# Object bundle examples

This directory contains source-controlled examples for the closed declarative object
format. [`lamp.bundle.json`](lamp.bundle.json) demonstrates bounded public metadata,
private JSON state, durability, and `get`/`toggle` actions.

Load examples only through `BundleRegistry`. A bundle is untrusted data: unknown
fields and action kinds fail closed, and no bundle may import code, run a process,
access the filesystem, or use the network. A future executable package manifest is
not permission to execute its entry point.

Object authors should also read the Object SDK boundary in
[`docs/design.md`](../docs/design.md) and the threat model in
[`docs/security.md`](../docs/security.md).
