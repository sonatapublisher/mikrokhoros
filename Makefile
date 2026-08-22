# Copyright © 2026 MikroKhoros contributors.
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
SWIFT_WARNING_FLAGS = $(if $(filter false,$(WARNINGS_AS_ERRORS)),,-Xswiftc -warnings-as-errors)
SWIFT_FLAGS = $(SWIFT_BUILD_FLAGS) $(SWIFT_WARNING_FLAGS)

.DEFAULT_GOAL := build

.PHONY: build release test test-cli test-terminal docs check-docs format lint update-licenses check-licenses preflight check install uninstall pre-commit

build:
	$(SWIFT) build $(SWIFT_FLAGS)

release:
	$(SWIFT) build -c release $(SWIFT_FLAGS)

test:
	$(SWIFT) test $(SWIFT_FLAGS)

test-cli:
	SWIFT_BUILD_FLAGS="$(SWIFT_FLAGS)" ./scripts/test-cli.sh

test-terminal:
	SWIFT_BUILD_FLAGS="$(SWIFT_FLAGS)" ./scripts/test-terminal.sh

docs:
	SWIFT_BUILD_FLAGS="$(SWIFT_FLAGS)" ./scripts/generate-cli-reference.sh

check-docs:
	SWIFT_BUILD_FLAGS="$(SWIFT_FLAGS)" ./scripts/generate-cli-reference.sh --check

format: update-licenses
	$(SWIFT) format format --in-place --recursive --parallel Sources Tests Package.swift

lint:
	$(SWIFT) format lint --strict --recursive --parallel Sources Tests Package.swift

update-licenses:
	./scripts/update-license-headers.sh

check-licenses:
	./scripts/check-license-headers.sh

preflight: lint check-licenses check-docs

check: preflight test test-cli test-terminal release

install:
	SWIFT_BUILD_FLAGS="$(SWIFT_FLAGS)" ./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

pre-commit:
	./scripts/install-pre-commit.sh
