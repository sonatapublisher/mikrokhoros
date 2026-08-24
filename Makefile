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

SWIFT ?= swift
SWIFT_BUILD_FLAGS ?=
WARNINGS_AS_ERRORS ?= true
# `check-docs` generates this exact tracked textual artifact before
# `check-public` runs in `preflight`. Keep it in the default gate so public
# output validation always covers generated documentation, not only source.
PUBLIC_BUILD_OUTPUTS ?= docs/cli-reference.md
SWIFT_WARNING_ENV = MIKROKHOROS_WARNINGS_AS_ERRORS=$(if $(filter false,$(WARNINGS_AS_ERRORS)),0,1)
SWIFT_FLAGS = $(SWIFT_BUILD_FLAGS)
PUBLIC_BUILD_ARGS = $(foreach output,$(PUBLIC_BUILD_OUTPUTS),--build-output $(output))

.DEFAULT_GOAL := build

.PHONY: build release test test-cli test-terminal docs check-docs format lint update-licenses check-licenses check-public check-public-release test-public test-secrets preflight check install uninstall pre-commit

build:
	$(SWIFT_WARNING_ENV) $(SWIFT) build $(SWIFT_FLAGS)

release:
	$(SWIFT_WARNING_ENV) $(SWIFT) build -c release $(SWIFT_FLAGS)

test:
	$(SWIFT_WARNING_ENV) $(SWIFT) test $(SWIFT_FLAGS)

test-cli:
	$(SWIFT_WARNING_ENV) SWIFT_BUILD_FLAGS="$(SWIFT_FLAGS)" ./scripts/test-cli.sh

test-terminal:
	$(SWIFT_WARNING_ENV) SWIFT_BUILD_FLAGS="$(SWIFT_FLAGS)" ./scripts/test-terminal.sh

docs:
	$(SWIFT_WARNING_ENV) SWIFT_BUILD_FLAGS="$(SWIFT_FLAGS)" ./scripts/generate-cli-reference.sh

check-docs:
	$(SWIFT_WARNING_ENV) SWIFT_BUILD_FLAGS="$(SWIFT_FLAGS)" ./scripts/generate-cli-reference.sh --check

format: update-licenses
	$(SWIFT) format format --in-place --recursive --parallel Sources Tests Package.swift

lint:
	$(SWIFT) format lint --strict --recursive --parallel Sources Tests Package.swift

update-licenses:
	./scripts/update-license-headers.sh

check-licenses:
	./scripts/check-license-headers.sh

check-public:
	python3 ./scripts/check-public-surface.py $(PUBLIC_BUILD_ARGS)

check-public-release:
	python3 ./scripts/check-public-surface.py --require-launch-topology $(PUBLIC_BUILD_ARGS)

test-public:
	python3 ./scripts/test-public-surface.py

test-secrets:
	python3 ./scripts/test-secret-allowlist.py

preflight: lint check-licenses check-docs check-public test-public test-secrets

check: preflight test test-cli test-terminal release

install:
	SWIFT_BUILD_FLAGS="$(SWIFT_FLAGS)" ./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

pre-commit:
	./scripts/install-pre-commit.sh
