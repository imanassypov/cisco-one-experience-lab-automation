#!/usr/bin/env bash
# Create a project-local Python venv and install pinned Ansible for Mac bootstrap.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT}"

PYTHON="${PYTHON:-python3}"
VENV_DIR="${ROOT}/.venv"

if ! command -v "${PYTHON}" >/dev/null 2>&1; then
  echo "python3 not found. Install Python 3 (e.g. brew install python) and retry." >&2
  exit 1
fi

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  echo "Creating virtualenv at ${VENV_DIR}"
  "${PYTHON}" -m venv "${VENV_DIR}"
fi

echo "Installing pinned packages from requirements.txt"
"${VENV_DIR}/bin/python" -m pip install --require-virtualenv --upgrade pip
"${VENV_DIR}/bin/python" -m pip install --require-virtualenv -r "${ROOT}/requirements.txt"

echo
echo "Local Ansible controller is ready."
echo "  source \"${VENV_DIR}/bin/activate\""
echo "  ansible-playbook playbooks/00_preflight.yml"
echo "  ansible-playbook playbooks/01_bootstrap_script_server.yml"
