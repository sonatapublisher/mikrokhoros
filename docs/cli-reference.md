# mikrokhoros CLI reference

> Generated from the exhaustive command catalog by `scripts/generate-cli-reference.sh`. Do not edit command entries by hand.

```text
Show command help.
mikrokhoros — persistent multi-agent world runtime
Usage:
khoros [--config <file>] [--world <world-selector>]
[--output <auto|human|yaml|json>] [--color <auto|always|never>] <command>
khoros [global-options] console
Command groups:
help [<topic>]... [--all]
Show command help.
web [--port <port>] [--available-port]
Start mikrokhoros Web.
init
Create the complete default-khoros product setup without prompts.
status
Show selected product status.
doctor
Validate product state.
config show
Show effective configuration.
config path
Print the configuration path.
config keys
List configuration keys.
config get <key>
Read one configuration value.
config set <key> <value>
Set one configuration value.
config reset [<key>]
Reset one key or all configuration.
config validate
Validate configuration.
adapters
List available AI adapters.
agent create <name> [--max-actions <max-actions>]
Create a user-owned agent identity.
agent list
List user-owned agents.
agent show <agent-id>
Show one agent.
agent configure <agent-id> --max-actions <max-actions>
Configure one agent.
agent add <agent-id> [--at <at>] [--auto-adapt]
Add an agent to the selected world.
agent remove <agent-id>
Remove an agent from the selected world.
agent profile set <agent-id> --adapter <adapter> --model <model> [--name <name>] [--endpoint <endpoint>] [--credential-env <credential-env>] [--temperature <temperature>] [--max-output-tokens <max-output-tokens>] [--reasoning <reasoning>]
Attach or replace an AI profile.
agent profile clear <agent-id>
Detach an AI profile.
agent retry <agent-id>
Retry an unread agent notification.
shell <agent-id> [--action <action>]...
Drive one agent through its in-world action shell.
library fetch <https-url> [--title <title>]
Fetch an HTTPS document into the world library.
library list
List library documents.
inventory install <path-or-url>
Install an object package.
inventory package available
List first-party object packages available to install.
inventory package list
List packages.
inventory package show <package-id> [--version <version>]
Show one package.
inventory package remove <package-id> [--version <version>] [--yes]
Remove a package from the visible catalog.
inventory create <package-id> [--version <version>] [--name <name>]
Create an Inventory object.
inventory folder create <path>
Create one Inventory folder.
inventory folder list [<folder>] [--recursive]
List an Inventory folder.
inventory folder show <folder>
Show one Inventory folder.
inventory folder rename <folder> <name>
Rename one Inventory folder.
inventory folder move <folder> --to <to>
Move an Inventory folder subtree.
inventory folder delete <folder> [--yes]
Delete one empty Inventory folder.
inventory move <inventory-id> --folder <folder>
Move an Inventory source into a folder.
inventory fork <inventory-id> [--name <name>] [--folder <folder>]
Fork an Inventory source for the selected world.
inventory list [--package <package>] [--folder <folder>] [--recursive] [--all]
List Inventory objects.
inventory show <inventory-id>
Show an Inventory object.
inventory interface <inventory-id>
Show an object's management interface.
inventory configure <inventory-id> [--set <set>]... [--unset <unset>]...
Configure an Inventory object.
inventory delete <inventory-id> [--yes]
Delete one Inventory object.
inventory secret set <inventory-id> <field> [--stdin] [--from-env <from-env>]
Set an Inventory credential.
inventory secret clear <inventory-id> <field>
Clear an Inventory credential reference.
inventory capability list <inventory-id>
List requested and granted capabilities.
inventory capability grant <inventory-id> [<capability>]...
Grant capabilities.
inventory capability revoke <inventory-id> [<capability>]...
Revoke capabilities.
inventory action list <inventory-id>
List human management actions.
inventory action run <inventory-id> <action> [--input <input>]...
Run a human management action.
inventory view list <inventory-id>
List human management views.
inventory view show <inventory-id> <view> [--object <object>]
Show a human management view.
inventory deploy <inventory-id> [--to <to>] [--at <at>] [--auto-adapt]
Deploy a concrete object copy.
inventory copies list <inventory-id> [--deployment <deployment>] [--listened]
List concrete descendants.
inventory copies show <world-object-id>
Show one concrete world object.
inventory copies delete <inventory-id> [--object <object>]... [--deployment <deployment>]... [--all] [--recursive] [--dry-run] [--yes]
Delete selected concrete copies.
inventory listen enable <world-object-id>
Enable a human object listener.
inventory listen disable <world-object-id>
Disable a human object listener.
inventory listen list [--inventory <inventory>]
List active human listeners.
inventory reports list [--inventory <inventory>] [--object <object>] [--type <type>] [--limit <limit>]
List stored object reports.
inventory reports show <report-id>
Show one object report.
inventory reports follow [--inventory <inventory>] [--object <object>] [--type <type>] [--limit <limit>]
Follow new object reports.
inventory restock create <inventory-id> --merchant <merchant> --price <price> [--at <at>] [--auto-adapt]
Create an Inventory-backed restock rule.
inventory restock list [--inventory <inventory>] [--merchant <merchant>]
List restock rules.
inventory restock show <rule-id>
Show one restock rule.
inventory restock set <rule-id> [--price <price>] [--enabled <enabled>]
Update a restock rule.
inventory restock run <rule-id> [--count <count>]
Run a restock rule manually.
inventory restock delete <rule-id> [--yes]
Delete a restock rule.
world list [--all]
List worlds in this mikrokhoros application.
world use <world>
Select the current world.
world create [--name <name>] [--template <template>] [--yes]
Create an independent bare or templated world.
world rename <world> <name>
Rename one world without changing its identity.
world delete <world> [--yes]
Delete one concrete world.
world template list
List built-in world templates.
world template show <template-id>
Show one built-in world template.
world template status [<template-id>]
Show exact template component health in the selected world.
world template apply <template-id> [--auto-adapt] [--dry-run] [--yes]
Apply or repair a built-in template in the selected world.
world show [<world>]
Show the selected or supplied world.
world inspect [<agent-or-object-id>]
Inspect complete human-only world state.
world export
Export the world journal.
world object list [--container <container>] [--type <type>] [--package <package>] [--inventory <inventory>] [--deployment <deployment>]
List exact concrete objects in the selected world.
world object show <world-object-id>
Show one exact world object.
world object interface <world-object-id>
Show exact-instance management controls.
world object action list <world-object-id>
List actions for one exact world object.
world object action run <world-object-id> <action> [--input <input>]...
Run a human action on one exact world object.
world object view list <world-object-id>
List views for one exact world object.
world object view show <world-object-id> <view>
Show a view for one exact world object.
world object move <world-object-id> --to <to> [--at <at>] [--auto-adapt]
Move one ordinary concrete world object.
Global options:
--config <file>      Select configuration.
--world <selector>   Select a world by ID, unique prefix, or unique name.
--output <mode>      auto, human, yaml, or json.
--color <mode>       auto, always, or never.
Per-user files live under ~/.mikrokhoros.
```
