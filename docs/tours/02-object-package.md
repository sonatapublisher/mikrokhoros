# Tour 2: install and deploy an object package

This tour follows the Object SDK lifecycle using the repository's declarative lamp:
package installation, Inventory configuration, a write-only credential, capability
grant, management action, deployment, and source/copy independence.

Set `MIKROKHOROS_SOURCE` to a mikrokhoros checkout containing `examples/`:

```bash
export MIKROKHOROS_SOURCE="$(git -C . rev-parse --show-toplevel)"
test -f "$MIKROKHOROS_SOURCE/examples/lamp.package.json"
```

## 1. Install and inspect the package

```bash
khoros inventory install "$MIKROKHOROS_SOURCE/examples/lamp.package.json"
khoros inventory package show org.mikrokhoros.example.lamp
khoros inventory show 'Connected Lamp'
khoros inventory interface 'Connected Lamp'
```

The package is the versioned implementation. `Connected Lamp` is the configurable
Inventory source. No lamp exists in the world yet.

## 2. Configure the source

```bash
khoros inventory configure 'Connected Lamp' --set room=workshop
export TOUR_LAMP_KEY='tour-only-value'
khoros inventory secret set 'Connected Lamp' api_key --from-env TOUR_LAMP_KEY
unset TOUR_LAMP_KEY
khoros inventory capability grant 'Connected Lamp' network
khoros inventory show 'Connected Lamp'
```

The secret value is write-only and remains absent from output and persisted public
documents. The source should now be ready.

## 3. Use its human management interface

```bash
khoros inventory action list 'Connected Lamp'
khoros inventory action run 'Connected Lamp' record_check --input amount=1
khoros inventory view show 'Connected Lamp' dashboard
```

The mutating action changes only the Inventory source and increments its revision.

## 4. Deploy an independent concrete lamp

```bash
khoros inventory deploy 'Connected Lamp' --at 4,0
khoros inventory copies list 'Connected Lamp'
khoros world object show 'Connected Lamp'
khoros world object interface 'Connected Lamp'
```

Change the source and inspect the existing copy:

```bash
khoros inventory configure 'Connected Lamp' --set room=studio
khoros inventory copies show 'Connected Lamp'
```

The deployed copy retains the source revision captured at deployment. Create another
copy from the updated source and compare their listed revisions:

```bash
khoros inventory deploy 'Connected Lamp' --at 4,1
khoros inventory copies list 'Connected Lamp'
```

There are now two world objects with the same name. A direct name selector is
ambiguous by design; use either unique short ID shown by `copies list` for exact
inspection.

Continue with [Tour 3](03-composable-tools.md).

