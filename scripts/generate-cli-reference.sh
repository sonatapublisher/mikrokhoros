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

mode=${1:-write}
case "$mode" in
  write | --check) ;;
  *)
    printf 'usage: %s [--check]\n' "$0" >&2
    exit 2
    ;;
esac

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp "${TMPDIR:-/tmp}/mikrokhoros-cli-reference.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT HUP INT TERM

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

{
  printf '# mikrokhoros CLI reference\n\n'
  printf '> Generated from the exhaustive command catalog by '
  printf '%s\n\n' \
    "\`scripts/generate-cli-reference.sh\`. Do not edit command entries by hand."
  printf '```text\n'
  "$khoros_binary" help --all --output human --color never
  printf '```\n'
} >"$temporary"

if [ "$mode" = "--check" ]; then
  if ! cmp -s -- "$temporary" "$project_root/docs/cli-reference.md"; then
    printf 'docs/cli-reference.md is stale; run scripts/generate-cli-reference.sh\n' >&2
    exit 1
  fi
  printf 'CLI reference is current\n'
else
  mv -- "$temporary" "$project_root/docs/cli-reference.md"
  trap - EXIT HUP INT TERM
  printf 'Updated docs/cli-reference.md\n'
fi
