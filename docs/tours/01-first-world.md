# Tour 1: your first world

This tour creates the complete built-in environment, examines its structure, uses
the agent's Eye, and posts a collaborative objective. It needs no AI provider or API
key.

## 1. Initialize mikrokhoros

```bash
khoros init
```

Initialization completes without questions. It creates a world named
`default-khoros`, five canonical Inventory sources and facilities, and one agent named
`agent` at root `(0,0)`. The agent holds its Eye and has no AI profile.

Run the command again at any point to verify that the complete setup remains healthy:

```bash
khoros init
```

A healthy second run reports existing state without creating new identities.

## 2. Inspect product health

```bash
khoros status
khoros doctor
khoros world show
khoros --world default-khoros world template status default-khoros
khoros agent show agent
```

Template status identifies Athena, Objective Board, Library, Warehouse, and
Marketplace with their actual positions and Inventory lineage.

## 3. Look through the agent's Eye

```bash
khoros shell agent --action 'object (look)'
```

The result is the Eye's fixed 5-by-5 view centered on the agent. Compare that bounded
agent-visible surface with the human administrative view:

```bash
khoros world inspect agent
```

## 4. Use a built-in facility

```bash
khoros world object action run 'Objective Board' post \
  --input 'title=Explore the workshop' \
  --input 'body=Inspect the facilities and identify one useful object to build.'
khoros world object view show 'Objective Board' objectives
```

The objective is a collaborative object owned by the Objective Board.

## 5. Try the interactive console

```bash
khoros
```

At `khoros ›`, type complete commands directly:

```text
status
agent show agent
world show
:queue
```

Type part of a command and press Tab to use the adaptive palette. Enter only
`inventory deploy` to explore its guided form; press Ctrl-C to cancel the form. At an
empty idle prompt, Ctrl-C closes the console and restores the terminal.

Continue with [Tour 2](02-object-package.md).
