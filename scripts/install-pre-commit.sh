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

project_root=$(git rev-parse --show-toplevel)
hooks_directory=$(git rev-parse --git-path hooks)
runner="$hooks_directory/mikrokhoros-pre-commit"
hook="$hooks_directory/pre-commit"
# The hook must receive this command substitution literally for execution at commit time.
# shellcheck disable=SC2016
invocation='"$(git rev-parse --git-path hooks)/mikrokhoros-pre-commit"'

mkdir -p "$hooks_directory"
cp "$project_root/scripts/pre-commit.sh" "$runner"
chmod +x "$runner"
if [ ! -f "$hook" ]; then
  printf '#!/bin/sh\n\n' >"$hook"
fi
if ! grep -Fq 'mikrokhoros-pre-commit' "$hook"; then
  printf '\n%s\n' "$invocation" >>"$hook"
fi
chmod +x "$hook"
printf 'installed mikrokhoros checks in %s\n' "$hook"
