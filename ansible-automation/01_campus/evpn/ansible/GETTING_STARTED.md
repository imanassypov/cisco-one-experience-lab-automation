# Getting Started — first run of the EVPN pipeline

First-time setup. Follow these steps **in order**, once per pod. At the end you
will be able to run the pipeline stages (`01`–`10`) against Catalyst Center.

Everything runs on **one machine**:

| Machine | Role |
|---------|------|
| Your **laptop** | Runs the dCloud VPN client and an SSH session. Nothing is installed on it. |
| The **Kali script server** at `198.18.134.12` | You clone the repo here and run everything here. It is the host with reachability to Catalyst Center (`cat-center.corp.pseudoco.com`) and to the Site 105 switches. |

| Step | What it does | Time |
|------|--------------|------|
| 1 | Connect the dCloud VPN and SSH to the script server | 2 min |
| 2 | Clone the repo onto the script server | 2 min |
| 3 | Stage the box and create `.vault` | 5 min |
| 4 | Bootstrap the script server | ~10 min |
| 5 | Confirm PATH and working directory | 1 min |
| 6 | Set your POD number and AP MACs | 2 min |
| 7 | Verify, then run stage 01 | 5 min |

---

## Prerequisites

- An active dCloud session for the **PseudoCo / Cisco One** lab, powered on.
- **Cisco Secure Client / AnyConnect** credentials for that session.
- An SSH client. Nothing else is needed on your laptop.
- The **lab vault password** — a single passphrase that decrypts every credential
  in this repo. Ask a proctor if you do not have it.

> **Never commit credentials.** All secrets live in one encrypted file,
> `Lab Topology/lab_access.yml`, and the passphrase that opens it lives in
> `.vault` at the repository root, which is gitignored. You never paste a
> password into a playbook, an inventory file, or `settings.json`.

---

## Step 1 — Connect the dCloud VPN and SSH in

Nothing in this lab is reachable without the VPN. Connect Cisco Secure Client to
the session, then confirm the script server answers:

```bash
nc -z -G 5 198.18.134.12 22 && echo reachable
```

If that hangs or fails, the VPN is down or the pod is still booting. Lab VMs can
take several minutes after a session starts before SSH comes up.

Then connect. Everything from here happens in this SSH session:

```bash
ssh cisco@198.18.134.12
```

---

## Step 2 — Clone the repository onto the script server

```bash
git clone https://github.com/imanassypov/cisco-one-experience-lab-automation.git
cd cisco-one-experience-lab-automation
```

The rest of this guide assumes the checkout is at
`~/cisco-one-experience-lab-automation`, but that is only a convention — every
path is derived from where the playbooks live, so any directory works.

---

## Step 3 — Stage the box and create `.vault`

You cannot run `ansible-playbook` to install Ansible, so a small shell script
does the minimum first: base packages and a virtualenv at `~/venv` holding the
pinned `ansible-core`, `paramiko`, `netaddr`, and both Catalyst Center SDKs.

```bash
cd ansible-automation/00_scriptserver_bootstrap
./stage-script-server.sh
```

`sudo` will prompt for the `cisco` account password. The script is idempotent,
and it refuses to run anywhere other than Linux — if you run it on your laptop
by mistake it tells you the SSH command you actually wanted.

It also prompts once for your **dCloud POD number**, from your lab printout,
and writes it into `lab.yml`. That is the only lab value you have to supply.
Pod 7 becomes SSID `PSEUDOCO-POD07` — the zero padding matters, because the
SSID must match a pre-configured group policy on the shared WLC. To skip the
prompt on a re-run: `LAB_POD_ID=7 ./stage-script-server.sh`.

The script writes `.vault` for you as well. It holds the **passphrase**, one
bare line, no quotes, and it is gitignored so a fresh clone never has one.

Confirm it opens the credential map:

```bash
cd ~/cisco-one-experience-lab-automation
ansible-vault view "Lab Topology/lab_access.yml" --vault-password-file .vault | head -4
# ---
# # Vault-encrypted lab access lookup. Single credential source for all playbooks.
# lab_access:
#   "script_server":
```

If that prints YAML, every playbook in the repo can authenticate. The
`--vault-password-file` flag is needed here only because the repository root has
no `ansible.cfg`; inside a collection directory the config supplies it.

> **Two files, two jobs.** `.vault` is the passphrase; `Lab Topology/lab_access.yml`
> is the encrypted `lab_access` map of hosts, usernames, and passwords. A vars
> plugin at `ansible-automation/plugins/vars/lab_access.py` decrypts the map and
> injects `lab_access` into every play, which is why no playbook takes a
> password prompt.

> **Be clear-eyed about what this vault protects: nothing.** The encrypted map
> is committed *and* the passphrase is in `stage-script-server.sh`, so anyone
> with the repository can read every lab credential. That is a deliberate trade
> for a disposable pod whose credentials are already public demo values. In a
> real environment the passphrase never lives in the repository — use a unique
> one per environment from a secret store, via `VAULT_PASSPHRASE=...`.

---

## Step 4 — Bootstrap the script server

Run the two bootstrap playbooks from `00_scriptserver_bootstrap/`. Both target
this host over a **local** connection — there is no SSH hop and no remote
credentials.

Call them by full path. `~/venv/bin` is not on your `PATH` yet — putting it
there is one of the things `01` does, which is the usual chicken-and-egg of
bootstrapping.

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/00_scriptserver_bootstrap
~/venv/bin/ansible-playbook playbooks/00_preflight.yml
~/venv/bin/ansible-playbook playbooks/01_bootstrap_script_server.yml
```

> If your shell says `ansible-playbook: command not found` and apt offers to
> install `ansible-core`, answer **no**. That would install an unpinned Ansible
> outside the venv, at a different version from every other student. Use the
> full path above, or `source ~/venv/bin/activate` first.

| Playbook | What it does |
|----------|--------------|
| `00_preflight.yml` | Read-only. Confirms you are on Linux, the checkout is complete, `.vault` decrypts, and `sudo` works |
| `01_bootstrap_script_server.yml` | Lab DNS, OS packages, the `~/venv` pins including Genie/pyATS, venv binaries on `PATH`, pinned Cisco collections and SDKs, and seeds `lab.yml` |
| `02_sync_from_git.yml` | Fast-forwards this checkout later, to pick up lab fixes published after you cloned |

All three are safe to re-run. Preflight is worth running first every time: it
proves the passphrase before anything is changed, so a wrong `.vault` fails with
a readable message instead of an opaque decrypt error part-way through.

Lab DNS matters: `01` puts `198.18.5.102` first in `/etc/resolv.conf` (dCloud
`198.18.128.1` as fallback) so `cat-center.corp.pseudoco.com` resolves. Without
it, every Catalyst Center stage fails on name resolution.

> `02_sync_from_git.yml` fails if the tree has local modifications rather than
> discarding them. Commit or revert your changes, then re-run it.

---

## Step 5 — Confirm PATH and working directory

Open a fresh shell (or log out and back in). `01` put the venv binaries on
`PATH` for both bash and zsh, so Ansible works without activating anything:

```bash
ansible-playbook --version
```

If that fails, `source ~/venv/bin/activate` still works as a fallback.

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

## Step 6 — Confirm your POD number, and AP MACs later

Every student runs the same repo against a different pod, so the values that
differ live in one file: `inventory/group_vars/all/lab.yml`. `settings.json`
carries `{POD}` and `{APn_MAC}` placeholders that are filled in from it at run
time.

`stage-script-server.sh` already created this file and wrote the pod number it
prompted you for in Step 3, so there is normally nothing to do here. Confirm it:

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/01_campus/evpn/ansible
grep lab_pod_id inventory/group_vars/all/lab.yml
```

Edit it only if you entered the wrong pod, or when you come back to add AP MACs:

```bash
vi inventory/group_vars/all/lab.yml
```

| Variable | Value |
|----------|-------|
| `lab_pod_id` | Your dCloud POD number from the lab printout (integer), set for you in Step 3. Stages 01–05 and 07–09 **fail** while it is `REPLACE_ME`, so a skipped value cannot push another student's SSID (`PSEUDOCO-PODnn`) onto the shared WLC. Zero-padded to two digits at run time, so pod 7 yields `PSEUDOCO-POD07`. The pod is **only** that SSID — not switch IPs or site paths. Which playbooks use it: [README — lab_pod_id](README.md#lab_pod_id--wlan-ssid-only). |
| `lab_ap_macs` | Leave `[]` until **after** stage 09 — and then let the automation fill it. The composite programs the AP trunk (`Gi1/0/2`, native VLAN 10); until then the AP cannot join the WLC and Catalyst Center has no Unified AP. Once stage 09 is done, run `10_await_access_points.yml`: it waits for the AP to reach Catalyst Center, then writes the **Ethernet** MAC into this file for you. Re-run stage 08 afterwards, which names the AP, assigns it to Site-105, then provisions it. Fill it by hand only if you prefer — colon-separated, Ethernet MAC not Base Radio MAC. |

To try a different pod for one run without editing the file:

```bash
ansible-playbook playbooks/07_network_profile.yml -e lab_pod_id=7
```

> `lab.yml` is **gitignored**, so your pod values survive every later `git pull`
> and the bootstrap can keep updating the checkout. It is seeded from the
> tracked `lab.yml.example` and never overwritten after. It holds no secrets —
> a pod number and AP MACs only.
>
> If `lab.yml` is missing, re-run `./stage-script-server.sh`, or copy it back:
>
> ```bash
> cp inventory/group_vars/all/lab.yml.example inventory/group_vars/all/lab.yml
> ```

---

## Step 7 — Verify, then run stage 01

Still on Kali, from the `ansible/` directory, check the inventory resolves.

`ansible-inventory` is a **read-only** inspector. It does not SSH to switches
or call Catalyst Center. It loads the same files `ansible-playbook` will use,
then prints the host/group tree. Run it here because Ansible only reads
`ansible.cfg` from the **current** directory.

That `ansible.cfg` points at:

| Setting | File | What the student sees |
|---------|------|------------------------|
| `inventory` | `inventory/static_inventory.yml` | Groups and hostnames (`catalyst_center_api`, the three `Site_105-*` switches) and their `ansible_host` IPs |
| `vault_password_file` | repo-root `.vault` | Unlocks `Lab Topology/lab_access.yml` |
| `vars_plugins` | `ansible-automation/plugins/vars/lab_access.py` | Injects `lab_access` so each switch can resolve `ansible_user` / `ansible_password` |

`--graph` prints **names and groups only**. It does not print IPs or passwords.
Empty `@ungrouped` is normal — Ansible always creates that group.

```bash
ansible-inventory --graph
```

You should see:

```
@all:
  |--@ungrouped:
  |--@catalyst_center:
  |  |--catalyst_center_api
```

`catalyst_center` is `localhost` driving the Catalyst Center REST API, and it is
the target of every stage. There are no device hosts: stage `10` collects switch
and controller CLI through Catalyst Center Command Runner rather than over SSH,
so the control node never needs to reach `198.18.128.22–24`.

Then run the first stage:

```bash
ansible-playbook playbooks/01_site_hierarchy.yml
```

dCloud Catalyst Center already has this hierarchy. A successful first run
against a stock pod looks like:

```
TASK [site_hierarchy : Site hierarchy provisioning complete]
ok: [catalyst_center_api] => {
    "msg": [
        "Created 0, updated 0, skipped 16",
        "skipped  Global/CALIFORNIA",
        "skipped  Global/NEW YORK",
        "skipped  Global/NORTH CAROLINA",
        "skipped  Global/TEXAS",
        "skipped  Global/CALIFORNIA/San Jose",
        "skipped  Global/NEW YORK/New York",
        "skipped  Global/NORTH CAROLINA/Durham",
        "skipped  Global/TEXAS/Richardson",
        "skipped  Global/CALIFORNIA/San Jose/DC-Site-10",
        "skipped  Global/NEW YORK/New York/DC-Site-11",
        "skipped  Global/NORTH CAROLINA/Durham/Site-105",
        "skipped  Global/TEXAS/Richardson/Site-106",
        "skipped  Global/CALIFORNIA/San Jose/DC-Site-10/MAIN",
        "skipped  Global/NEW YORK/New York/DC-Site-11/MAIN",
        "skipped  Global/NORTH CAROLINA/Durham/Site-105/MAIN",
        "skipped  Global/TEXAS/Richardson/Site-106/MAIN"
    ]
}
```

Play recap should show `changed=0`. The play still built `site_id_map` for
later stages. `created` / `updated` appear only if a path is missing or an
UPDATE actually changed CatC (`-e site_hierarchy_update_existing=true`).

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
| `collections/requirements.yml` | The script server — ansible-core 2.17 |
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
| `Cannot reach 198.18.134.12:22` when connecting | VPN down, or the pod is still booting | Reconnect Cisco Secure Client and wait a few minutes |
| Hang or `Connection timed out` on `cat-center.corp.pseudoco.com` or `198.18.128.22–24` | Same — the VPN dropped mid-run | Reconnect, then re-run the stage |
| `Name or service not known` for `corp.pseudoco.com` names | Lab DNS not first in `/etc/resolv.conf` | Re-run `01_bootstrap_script_server.yml` |
| `Lab access vault not found. Expected Lab Topology/lab_access.yml above …` | You ran from outside the repo tree | `cd` into `evpn/ansible` first |
| `Decryption failed` on any playbook | `.vault` content ≠ the passphrase the file was encrypted with | Rewrite `.vault` on the script server (Step 3) and re-run `00_preflight.yml` to confirm |
| `Attempting to decrypt but no vault secrets found` | `.vault` missing at the repository root | Create it — Step 3. `00_preflight.yml` reports this before anything is changed |
| `This collection now runs ON the script server` | You ran collection `00` on your laptop | SSH to `198.18.134.12` and run it from the checkout there |
| `must decrypt to a mapping with a top-level lab_access key` | `lab_access.yml` was re-created without its `lab_access:` root key | Rebuild it from `lab_access.yml.example` and re-encrypt |
| `ansible-playbook: not found` in a non-interactive SSH command | Non-login shells do not pick up `~/venv` from `.bashrc` | Use an interactive SSH session, or call `/home/cisco/venv/bin/ansible-playbook` |
| `02_sync_from_git.yml` fails on local changes | The tree is dirty from ad-hoc file edits | Commit or revert them, then re-run |
| Stage 01 fails `[400] NCND00067: The request body is invalid` on an area CREATE | `cisco.catalystcenter` below 2.4.0 — `parentId` is sent empty | `ansible-galaxy collection install cisco.catalystcenter:2.10.2 --force` |
| `lab_pod_id` is still `REPLACE_ME` (or not a positive integer) | Step 6 was skipped | Edit `inventory/group_vars/all/lab.yml` or pass `-e lab_pod_id=<n>` |
| Stage 07 asserts on an SSID name still containing `{` | The `{POD}` placeholder was edited out of `settings.json` | Restore the placeholder — the pod number belongs in `lab.yml`, not in `settings.json` |
| `Collection <name> does not support Ansible version 2.15.x` | Collections from `requirements.yml` installed on a 2.15 host | Use `requirements-jumphost.yml` there |

---

## Reference — where everything lives

One tree, on the script server. You clone it and create `.vault` inside it; the
virtualenv lives outside the tree at `~/venv`.

```
~/cisco-one-experience-lab-automation/
├── .vault                                  # passphrase (gitignored). You create it on this host.
├── Lab Topology/
│   ├── lab_access.yml                      # encrypted credential map (committed)
│   └── PseudoCo_Lab_Access_Lookup.md       # host and URL index, no passwords
└── ansible-automation/
    ├── requirements.txt                     # pins used by stage-script-server.sh
    ├── plugins/vars/lab_access.py          # injects lab_access into every play
    ├── 00_scriptserver_bootstrap/          # runs locally: preflight / bootstrap / git sync
    │   ├── stage-script-server.sh          # base packages + ~/venv (run this first)
    │   └── playbooks/                      # 00_preflight, 01_bootstrap, 02_sync
    └── 01_campus/evpn/
        ├── Catalyst Center Templates/      # DEFN / FUNC / FABRIC .j2
        ├── Settings/settings.json          # single source of truth for stages 01–09
        └── ansible/                        # ← on Kali, run every pipeline command from here
            ├── ansible.cfg
            ├── inventory/
            │   ├── static_inventory.yml
            │   └── group_vars/all/lab.yml  # your POD number and AP MACs
            └── playbooks/                  # 01–10 stages

~/venv/                                     # Kali Ansible venv (on PATH)
```
