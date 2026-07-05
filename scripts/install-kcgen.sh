#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${PROJECT_ROOT}/out/bin"

mkdir -p "${BIN_DIR}"

command -v go >/dev/null || {
  echo "ERROR: Go is required to build kcgen"
  exit 1
}

echo "Installing kcgen into ${BIN_DIR}..."
GOBIN="${BIN_DIR}" go install github.com/vtrenton/kcgen@master

echo "kcgen installed:"
"${BIN_DIR}/kcgen" --help || true
