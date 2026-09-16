#!/usr/bin/env bash
# Stages this Linux script server so it can run the automation locally.
#
# Run this ON the script server, from your own clone of the repository:
#   ssh cisco@198.18.134.12
#   git clone https://github.com/imanassypov/cisco-one-experience-lab-automation.git
#   cd cisco-one-experience-lab-automation/ansible-automation/00_scriptserver_bootstrap
#   ./stage-script-server.sh
#
# It installs only what is needed to run ansible-playbook. The bootstrap role
# installs the rest (Galaxy collections, Genie/pyATS, DNS, PATH).
# Safe to re-run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REQUIREMENTS="${REPO_ROOT}/ansible-automation/requirements.txt"
VENV="${VENV:-${HOME}/venv}"
PYTHON="${PYTHON:-python3}"
VAULT_FILE="${REPO_ROOT}/.vault"

say() { printf '\n==> %s\n' "$1"; }
die() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }

# Collection 00 used to run from the student laptop. Catch that habit here
# rather than half-way through apt.
[[ "$(uname -s)" == "Linux" ]] || die "This stages the Linux script server, but you are on $(uname -s).
       SSH to the script server first:  ssh cisco@198.18.134.12"

[[ -f "$REQUIREMENTS" ]] || die "$REQUIREMENTS not found. Run this from inside the cloned repository."

say "Staging $(hostname) from ${REPO_ROOT}"

# python3-venv and python3-dev are not installed on a stock Kali image, and pip
# needs a compiler for the crypto wheels.
say "Installing base packages (sudo may prompt for your password)"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  git python3 python3-pip python3-venv python3-dev gcc libffi-dev libssl-dev

say "Creating the virtualenv at ${VENV}"
[[ -x "${VENV}/bin/python" ]] || "$PYTHON" -m venv "$VENV"

say "Installing pinned Python packages"
"${VENV}/bin/pip" install --quiet --upgrade pip
"${VENV}/bin/pip" install --quiet -r "$REQUIREMENTS"

say "Staged: $("${VENV}/bin/ansible" --version | head -1)"

if [[ ! -f "$VAULT_FILE" ]]; then
  cat <<EOF

NEXT: create the vault password file. Ask your proctor for the passphrase.

  read -rs -p 'Lab vault password: ' VP && printf '%s' "\$VP" > "$VAULT_FILE" && unset VP
  chmod 600 "$VAULT_FILE"

EOF
else
  chmod 600 "$VAULT_FILE"
  say "Vault password file already present at ${VAULT_FILE}"
fi

cat <<EOF

Then bootstrap this host:

  source ${VENV}/bin/activate
  cd ${REPO_ROOT}/ansible-automation/00_scriptserver_bootstrap
  ansible-playbook playbooks/00_preflight.yml
  ansible-playbook playbooks/01_bootstrap_script_server.yml

EOF
