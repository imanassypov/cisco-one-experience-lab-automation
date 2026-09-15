#!/usr/bin/env bash
# Shared Mac venv lives at ansible-automation/.venv
exec "$(cd "$(dirname "$0")/.." && pwd)/setup-local-venv.sh" "$@"
