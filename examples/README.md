# Object package examples

[`lamp.package.json`](lamp.package.json) is a complete declarative object package.
It demonstrates:

- package-selected default Inventory creation and permission for additional sources;
- typed human configuration, a write-only secret, and a requested capability;
- a typed mutating management action and a world-aware dashboard view;
- agent-facing status, switch, and report functions;
- bounded durability and report contracts; and
- state copied independently into each world deployment.

Install it from the repository root:

```bash
khoros inventory install examples/lamp.package.json
```

The installed CLI decodes package files as untrusted structured data. Unknown fields,
unsupported runtimes, undeclared capabilities, invalid contracts, and oversized
content fail before an Inventory object is created. Declarative packages cannot
import code, launch processes, read files, or contact the network directly.

Object authors should also read the package and Object SDK contract in
[`docs/object-sdk.md`](../docs/object-sdk.md), the canonical runtime design in
[`docs/design.md`](../docs/design.md), and the trust model in
[`docs/security.md`](../docs/security.md).

The installed CLI also ships exact native package manifests. The composable tool
set is available through `builtin:user-workspace`, `builtin:pencil`,
`builtin:printer`, and `builtin:paper`. The `default-khoros` facilities use
`builtin:athena`, `builtin:objective-board`, `builtin:library`,
`builtin:warehouse`, and `builtin:marketplace`. List the complete catalog with
`khoros inventory package available`.

These packages demonstrate trusted runtime-adapter registration, package-owned
child graphs, world-scoped management, opaque host-folder bindings, function
audiences, relative object calls, and world-template composition through ordinary
Inventory-backed deployments.
