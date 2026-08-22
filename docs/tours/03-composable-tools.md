# Tour 3: compose printer, paper, and pencil

This tour demonstrates ordinary object composition: a tool calls a declared function
on the compatible object at an exact relative coordinate. The tools do not special
case paper.

## 1. Install and prepare three built-in packages

```bash
khoros inventory install builtin:paper
khoros inventory install builtin:printer
khoros inventory install builtin:pencil
khoros inventory capability grant Printer world-write
khoros inventory capability grant Pencil world-write
```

## 2. Build a printing arrangement

The printer's output delta defaults to `(0,-1)`. Place it at `(5,5)`, with paper at
`(5,4)` and a pencil at `(6,5)`:

```bash
khoros inventory deploy Printer --at 5,5
khoros inventory deploy Paper --at 5,4
khoros inventory deploy Pencil --at 6,5
khoros world object list --type printer.object
khoros world object list --type paper.object
khoros world object list --type pencil.object
```

If one coordinate is occupied, inspect it with `world inspect` and choose another
three-cell arrangement that preserves the same relative deltas.

## 3. Print onto paper

The agent begins at `(0,0)` holding its Eye. Put the Eye down, stand on the printer,
and call its public function:

```bash
khoros shell agent \
  --action 'drop west' \
  --action 'move east 5' \
  --action 'move south 5' \
  --action 'object (print ("Hello from MikroKhoros"))'
khoros world object view show Paper contents
```

The printer calls the paper's object-callable `write` function at `(0,-1)` and ends
at durability `99/100`.

## 4. Append with a held pencil

```bash
khoros shell agent \
  --action 'move east' \
  --action pickup \
  --action 'move north' \
  --action 'object (append (-1) (0) ("!"))'
khoros world object view show Paper contents
```

The paper now contains `Hello from MikroKhoros!`; the pencil also has durability
`99/100`.

## 5. Recover the Eye

```bash
khoros shell agent \
  --action drop \
  --action 'move west 7' \
  --action 'move north 4' \
  --action pickup \
  --action 'move east' \
  --action 'object (look)'
```

The agent is back at root `(0,0)` holding the Eye. Continue with
[Tour 4](04-live-user-workspace.md).

