#!/usr/bin/env bash
# Create a shared Python venv for every collection under ansible-automation/.
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
echo "  cd 00_scriptserver_bootstrap && ansible-playbook playbooks/00_preflight.yml"
echo "  cd 01_campus/evpn/ansible && ansible-playbook playbooks/01_site_hierarchy.yml"
