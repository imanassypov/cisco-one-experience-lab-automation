# 00 — Script server bootstrap

Prepares the **Kali Linux** script server at `198.18.134.12` so later lab collections can run **on** that host.

Connect **Cisco Secure Client / AnyConnect** first. This collection is run from your Mac over SSH.

Host and URL index: [PseudoCo_Lab_Access_Lookup.md](../../Lab%20Topology/PseudoCo_Lab_Access_Lookup.md). Credentials for this collection and every later playbook come from vault-encrypted [lab_access.yml](../../Lab%20Topology/lab_access.yml) (`script_server` key here). Do not put passwords in playbooks or unencrypted inventory.

## What it installs

- OS packages: `git`, Python 3, `pip`, `venv`, `sshpass`, and compiler headers
- A user virtualenv at `~/venv` (Ansible is **not** installed with apt/yum)
- Pinned `ansible-core`, `paramiko`, and `netaddr` inside that venv
- Venv CLI binaries on PATH (`~/.bashrc`, `~/.profile`, `~/.zshrc`, `~/.zprofile` — Kali’s default shell is zsh) and symlinked into `~/bin`
- On Kali, disables the HashiCorp apt source if it targets `kali-rolling` (that repo has no Release file and breaks `apt update`)
- Pinned Cisco Galaxy collections (`cisco.ios`, `cisco.catalystcenter` 2.10.2, `cisco.dnac` 6.46.0, `cisco.ise`, `cisco.nxos`, `cisco.meraki`)
- Pinned CatC Python SDKs (`catalystcentersdk` 3.1.3.0.1, `dnacentersdk` 2.10.6) for appliance 3.1.5 / API profile 3.1.3.0
- Git checkout of this repo at `~/cisco-one-experience-lab-automation` (the only project tree on the script server)

## Playbook sequence

Playbooks in `playbooks/` are numbered in the order they should be applied:

| Playbook | Purpose |
| --- | --- |
| `00_preflight.yml` | Confirm VPN path and TCP/22 to the script server |
| `01_bootstrap_script_server.yml` | Install the script-server venv, Ansible binaries, collections, and pull this GitHub repo |
| `02_sync_from_git.yml` | Clone or pull this GitHub repo onto the script server (sync only, no reinstall) |

Later collections (`01_campus` and onward) will use the same `00_`, `01_`, … naming inside their own `playbooks/` folders.

## Prerequisites on the Mac

Python 3 with the `venv` module (macOS / Xcode CLT or `brew install python`). Ansible and its dependencies are installed **only** into this collection's `.venv` (gitignored). Do not `brew install ansible` or `pip install` into the system Python.

```bash
cd ansible-automation/00_scriptserver_bootstrap
./setup-local-venv.sh
source .venv/bin/activate
```

That installs the pins in `requirements.txt` (`ansible-core`, `paramiko`, `netaddr`) — the same versions the script server venv will get.

`ansible.cfg` reads the repo-root `.vault` (gitignored) to decrypt `Lab Topology/lab_access.yml`. If it is missing, from the repository root: `cp .vault.example .vault` and put the lab vault password on a single line. Do not commit `.vault`.

The inventory uses Paramiko so password auth works on macOS without `sshpass`.

## Run

```bash
cd ansible-automation/00_scriptserver_bootstrap
source .venv/bin/activate
ansible-playbook playbooks/00_preflight.yml
ansible-playbook playbooks/01_bootstrap_script_server.yml
ansible-playbook playbooks/02_sync_from_git.yml
```

After bootstrap, later collections are developed on the Mac, pushed to GitHub, then synced and run **on** the script server. See the root README development workflow.

SSH to the script server and confirm `ansible-playbook --version` works without activating that host's venv. Test from `~/cisco-one-experience-lab-automation`. Recreate the repo-root `.vault` there after clone.
