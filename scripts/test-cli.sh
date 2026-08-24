#!/bin/sh
# Copyright © 2026 mikrokhoros contributors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eu

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/mikrokhoros-cli.XXXXXX")
trap 'rm -R -- "$test_root"' EXIT HUP INT TERM

cd "$project_root"
if [ -n "${KHOROS_BIN:-}" ]; then
  khoros_binary=$KHOROS_BIN
elif [ -n "${SWIFT_BUILD_FLAGS:-}" ]; then
  # shellcheck disable=SC2086
  swift build $SWIFT_BUILD_FLAGS
  # shellcheck disable=SC2086
  build_directory=$(swift build $SWIFT_BUILD_FLAGS --show-bin-path)
  khoros_binary="$build_directory/khoros"
else
  swift build
  build_directory=$(swift build --show-bin-path)
  khoros_binary="$build_directory/khoros"
fi

yaml_value() {
  key=$1
  sed -n "s/^[[:space:]]*$key: //p" | head -n 1 | tr -d '"\r'
}

yaml_top_value() {
  key=$1
  sed -n "s/^$key: //p" | head -n 1 | tr -d '"\r'
}

MIKROKHOROS_HOME="$test_root" "$khoros_binary" </dev/null >"$test_root/help.out"
grep -Fq 'khoros [--config <file>]' "$test_root/help.out"
if MIKROKHOROS_HOME="$test_root" "$khoros_binary" console </dev/null \
  >"$test_root/console.out" 2>&1
then
  printf 'explicit console unexpectedly accepted redirected input\n' >&2
  exit 1
fi
grep -Fq 'console.tty_required' "$test_root/console.out"

MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  config get console.maximumQueueDepth >"$test_root/console-config.out"
grep -Fq 'value: 256' "$test_root/console-config.out"

create_output=$(MIKROKHOROS_HOME="$test_root" "$khoros_binary" agent create Sol)
agent_id=$(printf '%s\n' "$create_output" | yaml_value id)
test -n "$agent_id"
test ! -e "$test_root/workspace.json"
test ! -e "$test_root/worlds/index.json"

if MIKROKHOROS_HOME="$test_root" "$khoros_binary" world show \
  >"$test_root/missing-world.out" 2>&1
then
  printf 'world show unexpectedly created a missing world\n' >&2
  exit 1
fi
grep -Fq 'world.not_initialized' "$test_root/missing-world.out"
test ! -e "$test_root/workspace.json"
test ! -e "$test_root/worlds/index.json"

world_output=$(MIKROKHOROS_HOME="$test_root" "$khoros_binary" world create)
world_id=$(printf '%s\n' "$world_output" | yaml_value id)
test -n "$world_id"
printf '%s\n' "$world_output" | grep -Fq 'template: null'

MIKROKHOROS_HOME="$test_root" "$khoros_binary" agent add "$agent_id" \
  --at 0,0 --auto-adapt >"$test_root/add.out"
grep -Fq "world: $world_id" "$test_root/add.out"
MIKROKHOROS_HOME="$test_root" "$khoros_binary" agent show sol \
  >"$test_root/named-agent.out"
grep -Fq "id: $agent_id" "$test_root/named-agent.out"
if MIKROKHOROS_HOME="$test_root" "$khoros_binary" shell sol --action pickup \
  >"$test_root/failed-action.out" 2>&1
then
  printf 'failed in-world action unexpectedly returned success\n' >&2
  exit 1
fi
grep -Fq 'pickup.holding_occupied' "$test_root/failed-action.out"

MIKROKHOROS_HOME="$test_root" "$khoros_binary" --output json status \
  >"$test_root/status.json"
grep -Fq '"world"' "$test_root/status.json"
if LC_ALL=C grep -q "$(printf '\033')" "$test_root/status.json"; then
  printf 'machine output unexpectedly contained ANSI\n' >&2
  exit 1
fi
if MIKROKHOROS_HOME="$test_root" "$khoros_binary" inventory deply \
  >"$test_root/typo.out" 2>&1
then
  printf 'misspelled command unexpectedly succeeded\n' >&2
  exit 1
fi
grep -Fq 'inventory deploy' "$test_root/typo.out"

other_world=$(MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  world create --name Other)
other_world_id=$(printf '%s\n' "$other_world" | yaml_value id)
test -n "$other_world_id"
if MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  --world "$other_world_id" agent profile clear "$agent_id" \
  >"$test_root/wrong-world.out" 2>&1
then
  printf 'assigned profile mutation unexpectedly used another world\n' >&2
  exit 1
fi
grep -Fq 'agent.world_mismatch' "$test_root/wrong-world.out"
MIKROKHOROS_HOME="$test_root" "$khoros_binary" world use "$world_id" \
  >"$test_root/world-use.out"
grep -Fq 'current: true' "$test_root/world-use.out"
MIKROKHOROS_HOME="$test_root" "$khoros_binary" world list \
  >"$test_root/world-list.out"
grep -Fq "$world_id" "$test_root/world-list.out"
grep -Fq "$other_world_id" "$test_root/world-list.out"

MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  world rename "$other_world_id" Renamed >"$test_root/world-rename.out"
grep -Fq 'name: Renamed' "$test_root/world-rename.out"
MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  --world Renamed status >"$test_root/temporary-world.out"
grep -Fq "world: $other_world_id" "$test_root/temporary-world.out"
MIKROKHOROS_HOME="$test_root" "$khoros_binary" world list \
  >"$test_root/current-after-override.out"
grep -Fq "current_world: $world_id" "$test_root/current-after-override.out"

before_removed_option=$(find "$test_root" -type f -print | sort | xargs cksum)
if MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  --workspace "$test_root/removed.json" status >"$test_root/removed-option.out" 2>&1
then
  printf 'removed --workspace option unexpectedly succeeded\n' >&2
  exit 1
fi
grep -Fq 'cli.option_removed' "$test_root/removed-option.out"
test ! -e "$test_root/removed.json"
after_removed_option=$(find "$test_root" -type f ! -name 'removed-option.out' -print | sort | xargs cksum)
test "$before_removed_option" = "$after_removed_option"

MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  --world "$world_id" world template apply default-khoros --dry-run \
  >"$test_root/template-plan.out"
grep -Fq 'confirmation_required: true' "$test_root/template-plan.out"
MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  --world "$world_id" world template apply default-khoros --yes \
  >"$test_root/template-apply.out"
grep -Fq 'id: "default-khoros"' "$test_root/template-apply.out"
MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  --world "$world_id" world template status default-khoros \
  >"$test_root/template-status.out"
grep -Fq 'status: present' "$test_root/template-status.out"

MIKROKHOROS_HOME="$test_root" "$khoros_binary" doctor >"$test_root/doctor.out"
grep -Fq 'status: ok' "$test_root/doctor.out"
grep -Fq 'agents: 1' "$test_root/doctor.out"

MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  inventory package available >"$test_root/packages.out"
grep -Fq 'org.mikrokhoros.user-workspace' "$test_root/packages.out"

workspace_install=$(MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  inventory install builtin:user-workspace)
workspace_template=$(printf '%s\n' "$workspace_install" \
  | yaml_value inventory_object_id)
test -n "$workspace_template"

MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  inventory folder create projects >"$test_root/folder-parent.out"
MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  inventory folder create projects/world-a >"$test_root/folder.out"

fork_output=$(MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  --world "$world_id" inventory fork "$workspace_template" \
  --name World-A-Workspace --folder projects/world-a)
workspace_fork=$(printf '%s\n' "$fork_output" \
  | yaml_top_value id)
test -n "$workspace_fork"

mkdir "$test_root/host-folder"
printf 'hello\n' >"$test_root/host-folder/note.txt"
MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  inventory action run "$workspace_fork" mount-add \
  --input name=repository --input "path=$test_root/host-folder" \
  >"$test_root/mount.out"
grep -Fq 'mount_count: 1' "$test_root/mount.out"

MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  inventory capability grant "$workspace_fork" user-machine \
  >"$test_root/grant.out"

deployment_output=$(MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  inventory deploy "$workspace_fork" --auto-adapt)
workspace_object=$(printf '%s\n' "$deployment_output" \
  | yaml_value object_id)
test -n "$workspace_object"
printf '%s\n' "$deployment_output" | grep -Fq 'inventory_folder:'
printf '%s\n' "$deployment_output" | grep -Fq "world_binding: $world_id"

MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  world object show "$workspace_object" >"$test_root/world-object.out"
grep -Fq 'inventory_source:' "$test_root/world-object.out"

MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  world object view show "$workspace_object" readiness \
  >"$test_root/workspace-status.out"
grep -Fq 'status: ready' "$test_root/workspace-status.out"

MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  world object move "$workspace_object" --to world --at 40,40 \
  >"$test_root/world-object-move.out"
grep -Fq '(40,40)' "$test_root/world-object-move.out"

MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  inventory copies show "$workspace_object" >"$test_root/copy.out"
grep -Fq 'inventory_source:' "$test_root/copy.out"

init_root="$test_root/init-home"
mkdir "$init_root"
MIKROKHOROS_HOME="$init_root" "$khoros_binary" init </dev/null \
  >"$test_root/init.out"
grep -Fq 'default-khoros' "$test_root/init.out"
grep -Fq 'profile: null' "$test_root/init.out"
cp "$init_root/inventory.json" "$test_root/init-inventory.before"
cp "$init_root/agents.json" "$test_root/init-agents.before"
init_world_id=$(sed -n 's/^[[:space:]]*"currentWorldID"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$init_root/worlds/index.json")
test -n "$init_world_id"
cp "$init_root/worlds/index.json" "$test_root/init-index.before"
cp "$init_root/worlds/$init_world_id.json" "$test_root/init-world.before"
MIKROKHOROS_HOME="$init_root" "$khoros_binary" init </dev/null \
  >"$test_root/init-repeat.out"
cmp -s "$init_root/worlds/index.json" "$test_root/init-index.before"
cmp -s "$init_root/worlds/$init_world_id.json" "$test_root/init-world.before"
cmp -s "$init_root/inventory.json" "$test_root/init-inventory.before"
cmp -s "$init_root/agents.json" "$test_root/init-agents.before"

first_directory="$test_root/from-one"
second_directory="$test_root/from-two"
mkdir "$first_directory" "$second_directory"
(cd "$first_directory" && MIKROKHOROS_HOME="$test_root" "$khoros_binary" world list) \
  >"$test_root/from-one.out"
(cd "$second_directory" && MIKROKHOROS_HOME="$test_root" "$khoros_binary" world list) \
  >"$test_root/from-two.out"
cmp -s "$test_root/from-one.out" "$test_root/from-two.out"
test ! -e "$first_directory/.mikrokhoros"
test ! -e "$second_directory/.mikrokhoros"

third_world=$(MIKROKHOROS_HOME="$test_root" "$khoros_binary" world create --name Third)
third_world_id=$(printf '%s\n' "$third_world" | yaml_value id)
test -n "$third_world_id"
MIKROKHOROS_HOME="$test_root" "$khoros_binary" \
  world delete "$third_world_id" --yes >"$test_root/delete-current.out"
grep -Fq 'current_world: null' "$test_root/delete-current.out"
MIKROKHOROS_HOME="$test_root" "$khoros_binary" status \
  >"$test_root/status-without-current.out"
grep -Fq 'state: selection_required' "$test_root/status-without-current.out"
MIKROKHOROS_HOME="$test_root" "$khoros_binary" doctor \
  >"$test_root/doctor-without-current.out"
grep -Fq 'status: ok' "$test_root/doctor-without-current.out"

printf 'CLI lifecycle test passed\n'
