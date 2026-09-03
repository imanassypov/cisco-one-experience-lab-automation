# Ansible CI/CD Pipeline

> Vendored into PseudoCo `01_campus/evpn`. Operator entry point is the parent
> [evpn README](../README.md). Run from this directory on the Kali script
> server (`~/venv`). CatC login is Vault-only.

Single Ansible project for Catalyst Center provisioning (stages 1–9) plus fabric verification (stage 10). All automation runs from this directory.

## Setup

First-time setup — VPN, vault password, script server bootstrap, and your POD number — lives in one place: **[GETTING_STARTED.md](GETTING_STARTED.md)**. Follow it once per pod, then come back here for the playbook reference.

Already set up? On the Kali script server, Ansible is on `PATH` from `~/venv`; every session just needs the project directory. There is nothing to activate or export.

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/01_campus/evpn/ansible
```

Every credential — the Catalyst Center API login and the stage 10 switch logins alike — comes from `lab_access` in `Lab Topology/lab_access.yml`, which the vars plugin `ansible-automation/plugins/vars/lab_access.py` injects into each play. The repo-root `.vault` unlocks it. There is no group `vault.yml` in this collection.

### Collection requirements files

| File | Target environment | Notes |
|------|--------------------|-------|
| `collections/requirements.yml` | The Kali script server and the Mac — ansible-core 2.17.14 | Current releases |
| `collections/requirements-jumphost.yml` | A Python 3.9 host — ansible-core 2.15 | Newest release of each collection that still declares `requires_ansible: >=2.15` |

Python 3.9 caps ansible-core at 2.15, so such a host cannot run the 2.16+ collection releases. Installing the wrong file produces `Collection <name> does not support Ansible version 2.15.x` for every 2.16-only collection. `01_bootstrap_script_server.yml` installs its own pins into `~/venv`, so on Kali you normally never run `ansible-galaxy` by hand.

`cisco.catalystcenter` is pinned at **2.10.2** (requires ansible-core >= 2.16). Every role reads `catalystcenter_response`, a key 2.4.0 introduced; do not drop below 2.4.0. This lab’s Catalyst Center appliance is **3.1.5**; the SDK API profile is **3.1.3.0** (see `inventory/group_vars/catalyst_center/connection.yml`).

## Layout

```
01_campus/evpn/
├── Catalyst Center Templates/   # DEFN / FUNC / FABRIC .j2
├── Settings/settings.json       # SSOT for all stages
└── ansible/
    ├── GETTING_STARTED.md       # first-time setup (students start here)
    ├── inventory/               # static_inventory.yml + group_vars
    ├── playbooks/               # 00_site_deploy orchestrator, 01–10 stages
    ├── roles/                   # site_hierarchy, template_sync, network_profile, provision_devices, …
    └── evidence/                # stage 10 output (gitignored)
```

## Pipeline Order

Full orchestrator (stages 1–9, excludes verification):

```bash
ansible-playbook playbooks/00_site_deploy.yml
```

| Playbook | Stage | Description |
|----------|-------|-------------|
| `00_site_deploy.yml` | 0 | Orchestrator — imports stages 1–9 |
| `01_site_hierarchy.yml` | 1 | Build site hierarchy |
| `02_network_settings.yml` | 2 | Apply network settings |
| `03_credentials.yml` | 3 | CLI/SNMP/NETCONF credentials |
| `04_device_discovery.yml` | 4 | Device discovery |
| `05_assign_to_site.yml` | 5 | Assign devices to sites |
| `06_template_sync.yml` | 6 | Template sync from GitHub or a local directory |
| `07_network_profile.yml` | 7 | Network profiles (switching, wireless design, wireless) |
| `08_provision_devices.yml` | 8 | Device provisioning (wired, then wireless controllers) |
| `09_deploy_composite.yml` | 9 | Composite template deploy |
| `10_verify_collect_facts.yml` | 10 | Collect show-command evidence from the fabric |

### Playbook annotation convention

Every playbook and role task file opens with a boxed header block. Read it
first — it is the fastest way to understand a stage without tracing the role.

```yaml
---
# =============================================================================
# <filename>  —  Pipeline stage <NN>
# =============================================================================
# What the stage does and why it exists.
#
# Sourced:
#   settings.json → settings_data.project[]: <exact keys consumed>
#   connection.yml / vault.yml: <exact vars consumed>
#
# Produced:
#   <exact facts set, with example values>
#   In Catalyst Center: <objects created or changed>
#
# Depends on: <prior stages>
# Module: <collection module driven via module_defaults>
#
# Run: ansible-playbook playbooks/<filename>
# =============================================================================
```

Rules:

- `Sourced:` / `Produced:` must name **real** variables and nested key paths, with example values — never a vague summary.
- Playbooks that reload devices or bounce APs are marked `*DISRUPTIVE*` on the title line.
- Multi-play files get a `# ── Play N: … ──` divider above each play.
- Inline `# ── section ── ` dividers separate logical blocks inside role task files.

### Data-manipulation task annotation

Any task that transforms data — `set_fact`, `json_query`, accumulator loops,
payload assembly — carries an `Example` block directly above it showing the
payload going **in** and the payload coming **out**:

```yaml
# Example — <scoping note, e.g. "single project entry, rollback image defined">
#   In : <var> = {
#          "key": "value"
#        }
#   Out: <var> = [
#          { "key": "value" }
#        ]
# <one or two lines stating what the filters did and why>
- name: <task name>
  ansible.builtin.set_fact:
```

Rules:

- **No elisions.** Never write `…`, `...`, or `and so on` inside an example
  data structure. Every key and every value is written out in full, including
  long image filenames, all six device IPs, and complete UUIDs. A reader must
  be able to copy the example into a scratch playbook and get the documented
  result.
- Values come from the **real** `Settings/settings.json` and
  `inventory/group_vars/catalyst_center/connection.yml` — not invented data.
- Where a task has branching outcomes (create vs update vs no-op), give one
  complete `In:`/`Out:` pair **per branch** and state which tasks fire.
- Opaque secrets (auth tokens, Git PATs, blob SHAs) use a complete
  well-formed literal of the right shape, never a truncated one.
- The trailing note explains the non-obvious filter behaviour — deduplication,
  `select('mapping')` guards, keys that get dropped, type coercions — not what
  the next line already says.

Coverage is complete: every data-manipulation task under `roles/*/tasks/` carries
an `Example` block. `defaults/` and `handlers/` are excluded by design — they hold
flat data and hook declarations with no transformation to document. When you add a
new `set_fact` or payload-assembly task, add its `Example` block in the same commit.

### Task naming convention

`ansible-lint`'s `name[template]` rule requires that a task name contain **at most one
Jinja expression, positioned at the very end**. The static leading text is what Ansible
callbacks, log aggregation and `--start-at-task` key off, so it must be stable across
loop iterations.

```yaml
# ✅ correct — static text first, one trailing template
- name: "Assert composite template found | {{ deploy_entry.template_name }}"
- name: "Resolve site UUID | {{ site_entry.key }}"

# ❌ violates name[template] — template leads the name
- name: "[{{ deploy_entry.template_name }}] Assert composite template found"

# ❌ violates name[template] — two templates separated by static text
- name: "Derive path | {{ _parent }}/{{ _name }}"
# ✅ fix — concatenate into a single expression
- name: "Derive path | {{ _parent ~ '/' ~ _name }}"

# ❌ violates name[template] — counts/state embedded mid-name
- name: "Phase B — Create/update sites ({{ site_configs_list | length }} total)"
# ✅ fix — keep the name static, report the count from the task's own output
- name: "Phase B — Create/update sites"
```

Rules:

- Loop-variable suffixes stay — they are the only thing disambiguating otherwise
  identical banners across iterations. They just move to the end after a ` | ` separator.
- Counts, states and derived values never belong in a name. Move them into the
  `debug`/`assert` message of the same task, where they are already visible.
- Lint rules the project deliberately suppresses live in
  [`.ansible-lint`](../../.ansible-lint) at the repository root — one file shared by
  the CLI and the VS Code Ansible extension, which lints from the workspace root.
  `name[template]` is **not** among them — fix violations rather than skipping the rule.

### Template sync (stage 6)

`06_template_sync.yml` reads the `.j2` templates and the composite YAML from one of two sources, selected by `template_source` in `inventory/group_vars/catalyst_center/connection.yml`. Both sources produce the same fact — `repo_tree_entries`, a list of `{path: <root-relative path>}` — so everything downstream (ordering, composite parsing, the `template_workflow_manager` payload) is identical either way.

| `template_source` | Reads from | Auth | Commit metadata | Diff header |
|---|---|---|---|---|
| `git` (default) | GitHub REST API on `git_repo` / `git_branch` | `git_token` (vault) — optional for public repos, lifts the 60 req/hr anonymous limit | Real commit message, author, SHA | Honours `include_diff_header` |
| `local` | `template_local_root` on the machine running Ansible | none | Synthesised `Synced from local directory <date> <time>` | Always off — there is no commit to diff |

```bash
ansible-playbook playbooks/06_template_sync.yml                          # GitHub
ansible-playbook playbooks/06_template_sync.yml -e template_source=local  # this working tree
ansible-playbook playbooks/06_template_sync.yml -e template_source=local \
  -e template_local_root=/abs/path/to/templates
```

| Variable | Default | Description |
|---|---|---|
| `template_source` | `git` in the role; **`local`** in `connection.yml` | `git` or `local`. Any other value fails the run immediately. |
| `template_local_root` | `evpn/` (derived from `playbook_dir`) | Directory the `local` source scans. Must exist and be a directory. |
| `git_repo_subfolders[].path` | see `connection.yml` | Relative to the repo root (`git`) **or** to `template_local_root` (`local`) — one list drives both. |
| `git_repo_subfolders[].project_name` | see `connection.yml` | Catalyst Center Template Programmer project each subfolder syncs into. |

**How the `template_local_root` default resolves.** `playbook_dir` is `<repo>/ansible-automation/01_campus/evpn/ansible/playbooks`, so the two `dirname` calls in `template_local_root: "{{ playbook_dir | dirname | dirname }}"` walk up to `evpn/`, which is the folder holding the vendored `Catalyst Center Templates/` tree:

| Step | Value |
|---|---|
| `playbook_dir` | `<repo>/…/evpn/ansible/playbooks` |
| `\| dirname` | `<repo>/…/evpn/ansible` |
| `\| dirname` | `<repo>/…/evpn` ← `template_local_root` |

The default therefore points at whichever clone the playbook is running from, with no absolute path hard-coded. Move `06_template_sync.yml` to a different directory depth and this expression must be adjusted, or `template_local_root` set explicitly. Note that `playbook_dir` only equals `playbooks/` under `ansible-playbook` — an ad-hoc `ansible ... -m debug -a var=template_local_root` sets it to the cwd and so reports a path one level too high.

Only the directories named in `git_repo_subfolders` are scanned in `local` mode — a recursive walk of the whole root would descend into `.git` and `.venv`, whose `.yml`/`.j2` files are noise. A subfolder with no `.j2` files logs a warning and is skipped.

File contents are read with `slurp` + `b64decode` rather than the `file` lookup, so bytes — including trailing newlines — match what the Git path produces.

`local` mode still requires a reachable Catalyst Center and the `dnacentersdk` Python package in the interpreter running the play; only the *source* of the template text changes.

## Inventory layout

`ansible.cfg` points Ansible at a single static file — there is no dynamic
inventory plugin and nothing contacts CML:

```ini
inventory = inventory/static_inventory.yml
```

| File | Purpose |
|------|---------|
| `inventory/static_inventory.yml` | Catalyst Center API endpoint (`localhost`) and the three Site 105 EVPN switches |
| `inventory/group_vars/all/` | `lab.yml` — per-student `lab_pod_id` and `lab_ap_macs` |
| `inventory/group_vars/catalyst_center/` | `connection.yml` plus the vault holding CatC credentials |

Two groups exist. Stages `01`–`09` target `catalyst_center`, which is
`localhost` talking to the Catalyst Center REST API. Stage `10` targets
`campus_evpn`, whose `evpn_leaves` and `evpn_border_spine` children are the
three fabric switches reached over SSH at `198.18.128.22–24`; their credentials
come from `lab_access[inventory_hostname]` in the vault.

```bash
ansible-inventory --graph
```

### Fabric verification

Stage 10 is the only playbook that logs into the switches. It runs
`ios_command` against `campus_evpn` and writes the output under `evidence/`,
which is gitignored. It reads state and changes nothing.

```bash
ansible-playbook playbooks/10_verify_collect_facts.yml
ansible-playbook playbooks/10_verify_collect_facts.yml --limit evpn_leaves
```

Reaching the switches requires the dCloud VPN to be up. A hang or
`Connection timed out` on `198.18.128.22–24` almost always means the VPN
dropped, not that the fabric is broken.

## Common Overrides

```bash
DEBUG=true ansible-playbook playbooks/04_device_discovery.yml
ansible-playbook playbooks/01_site_hierarchy.yml -e state=deleted
ansible-playbook playbooks/06_template_sync.yml -e template_source=local
ansible-playbook playbooks/08_provision_devices.yml -e wireless_provision_enabled=false
ansible-playbook playbooks/07_network_profile.yml -e lab_pod_id=7
```

Role task files include pre/post data structure comments for each API interaction.
