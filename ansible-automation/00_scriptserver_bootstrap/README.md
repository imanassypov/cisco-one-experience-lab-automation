# 00 — Script server bootstrap

Prepares the **Kali Linux** script server at `198.18.134.12` so every later lab collection can run **on** that host.

This collection runs **on the script server itself**. You SSH in, clone this repository there, and bootstrap the box from its own checkout. Nothing is installed on your laptop, and no playbook reaches across the network to configure another machine.

Connect **Cisco Secure Client / AnyConnect** to the dCloud session first — that is what makes `198.18.134.12` reachable.

Host and URL index: [PseudoCo_Lab_Access_Lookup.md](../../Lab%20Topology/PseudoCo_Lab_Access_Lookup.md). Credentials for this collection and every later playbook come from vault-encrypted [lab_access.yml](../../Lab%20Topology/lab_access.yml) (`script_server` key here). Do not put passwords in playbooks or unencrypted inventory.

## Quick start

```bash
# 1. From your laptop, connect the dCloud VPN, then SSH to the script server
ssh cisco@198.18.134.12

# 2. Clone this repository onto the script server
git clone https://github.com/imanassypov/cisco-one-experience-lab-automation.git
cd cisco-one-experience-lab-automation/ansible-automation/00_scriptserver_bootstrap

# 3. Stage the box. Prompts once for your dCloud POD number.
./stage-script-server.sh

# 4. Bootstrap. Uses the venv directly - nothing to activate.
~/venv/bin/ansible-playbook playbooks/00_preflight.yml
~/venv/bin/ansible-playbook playbooks/01_bootstrap_script_server.yml
```

You can clone anywhere — `~/cisco-one-experience-lab-automation` is only a convention. Every path is derived from where the playbook lives, so a clone under any directory works.

The staging script also writes the repo-root `.vault` for you and seeds `lab.yml` with the pod number you entered, so there is nothing to create by hand. To skip the prompt on an unattended re-run: `LAB_POD_ID=7 ./stage-script-server.sh`.

> Call `ansible-playbook` by its full path until `01` has run — that is the playbook that puts `~/venv/bin` on `PATH`. After it completes, a new shell can just run `ansible-playbook`. If apt offers to install `ansible-core`, say no: that would be an unpinned copy outside the venv.

## Why a staging script before Ansible

`stage-script-server.sh` exists to solve a chicken-and-egg problem: you cannot run `ansible-playbook` to install Ansible. The script does the minimum needed to get Ansible running, and the bootstrap playbook does everything else.

| Step | Done by | What |
| --- | --- | --- |
| Base packages | `stage-script-server.sh` | `git`, `python3`, `pip`, `venv`, `python3-dev`, `gcc`, `libffi-dev`, `libssl-dev` |
| Virtualenv at `~/venv` | `stage-script-server.sh` | Pins from [`requirements.txt`](../requirements.txt) — `ansible-core`, `paramiko`, `netaddr`, both CatC SDKs |
| `.vault` and `lab.yml` | `stage-script-server.sh` | Writes the vault passphrase and the POD number it prompted for |
| Everything else | `01_bootstrap_script_server.yml` | DNS, PATH, Galaxy collections, Genie/pyATS |

The script is idempotent — re-running it is harmless. It refuses to run on anything other than Linux, so running it on your laptop by mistake fails immediately and prints the SSH command you actually wanted.

## What the bootstrap installs

- Lab DNS `198.18.5.102` first (then dCloud `198.18.128.1`) in `/etc/network/interfaces` and `/etc/resolv.conf` so `cat-center.corp.pseudoco.com` resolves
- OS packages, kept deliberately minimal: `git`, `pip`, and the versioned `pythonX.Y-venv`. No compiler and no `-dev` headers — every pinned wheel is prebuilt for this interpreter, and on the dCloud image `libffi-dev` / `libssl-dev` cannot install without dragging `libc6` forward
- The user virtualenv at `~/venv` (Ansible is **not** installed with apt/yum)
- Pinned `ansible-core`, `paramiko`, `netaddr`, plus `genie` and `pyats` — stage 10 parses every CLI response with Genie, which adds roughly 700 MB — and `rich`, which renders the stage 10 markdown report in the terminal
- Pinned CatC Python SDKs (`catalystcentersdk` 3.1.3.0.1, `dnacentersdk` 2.10.6) for appliance 3.1.5 / API profile 3.1.3.0
- Venv CLI binaries on PATH (`~/.bashrc`, `~/.profile`, `~/.zshrc`, `~/.zprofile` — Kali's default shell is zsh) and symlinked into `~/bin`
- Pinned Cisco Galaxy collections — see [`files/requirements.yml`](roles/script_server_bootstrap/files/requirements.yml) for the authoritative versions
- On Kali, disables the HashiCorp apt source if it targets `kali-rolling` (that repo has no Release file and breaks `apt update`)
- Seeds `inventory/group_vars/all/lab.yml` from the tracked example, and never overwrites it afterwards

> **Why so little is installed from apt.** The dCloud image tracks `kali-rolling` and `kali-last-snapshot` at the same time, so apt offers base packages far newer than what is installed — `python3` 3.14 against 3.13, `libc6` 2.43 against 2.40. Asking apt for an already-installed package is an upgrade request, and upgrading `python3` breaks the ~120 installed `python3-*` packages that require an older one. So the bootstrap names as little as possible and never runs `apt --fix-broken install`, which would attempt exactly that system-wide upgrade.

## Playbook sequence

| Playbook | Purpose | Re-runnable |
| --- | --- | --- |
| `00_preflight.yml` | Confirm you are on Linux, the checkout is complete, `.vault` decrypts, and `sudo` works | Yes, read-only |
| `01_bootstrap_script_server.yml` | DNS, packages, venv, PATH, collections, `lab.yml` seed, verification | Yes |
| `02_sync_from_git.yml` | Fast-forward this checkout to pick up lab changes published later | Yes |

`02_sync_from_git.yml` updates the checkout **in place** — it never re-clones, and it fails rather than discarding uncommitted work. Run it when told a lab fix has been published.

Later collections (`01_campus` and onward) use the same `00_`, `01_`, … naming inside their own `playbooks/` folders.

## The vault password file

`ansible.cfg` reads the repo-root `.vault` (gitignored) to decrypt `Lab Topology/lab_access.yml`. `stage-script-server.sh` writes it for you with the shared lab passphrase.

Preflight proves the passphrase actually works before anything is changed — a wrong passphrase fails there with a readable message instead of an opaque decrypt error mid-run.

> **This is encryption theatre, on purpose.** `lab_access.yml` is committed **and** the passphrase that opens it is in `stage-script-server.sh`, so anyone with the repository can read every lab credential. That is an acceptable trade for a disposable dCloud pod whose credentials are already public demo values, and it removes a step students routinely got wrong. It is **not** a pattern to copy: a real environment needs a unique passphrase per environment, kept out of the repository and injected from a secret store. Override it here with `VAULT_PASSPHRASE=... ./stage-script-server.sh`.

## After bootstrap

Every later collection runs from this same checkout, with Ansible already on PATH:

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/01_campus/evpn/ansible
ansible-playbook playbooks/01_site_hierarchy.yml
```

Confirm `ansible-playbook --version` works in a fresh interactive shell without `source ~/venv/bin/activate` — `path.yml` puts the venv binaries on PATH for both bash and zsh. See the root README for the development workflow.
