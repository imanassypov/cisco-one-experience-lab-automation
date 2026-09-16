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
LAB_VARS="${REPO_ROOT}/ansible-automation/01_campus/evpn/ansible/inventory/group_vars/all/lab.yml"

# Shared dCloud demo passphrase. Override for any environment that is not this
# throwaway lab: VAULT_PASSPHRASE=... ./stage-script-server.sh
VAULT_PASSPHRASE="${VAULT_PASSPHRASE:-C1sco12345}"
# Set LAB_POD_ID=n to skip the prompt (useful for unattended re-runs).
LAB_POD_ID="${LAB_POD_ID:-}"

say() { printf '\n==> %s\n' "$1"; }
die() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }

APT_LOG="$(mktemp)"
trap 'rm -f "$APT_LOG"' EXIT

# This package set pulls a libc6 upgrade, which raises a debconf prompt about
# restarting services, and needrestart raises a second one. Either will block
# the run forever. sudo resets the environment, so the variables have to ride
# on the sudo command line rather than being exported.
apt_get() {
  sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 \
    apt-get -o Dpkg::Options::=--force-confdef \
            -o Dpkg::Options::=--force-confold "$@"
}

# HashiCorp publishes no kali-rolling Release file, but the dCloud image ships
# that source anyway, so every apt-get update exits non-zero. The bootstrap
# role fixes this too, but this script runs before it.
disable_hashicorp_sources() {
  local found file
  found="$(sudo grep -Rl --include='*.list' --include='*.sources' \
             -E 'apt\.releases\.hashicorp\.com' \
             /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true)"
  [[ -n "$found" ]] || return 0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if [[ "$file" == /etc/apt/sources.list ]]; then
      sudo sed -i -E 's|^([^#].*apt\.releases\.hashicorp\.com.*)$|# disabled-by-cisco-one \1|' "$file"
    else
      sudo mv -n "$file" "${file}.disabled-by-cisco-one"
    fi
    say "Disabled broken HashiCorp apt source: ${file}"
  done <<< "$found"
}

# Kali rotated its archive signing key. Images built before the rotation cannot
# verify the repository, so apt keeps the stale index and installs fail.
refresh_kali_keyring() {
  local url=https://archive.kali.org/archive-keyring.gpg
  local dest=/usr/share/keyrings/kali-archive-keyring.gpg
  say "Refreshing the Kali archive signing key"
  if command -v curl >/dev/null 2>&1; then
    sudo curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    sudo wget -qO "$dest" "$url"
  else
    die "Neither curl nor wget is available to fetch ${url}"
  fi
}

# Collection 00 used to run from the student laptop. Catch that habit here
# rather than half-way through apt.
[[ "$(uname -s)" == "Linux" ]] || die "This stages the Linux script server, but you are on $(uname -s).
       SSH to the script server first:  ssh cisco@198.18.134.12"

[[ -f "$REQUIREMENTS" ]] || die "$REQUIREMENTS not found. Run this from inside the cloned repository."

say "Staging $(hostname) from ${REPO_ROOT}"

# python3-venv and python3-dev are not installed on a stock Kali image, and pip
# needs a compiler for the crypto wheels.
say "Installing base packages (sudo may prompt for your password)"
disable_hashicorp_sources

# Answer the libc6 service-restart question up front instead of at the prompt.
echo 'libraries/restart-without-asking boolean true' | sudo debconf-set-selections

# A broken third-party source must not abort the run, so inspect the log rather
# than trusting the exit code.
apt_get update >"$APT_LOG" 2>&1 || true
if grep -qiE 'Missing key|NO_PUBKEY|signature verification failed' "$APT_LOG"; then
  refresh_kali_keyring
  apt_get update >"$APT_LOG" 2>&1 || true
fi

if ! apt_get install -y --no-install-recommends \
     git python3 python3-pip python3-venv python3-dev gcc libffi-dev libssl-dev; then
  printf '\n--- last 20 lines of apt-get update ---\n' >&2
  tail -20 "$APT_LOG" >&2
  die "Package installation failed. The apt output above usually names the repository at fault."
fi

say "Creating the virtualenv at ${VENV}"
[[ -x "${VENV}/bin/python" ]] || "$PYTHON" -m venv "$VENV"

say "Installing pinned Python packages"
"${VENV}/bin/pip" install --quiet --upgrade pip
"${VENV}/bin/pip" install --quiet -r "$REQUIREMENTS"

say "Staged: $("${VENV}/bin/ansible" --version | head -1)"

# The vault passphrase is a well-known shared value in this demo lab, so there
# is nothing to protect by prompting for it. See the README: this is not a
# pattern to carry into production.
if [[ ! -f "$VAULT_FILE" ]]; then
  printf '%s' "$VAULT_PASSPHRASE" > "$VAULT_FILE"
  say "Created ${VAULT_FILE}"
else
  say "Vault password file already present at ${VAULT_FILE}"
fi
chmod 600 "$VAULT_FILE"

# lab.yml is gitignored, so a fresh clone has only the tracked example. Seeding
# it here means the pod number can be set before any playbook runs.
[[ -f "$LAB_VARS" ]] || cp "${LAB_VARS}.example" "$LAB_VARS"

current_pod="$(sed -n -E 's/^lab_pod_id:[[:space:]]*([^[:space:]#]+).*/\1/p' "$LAB_VARS" | head -1)"

if [[ -z "$LAB_POD_ID" && "$current_pod" =~ ^[0-9]+$ ]]; then
  LAB_POD_ID="$current_pod"
  say "Pod number already set to ${LAB_POD_ID} in lab.yml"
fi

# Stages that read settings.json refuse to run while this is REPLACE_ME, and a
# wrong value would push this student's SSID onto another pod's controller.
while [[ ! "$LAB_POD_ID" =~ ^[0-9]+$ ]]; do
  if [[ ! -t 0 ]]; then
    die "lab_pod_id is unset and there is no terminal to prompt on.
       Re-run with:  LAB_POD_ID=<n> ./stage-script-server.sh"
  fi
  printf '\n'
  read -r -p 'dCloud POD number from your lab printout (integer): ' LAB_POD_ID
  [[ "$LAB_POD_ID" =~ ^[0-9]+$ ]] || printf 'Not a number: %s\n' "$LAB_POD_ID" >&2
done

sed -i -E "s/^lab_pod_id:.*/lab_pod_id: ${LAB_POD_ID}/" "$LAB_VARS"
say "Pod ${LAB_POD_ID} written to lab.yml (SSID will be PSEUDOCO-POD$(printf '%02d' "$LAB_POD_ID"))"

cat <<EOF

Then bootstrap this host:

  source ${VENV}/bin/activate
  cd ${REPO_ROOT}/ansible-automation/00_scriptserver_bootstrap
  ansible-playbook playbooks/00_preflight.yml
  ansible-playbook playbooks/01_bootstrap_script_server.yml

EOF
