# mikrokhoros Object SDK

The Object SDK is the developer-facing Swift API and package contract used to build
objects for mikrokhoros. It is not an object in Inventory or in a world. An object
package is the installable artifact; an Inventory source is the human-owned template;
a deployment creates an independent concrete world instance.

## Package contract

`ObjectPackageManifest` is the single versioned package format. A manifest declares:

- stable package ID, semantic version, display metadata, and runtime;
- installation behavior and whether later Inventory sources are allowed;
- the root object definition and any package-owned child graph;
- requested capabilities;
- public functions and their invocation audiences;
- typed human fields, actions, views, and report contracts.

The installed CLI accepts declarative packages and its exact registered first-party
native packages. A Swift host can register another trusted native adapter with
`ObjectRuntimeRegistry`. Package metadata cannot register an adapter or activate
native code. JavaScript packages remain unavailable without a sandboxed adapter.

Declarative packages run in the closed interpreter. They can work with bounded JSON
state and declared reports; they cannot import code, launch processes, or directly
access the network or host filesystem.

## World-template composition

A world template is a host-owned composition of object packages. It is not an object
package, Inventory source, runtime adapter, or alternative SDK. The public
`WorldTemplateDefinition` contract declares ordered package components, canonical
source names, requested root coordinates, package-owned child expectations, and
pickup-lock policy. The installed CLI registers only its trusted `default-khoros`
definition; loading user-authored template files is not part of this runtime.

Template installation and deployment continue through the ordinary package cache,
Inventory, runtime-adapter, deployment-snapshot, replay, management, listener, and
report paths. The template adds immutable provenance linking a canonical Inventory
source and concrete deployment to one component role. Object authors cannot acquire
that role through manifest text, display names, object type, or coordinates.

The five built-in facility packages demonstrate this composition. Objective Board,
Library, Warehouse, and Marketplace each own their declared service child inside one
deployment graph; those children are not separate Inventory sources. The same model
lets an embedding host define another trusted composition without changing the Object
SDK or granting package code new authority.

## Runtime adapters

`ObjectRuntimeAdapter` owns runtime-specific validation, default management state,
Inventory actions and views, deployment-state capture, concrete instantiation,
instance actions and views, bounded state restoration, and an explicit declaration
of its possible external-effect classes. Adapter selection is an
exact package-ID registration performed by the embedding host.

Human instance actions receive `WorldObjectManagementContext`. It identifies the
exact world, object, lineage, revision, and captured grants and offers a controlled
state-mutation receipt. It does not expose the complete runtime harness through the
public SDK.

Every deployment snapshot records its runtime-adapter ID and version. Replay selects
the same adapter and restores the recorded concrete IDs and adapter state without
consulting the current Inventory source.

## Function audiences and relative calls

Every public function declares one audience:

| Audience | Direct agent call | Object-to-object call |
| --- | --- | --- |
| `agent` | yes | no |
| `object` | no | yes |
| `both` | yes | yes |

Existing schema-1 declarative functions decode as `agent`. A direct model action
cannot invoke an object-only function.

Trusted host object implementations register constrained handlers with
`registerAgentFunction`, `registerObjectFunction`, or `registerSharedFunction`.
Each handler receives `AgentObjectContext`; the unrestricted runtime context remains
internal to mikrokhoros.

`ObjectWorldReadService.inspect(at:)` and
`ObjectWorldWriteService.invoke(at:function:arguments:)` resolve an exact coordinate
relative to the calling object. A placed object uses its own coordinate. A held tool
uses its carrier’s current coordinate. Source and target must share the same
immediate container space; resolution never searches for another compatible object.

Nested invocation identity contains a root invocation ID, current invocation ID,
target object, optional calling object, original agent, world, depth, and target
lineage. mikrokhoros creates these fields. A nested object cannot replace the
original agent identity. The configured invocation-depth limit prevents recursive
cycles.

Source and target durability are charged only after their respective functions
complete successfully. A target failure propagates through the initiating action and
the ordinary action batch stops at that point.

## Capability-mediated services

`ObjectCapabilityBroker` checks the concrete instance’s captured grant every time a
protected service performs work. Public contexts can carry bounded state, world
read/write/system services, network access, folder-bound host access, and a scoped
report emitter. Inventory grant changes affect future copies only.

`ObjectUserFolderService` is the filesystem boundary. Its operations accept an
opaque binding ID and a relative path:

```swift
service.list(bindingID: bindingID, relativePath: relativePath)
service.read(bindingID: bindingID, relativePath: relativePath, range: range)
service.write(bindingID: bindingID, relativePath: relativePath, data: data)
service.append(bindingID: bindingID, relativePath: relativePath, data: data)
service.clear(bindingID: bindingID, relativePath: relativePath)
```

The service verifies the captured `user-machine` grant, binding ownership, canonical
root containment, non-symlink traversal, current entry type, mount access mode, and
configured byte limits. Object code receives no arbitrary absolute-path operation.

## First-party composition example

The built-in paper exposes `read` to agents and `write`, `append`, and `clear` to
object callers. Pencil exposes agent-facing functions that invoke one of those
object-only functions on an exact neighboring cell. Printer exposes `print`, which
invokes `write` at the printer’s configured output delta.

Neither tool checks for a paper or file type. Compatibility comes from the target’s
function interface. This allows the same pencil and printer code to work with paper,
projected UTF-8 files, or another package that deliberately implements the same
object-callable functions.

## Human management scopes

Management actions and views declare `inventory`, `world`, or `both` scope.
Inventory mutations affect one source and increment its source revision. World
mutations affect one exact concrete instance and increment its instance revision.
Neither operation synchronizes state into siblings or future/earlier deployments.

The CLI and guided console read the same manifest contract. Guided action forms
resolve the selected object and action, then ask for the declared typed inputs. The
resulting tokens enter the same `CommandParser` and `CommandExecutor` used by
one-shot commands.

## Persistence and external effects

Adapter-backed state is stored in immutable deployment snapshots and later
world-object state events. Successful object-to-object calls and external operations
record bounded receipts. During
world replay, recorded effects consume their receipts without performing host
I/O. The first relevant live interaction then reconciles projected topology against
the current host resource.

Object authors must treat filenames, file contents, object results, report payloads,
and remote responses as untrusted data. These values may be returned in bounded
structured output, but they never become system instructions or runtime identity.

See the [canonical runtime design](design.md), [security model](security.md), and
[declarative lamp package](../examples/lamp.package.json).
