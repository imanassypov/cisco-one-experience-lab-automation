# Getting Started — first run of the EVPN pipeline

First-time setup. Follow these steps **in order**, once per pod. At the end you
will be able to run the pipeline stages (`01`–`10`) against Catalyst Center.

Two machines are involved:

| Machine | Role |
|---------|------|
| Your **Mac** | Authors the repo and bootstraps the script server. Never runs the pipeline against Catalyst Center. |
| The **Kali script server** at `198.18.134.12` | Runs the pipeline. It is the host with reachability to Catalyst Center (`cat-center.corp.pseudoco.com`) and to the Site 105 switches. |

| Step | What it does | Time |
|------|--------------|------|
| 1 | Connect the dCloud VPN | 2 min |
| 2 | Clone the repo and create `.vault` on the Mac | 3 min |
| 3 | Build the Mac venv | 3 min |
| 4 | Bootstrap the Kali script server | ~10 min |
| 5 | Recreate `.vault` on Kali | 1 min |
| 6 | Set your POD number and AP MACs | 2 min |
| 7 | Verify, then run stage 01 | 5 min |

---

## Prerequisites

- An active dCloud session for the **PseudoCo / Cisco One** lab, powered on.
- **Cisco Secure Client / AnyConnect** credentials for that session.
- Python 3 with the `venv` module on your Mac (Xcode CLT or `brew install python`).
- The **lab vault password** — a single passphrase that decrypts every credential
  in this repo. Ask a proctor if you do not have it.

> **Never commit credentials.** All secrets live in one encrypted file,
> `Lab Topology/lab_access.yml`, and the passphrase that opens it lives in
> `.vault` at the repository root, which is gitignored. You never paste a
> password into a playbook, an inventory file, or `settings.json`.

---

## Step 1 — Connect the dCloud VPN

Nothing in this lab is reachable without it. Connect Cisco Secure Client to the
session, then confirm the script server answers:

```bash
nc -z -G 5 198.18.134.12 22 && echo reachable
```

If that hangs or fails, the VPN is down or the pod is still booting. Lab VMs can
take several minutes after a session starts before SSH comes up.

---

## Step 2 — Clone the repository and create `.vault`

```bash
git clone https://github.com/imanassypov/cisco-one-experience-lab-automation.git
cd cisco-one-experience-lab-automation
```

`.vault` holds the **passphrase**, one bare line, no quotes. It is gitignored, so
a fresh clone never has one — you create it on every machine that runs Ansible:

```bash
cp .vault.example .vault
read -rs -p 'Lab vault password: ' VP && printf '%s' "$VP" > .vault && unset VP
chmod 600 .vault
```

`read -rs` keeps the passphrase off your screen and out of your shell history,
and `printf '%s'` writes it with no trailing newline.

Confirm it opens the credential map:

```bash
ansible-vault view "Lab Topology/lab_access.yml" --vault-password-file .vault | head -4
# ---
# # Vault-encrypted lab access lookup. Single credential source for all playbooks.
# lab_access:
#   "script_server":
```

If that prints YAML, every playbook in the repo can authenticate. If it says
`Decryption failed`, the passphrase in `.vault` is wrong. The
`--vault-password-file` flag is needed here only because the repository root has
no `ansible.cfg`; inside a collection directory the config supplies it.

> **Two files, two jobs.** `.vault` is the passphrase; `Lab Topology/lab_access.yml`
> is the encrypted `lab_access` map of hosts, usernames, and passwords. The map
> **is** committed (encrypted); the passphrase never is. A vars plugin at
> `ansible-automation/plugins/vars/lab_access.py` decrypts the map and injects
> `lab_access` into every play, which is why no playbook takes a password prompt.

---

## Step 3 — Build the Mac venv

Ansible is installed **only** into this collection's `.venv`. Do not
`brew install ansible` or `pip install` into the system Python.

```bash
cd ansible-automation/00_scriptserver_bootstrap
./setup-local-venv.sh
source .venv/bin/activate
```

That installs the pins from `requirements.txt` — `ansible-core` 2.17.14,
`paramiko`, `netaddr`, and the two Catalyst Center SDKs — the same versions the
script server will get. Paramiko is what lets password auth work on macOS
without `sshpass`.

---

## Step 4 — Bootstrap the Kali script server

Run all three from `00_scriptserver_bootstrap/` with the venv active. The
inventory targets `198.18.134.12` and reads its login from
`lab_access.script_server`, so you are not asked for credentials.

```bash
ansible-playbook playbooks/00_preflight.yml
ansible-playbook playbooks/01_bootstrap_script_server.yml
ansible-playbook playbooks/02_sync_from_git.yml
```

| Playbook | What it does |
|----------|--------------|
| `00_preflight.yml` | Fails fast with a clear message if the VPN path or TCP/22 is down |
| `01_bootstrap_script_server.yml` | OS packages, a venv at `~/venv` with the same pins, venv binaries on `PATH`, pinned Cisco collections and SDKs, lab DNS, and a clone of this repo at `~/cisco-one-experience-lab-automation` |
| `02_sync_from_git.yml` | Git pull only — the fast path for later updates |

Both bootstrap playbooks are safe to re-run.

Lab DNS matters: `01` puts `198.18.5.102` first in `/etc/resolv.conf` (dCloud
`198.18.128.1` as fallback) so `cat-center.corp.pseudoco.com` resolves. Without
it, every Catalyst Center stage fails on name resolution.

> `02_sync_from_git.yml` fails if the Kali tree has local modifications, which
> happens easily after ad-hoc file copies. Commit or revert them on Kali, or
> re-run `01`.

---

## Step 5 — Recreate `.vault` on the script server

`.vault` is gitignored, so the clone Kali just made does not include it. Repeat
Step 2's vault creation there, with the same passphrase:

```bash
ssh cisco@198.18.134.12
cd ~/cisco-one-experience-lab-automation
cp .vault.example .vault
read -rs -p 'Lab vault password: ' VP && printf '%s' "$VP" > .vault && unset VP
chmod 600 .vault

ansible-vault view "Lab Topology/lab_access.yml" --vault-password-file .vault | head -4
```

Ansible is already on `PATH` from `~/venv` in an interactive shell — no
`activate` needed.

> **Working directory rule — read this once, remember it forever.**
> Ansible only reads `ansible.cfg` from the **current** directory, and that file
> is what points at the inventory, the roles, the vars plugin, and `.vault`. Every
> `ansible`, `ansible-playbook`, `ansible-inventory`, and `ansible-vault` command
> for this pipeline runs from:
>
> ```bash
> cd ~/cisco-one-experience-lab-automation/ansible-automation/01_campus/evpn/ansible
> ```
>
> Run them from anywhere else and you get a missing inventory, unresolved vault
> passwords, and interactive password prompts.

---

## Step 6 — Set your POD number and AP MACs

Every student runs the same repo against a different pod, so the values that
differ live in one file: `inventory/group_vars/all/lab.yml`. `settings.json`
carries `{POD}` and `{APn_MAC}` placeholders that are filled in from it at run
time.

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/01_campus/evpn/ansible
vi inventory/group_vars/all/lab.yml
```

| Variable | Value |
|----------|-------|
| `lab_pod_id` | Your dCloud POD number from the lab printout. Zero-padded to two digits, so pod 7 yields SSID `PSEUDOCO-POD07`. The padding is not cosmetic — the SSID must match a pre-configured group policy on the WLC. |
| `lab_ap_macs` | Ethernet MAC of each access point in join order, colon-separated. List only the APs your pod actually has — `settings.json` always carries two AP entries, and the one whose `{APn_MAC}` finds no match stays unresolved and is skipped rather than sent to Catalyst Center as a bad MAC. Use the Ethernet MAC from `show ap summary`, not the Base Radio MAC. |

To try a different pod for one run without editing the file:

```bash
ansible-playbook playbooks/07_network_profile.yml -e lab_pod_id=7
```

> Unlike `.vault`, `lab.yml` **is** tracked in git, so your edit shows up in
> `git status` and will follow a `git pull` into a conflict. It holds no
> secrets — a pod number and AP MACs only.

---

## Step 7 — Verify, then run stage 01

From the `ansible/` directory, check the inventory resolves:

```bash
ansible-inventory --graph
```

Expected — two groups and nothing else:

```
@all:
  |--@catalyst_center:
  |  |--catalyst_center_api
  |--@campus_evpn:
  |  |--@evpn_leaves:
  |  |  |--Site_105-Leaf1
  |  |  |--Site_105-Leaf2
  |  |--@evpn_border_spine:
  |  |  |--Site_105-Border-Spine
```

`catalyst_center` is `localhost` driving the Catalyst Center REST API and is the
target of stages `01`–`09`. `campus_evpn` is the three Site 105 switches over
SSH, used only by stage `10`.

Then run the first stage:

```bash
ansible-playbook playbooks/01_site_hierarchy.yml
```

Continue with the stage order in [README.md](README.md#pipeline-order).

---

## Collections

`01_bootstrap_script_server.yml` installs the pinned Cisco collections into
`~/venv`, so you normally never run `ansible-galaxy` by hand. If a stage reports
a missing collection:

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

| File | Target |
|------|--------|
| `collections/requirements.yml` | The script server and the Mac — ansible-core 2.17 |
| `collections/requirements-jumphost.yml` | A Python 3.9 host capped at ansible-core 2.15. Each pin is the newest release that still admits 2.15. |

`cisco.catalystcenter` must stay at **2.4.0 or newer** on either file. Older
releases return results under `dnac_response` while every role here reads
`catalystcenter_response`, which silently produces an empty site map.

---

## Troubleshooting

Add `-e catc_debug=true` (or `-e dnac_debug=true`) to any Catalyst Center stage
to print the full HTTP request and response for each API call.

> **Never share that output.** Debug mode also prints the `X-Auth-Token` bearer
> JWT, which is a live credential for your Catalyst Center. Redact it before
> pasting anywhere, and never commit a debug transcript.

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Cannot reach 198.18.134.12:22` from `00_preflight.yml` | VPN down, or the pod is still booting | Reconnect Cisco Secure Client and wait a few minutes |
| Hang or `Connection timed out` on `cat-center.corp.pseudoco.com` or `198.18.128.22–24` | Same — the VPN dropped mid-run | Reconnect, then re-run the stage |
| `Name or service not known` for `corp.pseudoco.com` names | Lab DNS not first in `/etc/resolv.conf` | Re-run `01_bootstrap_script_server.yml` |
| `Lab access vault not found. Expected Lab Topology/lab_access.yml above …` | You ran from outside the repo tree | `cd` into `evpn/ansible` first |
| `Decryption failed` on any playbook | `.vault` content ≠ the passphrase the file was encrypted with | Re-create `.vault` (Step 2 / Step 5) |
| `Attempting to decrypt but no vault secrets found` | `.vault` missing at the repository root | Step 2 / Step 5 |
| `must decrypt to a mapping with a top-level lab_access key` | `lab_access.yml` was re-created without its `lab_access:` root key | Rebuild it from `lab_access.yml.example` and re-encrypt |
| `ansible-playbook: not found` when driving Kali with `ansible … -m shell` | Non-login shells do not pick up `~/venv` from `.bashrc` | Call the full path: `/home/cisco/venv/bin/ansible-playbook` |
| `02_sync_from_git.yml` fails on local changes | The Kali tree is dirty from ad-hoc file copies | Commit or revert on Kali, or re-run `01` |
| Stage 01 fails `[400] NCND00067: The request body is invalid` on an area CREATE | `cisco.catalystcenter` below 2.4.0 — `parentId` is sent empty | `ansible-galaxy collection install cisco.catalystcenter:2.10.2 --force` |
| `'lab_pod_id' is undefined` on stage 07 | `lab.yml` was emptied or is not being loaded | Step 6 |
| Stage 07 asserts on an SSID name still containing `{` | The `{POD}` placeholder was edited out of `settings.json` | Restore the placeholder — the pod number belongs in `lab.yml`, not in `settings.json` |
| `Collection <name> does not support Ansible version 2.15.x` | Collections from `requirements.yml` installed on a 2.15 host | Use `requirements-jumphost.yml` there |

---

## Reference — where everything lives

The same tree exists on the Mac and on Kali; only `.vault` and the venvs differ.

```
~/cisco-one-experience-lab-automation/
├── .vault                                  # lab passphrase (you create, gitignored)
├── Lab Topology/
│   ├── lab_access.yml                      # encrypted credential map (committed)
│   └── PseudoCo_Lab_Access_Lookup.md       # host and URL index, no passwords
└── ansible-automation/
    ├── plugins/vars/lab_access.py          # injects lab_access into every play
    ├── 00_scriptserver_bootstrap/          # ← run from the Mac
    │   ├── .venv/                          # Mac Ansible venv (gitignored)
    │   └── playbooks/                      # 00_preflight, 01_bootstrap, 02_sync
    └── 01_campus/evpn/
        ├── Catalyst Center Templates/      # DEFN / FUNC / FABRIC .j2
        ├── Settings/settings.json          # single source of truth for stages 01–09
        └── ansible/                        # ← run every pipeline command from here
            ├── ansible.cfg
            ├── inventory/
            │   ├── static_inventory.yml
            │   └── group_vars/all/lab.yml  # your POD number and AP MACs
            └── playbooks/                  # 01–10 stages

~/venv/                                     # script server Ansible venv (on PATH)
```
