SHELL := /bin/bash

# Ambxst Go backend binary (repo root, gitignored)
BINARY := ambxst
BACKEND_DIR := backend

GO ?= go
GOFLAGS ?=
QMLLINT ?= $(shell command -v qmllint 2>/dev/null || command -v /usr/lib/qt6/bin/qmllint 2>/dev/null)

.PHONY: all build vet qml-lint lint run nix clean dev install

all: build

## build: compile the Go backend into $(BINARY) at the repo root
build:
	@cd $(BACKEND_DIR) && $(GO) build $(GOFLAGS) -o ../$(BINARY) ./cmd/ambxst
	@echo "Built ./$(BINARY)"

## vet: run go vet on the backend
vet:
	@cd $(BACKEND_DIR) && $(GO) vet ./...

## qml-lint: statically check the shell's QML
qml-lint:
	@test -n "$(QMLLINT)" || { echo "qmllint not found (install Qt Declarative tooling)" >&2; exit 1; }
	@find config modules -name '*.qml' -type f -print0 | xargs -0 "$(QMLLINT)" shell.qml

## lint: run Go and QML static checks
lint: vet qml-lint

## run: build and launch the shell (the ambxst binary itself is the
##       daemon; it supervises Quickshell, axctl and wl-paste children)
run: build
	@./$(BINARY)

## dev: alias for run
dev: build
	@./$(BINARY)

## nix: build the backend package via Nix (NixOS / Nix installs)
nix:
	@cd $(BACKEND_DIR) && git -C .. add backend 2>/dev/null; nix build '.#packages.$(shell uname -m)-linux.backend' --no-link --print-out-paths

## install: build, sudo install the binary, then remove the local copy
install: build
	sudo install $(BINARY) /usr/local/bin/$(BINARY)
	rm -f $(BINARY)

## clean: remove the compiled binary
clean:
	@rm -f $(BINARY)
	@echo "Removed ./$(BINARY)"
