# Campus EVPN automation — student lab guide

This Ansible project builds the PseudoCo campus EVPN/VXLAN lab through
Catalyst Center. Ansible does not directly configure the switches during
stages 01–08. Instead, it creates the design objects Catalyst Center needs,
discovers and provisions the devices, and asks Catalyst Center to render the
fabric configuration from Jinja templates.

Run the playbooks in numerical order:

1. Create or confirm the site hierarchy.
2. Apply site network settings.
3. Create and assign device credentials.
4. Discover the WLC and campus switches.
5. Assign discovered devices to sites.
6. Sync EVPN Jinja into a Catalyst Center CLI project (local folder or GitHub).
7. Create switching and wireless network profiles.
8. Provision the switches, WLC, and access points.
9. Deploy the EVPN composite template to the switches.
10. SSH to the switches and collect read-only verification evidence.

Stages 01–09 use the Catalyst Center API. Stage 10 is the only playbook that
logs in to the switches.

## Before you begin

Complete [GETTING_STARTED.md](GETTING_STARTED.md) first. In particular:

- Connect the student laptop to the dCloud VPN.
- Run collection `00_scriptserver_bootstrap` from the laptop. It prepares Kali
  with Python, Ansible, Cisco collections, SDKs, lab DNS, the Git checkout, and
  a copy of the demo `.vault`.
- SSH to Kali. All commands below run there, not on the student laptop.
- Set `lab_pod_id` and `lab_ap_macs` in
  `inventory/group_vars/all/lab.yml`. The committed pod value is
  `REPLACE_ME`; stages that load `settings.json` stop until you replace it.
- Run every command from this directory so Ansible finds `ansible.cfg`:

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/01_campus/evpn/ansible
```

Confirm the inventory before making changes:

```bash
ansible-inventory --graph
```

You should see `catalyst_center_api` and the three Site 105 switches. The empty
`@ungrouped` group is normal.

## What supplies the data

The main data source is `../Settings/settings.json`. Its four `project[]`
entries describe:

- DC-Site-10 in San Jose
- DC-Site-11 in New York
- Site-105 in Durham
- Site-106 in Richardson

Each playbook reads only the sections it needs. For example, stage 02 reads
`network_settings`, stage 04 reads `discovery`, and stage 07 reads
`network_profile`, `wireless_design`, and `wireless_profile`.

Other inputs are:

- `inventory/group_vars/catalyst_center/connection.yml` — Catalyst Center
  hostname, API version, template source, and operational defaults.
- `inventory/group_vars/all/lab.yml` — the student's pod number and AP Ethernet
  MAC addresses.
- `Lab Topology/lab_access.yml` — vault-encrypted API and SSH credentials,
  loaded by the repository vars plugin.
- `../Catalyst Center Templates/` — the DEFN, FUNC, FABRIC, and composite Jinja
  templates synchronized in stage 06.

The pod number is not an IP address or site identifier. It is used only to
render the student WLAN name `PSEUDOCO-PODnn`; for example, pod 7 becomes
`PSEUDOCO-POD07`.

## Safety labels

- **Read-only** — does not change Catalyst Center or a device.
- **Design change** — changes Catalyst Center intent, but does not immediately
  push switch CLI.
- **Potentially disruptive** — may reprovision devices or reboot APs.
- **Disruptive** — pushes rendered configuration to switches.

Do not use `-e state=deleted`, `-e force_reprovision=true`, or other force
options unless the lab instructions explicitly call for them.

---

## Stage 01 — Site hierarchy

**Playbook:** `playbooks/01_site_hierarchy.yml`
**Safety:** Design change; normally an idempotent no-op on stock dCloud.

### What it accomplishes

This stage creates or confirms the geographic hierarchy used by all later
stages:

```text
Global
└── State
    └── City
        └── Building
            └── MAIN
```

It manages four state, city, building, and floor branches — 16 paths in total.
Later playbooks resolve sites by these exact paths, so stage 01 must run first.

### Data read from settings.json

For every `project[]` entry:

- `HierarchyParent`
- `HierarchyArea`
- `HierarchyBldg`
- `HierarchyFloor`
- `HierarchyBldgAddress`
- `HierarchyBldgCountry`
- `HierarchyBldgLatitude`
- `HierarchyBldgLongitude`

Floor RF model and dimensions come from defaults in `connection.yml` because
the current JSON does not set them.

### Catalyst Center APIs

- `GET /dna/intent/api/v1/sites` — read the existing hierarchy.
- `POST /dna/intent/api/v1/areas` — create a missing state or city.
- `POST /dna/intent/api/v2/buildings` — create a missing building.
- `POST /dna/intent/api/v2/floors` — create a missing floor.
- `GET /dna/intent/api/v1/sites?nameHierarchy=<path>` — resolve a newly
  created site's UUID.
- `PUT` to the corresponding area, building, or floor endpoint — update an
  existing object when updates are enabled.

Building and floor updates are disabled by default because of a known
collection/SDK issue. Missing objects are still created.

### Run it

```bash
ansible-playbook playbooks/01_site_hierarchy.yml
```

### Important expected output

The dCloud appliance already has this hierarchy. A normal run therefore ends:

```text
TASK [site_hierarchy : Site hierarchy provisioning complete]
"Created 0, updated 0, skipped 16"
"skipped  Global/CALIFORNIA"
"skipped  Global/NEW YORK"
...
"skipped  Global/TEXAS/Richardson/Site-106/MAIN"

PLAY RECAP
catalyst_center_api : changed=0 failed=0
```

`skipped 16` is success, not a failure. The stage still resolved all site UUIDs.

### Where to verify in Catalyst Center

Open **Design > Network Hierarchy**. Expand each branch and confirm:

- California > San Jose > DC-Site-10 > MAIN
- New York > New York > DC-Site-11 > MAIN
- North Carolina > Durham > Site-105 > MAIN
- Texas > Richardson > Site-106 > MAIN

On stock dCloud, expect no visible change because these paths already exist.

---

## Stage 02 — Network settings

**Playbook:** `playbooks/02_network_settings.yml`
**Safety:** Design change; submits all four site settings on every run.

### What it accomplishes

This stage attaches common network services to each `MAIN` floor. Catalyst
Center stores these as site intent. Devices pick them up when they are
provisioned in stage 08; this stage does not change switch CLI.

That is **not** the same as the Design UI badge **Inherited from Global**.
See the callout below: DHCP, DNS domain, and ISE at `MAIN` stay inherited
on stock dCloud because they already match Global.

### Data read from settings.json

The target path comes from the four `Hierarchy*` fields. The payload comes from
`project[].network_settings`:

- `dhcp_server`
- `dns_server`
- `ntp_server`
- `timezone`
- `message_of_the_day`
- `snmp_server`
- `syslog_server`
- `netflow_server`
- `network_aaa`
- `client_and_endpoint_aaa`

The current settings apply:

- DHCP, DNS, and NTP server `198.18.5.102`
- DNS domain `corp.pseudoco.com`
- Site-specific timezones and banners
- SNMP and syslog collectors
- NetFlow collector and UDP port
- Client/endpoint RADIUS intent pointing to ISE
- No network-device AAA because `network_aaa` is `null`

### Catalyst Center APIs

- `POST /dna/system/api/v1/auth/token` — authenticate.
- `GET /dna/intent/api/v1/sites` — resolve site UUIDs.
- `PUT /dna/intent/api/v1/network/{siteId}` — apply the composite settings.
- `GET {executionStatusUrl}` — wait for each asynchronous task to report
  `SUCCESS` or `FAILURE`.

The composite PUT is intentional; it avoids an appliance error when
client/endpoint AAA is supplied without network AAA.

### Run it

```bash
ansible-playbook playbooks/02_network_settings.yml
```

### Important expected output

Verified on Kali against stock dCloud CatC (2026-09-15): four MAIN floors,
`failed=0`, `changed=0`.

```text
Settings data loaded — 4 entries found.
4 site(s) have settings to apply.

Site ID resolved: <uuid>   # DC-Site-10/MAIN
Site ID resolved: <uuid>   # DC-Site-11/MAIN
Site ID resolved: <uuid>   # Site-105/MAIN
Site ID resolved: <uuid>   # Site-106/MAIN

FAILED - RETRYING: ... Poll execution status | <site> (12 retries left).
Network settings successfully applied for 'Global/CALIFORNIA/San Jose/DC-Site-10/MAIN'.
Network settings successfully applied for 'Global/NEW YORK/New York/DC-Site-11/MAIN'.
Network settings successfully applied for 'Global/NORTH CAROLINA/Durham/Site-105/MAIN'.
Network settings successfully applied for 'Global/TEXAS/Richardson/Site-106/MAIN'.

Network settings applied successfully
Sites configured: Global/CALIFORNIA/San Jose/DC-Site-10/MAIN, ...

PLAY RECAP
catalyst_center_api : ok=39  changed=0  failed=0  skipped=23
```

`FAILED - RETRYING` is **not** a play failure. CatC accepts the PUT with HTTP
202 and the role polls until status is SUCCESS or FAILURE. While the job is
still IN_PROGRESS, Ansible prints that banner and waits (5 seconds, up to 12
tries). The first site (DC-Site-10) often takes several retries; the next three
usually succeed on the first or second poll.

`changed=0` is also expected: the `uri` PUT plus poll is recorded as `ok`, not
`changed`. Success is every assert saying settings were applied and recap
`failed=0`.

DEBUG tasks are skipped unless you pass `-e catc_debug=true`.

### CatC UX: “Inherited from Global” is success

Do **not** treat a lock or **Inherited from Global** on Domain Name (or
DHCP/DNS/NTP/ISE) at a `MAIN` floor as a failed apply.

CatC Design settings cascade down the hierarchy. `PUT /dna/intent/api/v1/network/{siteId}`
against a floor only stores a **local override** when the value **differs**
from the parent. If the value matches Global, CatC keeps inheritance. Cisco
documents matching the parent as the way to **remove** a site override.

Stock dCloud already has these at **Global**, and every `project[].network_settings`
row repeats them:

| Setting | Value at Global and at every MAIN |
| --- | --- |
| DHCP / DNS / NTP | `198.18.5.102` |
| DNS domain | `corp.pseudoco.com` |
| Client/endpoint AAA | ISE `198.18.5.101` |

Selecting `Global/NEW YORK/New York/DC-Site-11/MAIN` (or any other MAIN) and
seeing Domain Name `corp.pseudoco.com` with **Inherited from Global** means
the effective setting is correct. Stage 02 still PUTs those fields (the play
reported SUCCESS); CatC simply has nothing unique to store at the floor.

**Local (not inherited)** at MAIN are the fields that actually differ per
site in `settings.json`:

| Site | Timezone | MOTD banner (prefix) |
| --- | --- | --- |
| DC-Site-10/MAIN | `America/Los_Angeles` | PseudoCo HQ DC-Site-10 |
| DC-Site-11/MAIN | `America/New_York` | PseudoCo Remote DC-Site-11 |
| Site-105/MAIN | `America/New_York` | PseudoCo Campus Site-105 EVPN |
| Site-106/MAIN | `America/Chicago` | PseudoCo Branch Site-106 |

Compare **Global** vs **MAIN** on **Design > Network Settings > Servers**:
domain and DHCP should match; timezone and banner should not (unless Global
was already set to that timezone).

### Where to verify in Catalyst Center

Open **Design > Network Settings > Servers**, select each `MAIN` floor, then
the **Telemetry** tab for SNMP, syslog, and NetFlow. Confirm the tables above,
not that every lock icon is gone.

Do not expect switch running configuration to change yet.

---

## Stage 03 — Device credentials

**Playbook:** `playbooks/03_credentials.yml`
**Safety:** Design change. Deletion mode would remove shared global credentials.

### What it accomplishes

This stage makes sure Catalyst Center has the global credentials it needs to
manage devices, then assigns CLI, SNMP, and HTTP(S) credentials to each
`MAIN` floor. NETCONF port 830 is reconciled separately.

Phase A **GETs first** (`HTTP_READ` / `HTTP_WRITE` and the CLI/SNMP subtypes)
only to list descriptions already in Design. The workflow manager still does
the create and the site bind. We skip putting a type in
`global_credential_details` when its description is already present so this
lab **binds** `HTTPS Read` / `HTTPS Write` (and `CLI Admin`, SNMP) instead of
POSTing a second global with the same label. Discovery in stage 04 looks up
those names; a duplicate description would break that lookup. The GET is also
how four identical `project[]` rows become **one** create payload, not four.

### Data read from settings.json

From `project[].device_credentials`:

- `cli_credential` — description, username, password, enable password
- `snmp_v2c_read` — description and read community
- `snmp_v2c_write` — description and write community
- `https_read` — description, username, password, port (443)
- `https_write` — description, username, password, port (443)
- `netconf_credential` — description and port

From `project[].assign_credentials`:

- `site_name` — site paths that receive the CLI/SNMP/HTTP credential assignment

Repeated global credentials are deduplicated by description before processing.
Stage 04 discovery refers to the same descriptions (`HTTPS Read`, `HTTPS Write`).

### Catalyst Center APIs

The `cisco.dnac.device_credential_workflow_manager` handles CLI, SNMP, and
HTTP(S) reads, creates, updates, and site assignments, including:

- `GET /dna/intent/api/v1/global-credential` (`CLI`, `SNMPV2_*`, `HTTP_READ`,
  `HTTP_WRITE`)
- `POST` or `PUT /dna/intent/api/v2/global-credential`
- `GET /dna/intent/api/v1/sites/{id}/deviceCredentials`
- `POST /dna/intent/api/v1/sites/{id}/deviceCredentials`

NETCONF uses:

- `POST /dna/system/api/v1/auth/token`
- `GET /dna/intent/api/v1/global-credential?credentialSubType=NETCONF`
- `POST` or `PUT /dna/intent/api/v1/global-credential/netconf`
- `GET /dna/intent/api/v1/task/{taskId}` — poll completion

CLI/SNMP/HTTP go through `device_credential_workflow_manager`. That module
**has no NETCONF type**, so Phase A cannot create port 830. There is a
separate `cisco.dnac.netconf_credential` module, but CatC's create/update
calls return **HTTP 202** with a task id, and that module does not handle
that async body correctly (it treats the job as finished or errors). Stage 03
therefore uses `uri` for POST/PUT and polls the task itself.

Reads still use `cisco.dnac.global_credential_info`. Existence is keyed by
**port**, not description: CatC allows only one NETCONF credential per port,
and stock dCloud already owns 830 as `defaultNetConfPort`. A description-only
create would hit "Duplicate credential".

### Run it

```bash
ansible-playbook playbooks/03_credentials.yml
```

### Important expected output

Verified on Kali against stock dCloud CatC (2026-09-15): `failed=0`,
`changed=1` (Phase A workflow manager only).

```text
4 site assignment(s), 0 missing global type(s), state=merged
1 total: ['defaultNetConfPort']
changed: [catalyst_center_api]   # Phase A — Manage CLI, SNMP, and HTTP credentials

1 existing: {'830': {'id': '...', 'description': 'defaultNetConfPort'}}
NETCONF credential 'defaultNetConfPort' (port 830) already exists with matching description — no action needed.

Successfully provisioned 4 CLI/SNMP/HTTP site assignment(s)

PLAY RECAP
catalyst_center_api : ok=29  changed=1  failed=0  skipped=21
```

`0 missing global type(s)` is the expected stock-dCloud result: all five WFM
descriptions (`CLI Admin`, `SNMPv2c Read`, `SNMPv2c Write`, `HTTPS Read`,
`HTTPS Write`) were already in the GET-by-subtype lists, so Phase A only
**assigns** them and creates nothing. A non-zero count means that many
descriptions were absent and were created before being assigned. Pass
`-e catc_debug=true` to print `wfm_config` if you need to see which type it was.

NETCONF CREATE/UPDATE and Phase C delete are skipped when port 830 already
exists as `defaultNetConfPort` and `state=merged`.

A later re-run may show `0 missing global type(s)` and still `changed=1` if
the workflow manager re-applies site assignments. Success is recap `failed=0`
and the four-site complete message, not `changed=0`.

### Where to verify in Catalyst Center

Open **Design > Network Settings > Device Credentials** and confirm these
global objects exist:

- CLI Admin
- SNMPv2c Read
- SNMPv2c Write
- HTTPS Read
- HTTPS Write
- defaultNetConfPort (830)

Select each `MAIN` floor and confirm CLI, SNMP, and HTTP credentials are assigned.

---

## Stage 04 — Device discovery

**Playbook:** `playbooks/04_device_discovery.yml`
**Safety:** Design/inventory change. Re-running replaces same-named discovery
jobs and removes their old history.

### What it accomplishes

This stage asks Catalyst Center to contact and inventory the WLC and the
three Site-105 switches. DC-Site-11 and Site-106 have no `discovery` block,
so they never get a job.

### What each job is

| Job | Range | NETCONF | Mgmt IP |
| --- | --- | --- | --- |
| `C9800-WLC` | `198.18.5.103` | on, port 830 | none / device IP |
| `Site-105-Discovery` | `172.30.255.1–3` | off | UseLoopBack |

Both jobs look up stage 03 globals by name: `CLI Admin`, `SNMPv2c Read` /
`SNMPv2c Write`, `HTTPS Read` / `HTTPS Write`.

### Data read from settings.json

For rows containing `project[].discovery`:

- `discovery_name`
- `discovery_type`
- `ip_address_list`
- `preferred_mgmt_ip_method`
- `protocol_order`
- `retry`
- `timeout`
- `enable_netconf` and `netconf_port`
- CLI, SNMP, and HTTP credential descriptions/usernames

Rows with an empty `device_list` and no discovery block do not create jobs.

### Catalyst Center APIs

The `cisco.dnac.discovery_workflow_manager` handles:

- `GET /dna/intent/api/v1/discovery/{startIndex}/{recordsToReturn}`
- `DELETE /dna/intent/api/v1/discovery/{id}` when a job name already exists
- `POST /dna/intent/api/v1/discovery`
- `GET /dna/intent/api/v1/task/{taskId}`
- `GET /dna/intent/api/v1/discovery/{id}/network-device`

### Run it

```bash
ansible-playbook playbooks/04_device_discovery.yml
```

### Important expected output

Verified on Kali against stock dCloud CatC (2026-09-15): `failed=0`,
`changed=1`.

```text
Settings data loaded — 4 entries found.
2 discovery task(s) to run.
changed: [catalyst_center_api] => (item=C9800-WLC)
changed: [catalyst_center_api] => (item=Site-105-Discovery)
Device discovery submitted successfully
Discovery tasks run: 2
C9800-WLC, Site-105-Discovery

PLAY RECAP
catalyst_center_api : ok=11  changed=1  failed=0  skipped=5
```

Four `project[]` rows load, but only two have a `discovery` block. DC-Site-11
and Site-106 have empty `device_list` and no job, so they never appear in the
loop. Recap `changed=1` is one looped `discovery_workflow_manager` task with
two items, not a single job.

The module **submits** the jobs (and waits on CatC's discovery task). Play
success is not the same as every IP being reachable. Re-running deletes any
existing job with the same name and starts a new one, which is why both items
report `changed` even when the devices are already in Inventory.

### Where to verify in Catalyst Center

Open **Tools > Discovery** and confirm:

- `C9800-WLC` is complete.
- `Site-105-Discovery` is complete.
- The result details show the expected devices as reachable.

Then open **Provision > Inventory**. Confirm the WLC and all three switches are
present. They may still be unassigned or under Global until stage 05.

---

## Stage 05 — Assign devices to sites

**Playbook:** `playbooks/05_assign_to_site.yml`
**Safety:** Inventory organization change; does not provision devices.

### What it accomplishes

This stage assigns discovered inventory devices to the correct floor.
DC-Site-11 and Site-106 have empty `device_list`, so they never appear.

### What each assignment is

| Site path | IPs |
| --- | --- |
| `Global/CALIFORNIA/San Jose/DC-Site-10/MAIN` | WLC `198.18.5.103` |
| `Global/NORTH CAROLINA/Durham/Site-105/MAIN` | Switch loopbacks `172.30.255.1`, `.2`, `.3` |

This does **not** provision devices and does **not** assign access points.

### Data read from settings.json

- `project[].device_list`
- `HierarchyParent`
- `HierarchyArea`
- `HierarchyBldg`
- `HierarchyFloor`

### Catalyst Center APIs

- `GET /dna/intent/api/v1/site?name=<full path>` — resolve the site UUID.
- `POST /dna/intent/api/v1/assign-device-to-site/{siteId}/device` — submit the
  assignment.

### Run it

```bash
ansible-playbook playbooks/05_assign_to_site.yml
```

### Important expected output

Verified on Kali against stock dCloud CatC (2026-09-15): `failed=0`,
`changed=0`.

```text
Settings data loaded — 4 entries found.
2 site(s) to assign devices to.
ok: [catalyst_center_api] => (item=Global/CALIFORNIA/San Jose/DC-Site-10/MAIN)
ok: [catalyst_center_api] => (item=Global/NORTH CAROLINA/Durham/Site-105/MAIN)
Device-to-site assignment submitted successfully
Sites processed: Global/CALIFORNIA/San Jose/DC-Site-10/MAIN, Global/NORTH CAROLINA/Durham/Site-105/MAIN

PLAY RECAP
catalyst_center_api : ok=12  changed=0  failed=0  skipped=6
```

Four `project[]` rows load; only two have a non-empty `device_list`. Recap
`changed=0` with `ok` on both assign items is success when the devices are
**already** at those floors (this lab after a previous 05 run). A first-time
assign may report `changed`. The play still prints “submitted successfully”
because the role does **not** poll CatC’s execution URL.

### Where to verify in Catalyst Center

Open **Provision > Inventory** and inspect the Site column or filter by site:

- The WLC should belong to DC-Site-10/MAIN.
- The three EVPN switches should belong to Site-105/MAIN.

This API assigns unassigned devices. It does not move a device already assigned
to the wrong site; correct that in CatC before proceeding.

---

## Stage 06 — Synchronize EVPN templates

**Playbook:** `playbooks/06_template_sync.yml`
**Safety:** Template design change; does not configure switches.

### What it accomplishes

This stage copies DEFN, FUNC, and FABRIC Jinja plus the composite YAML into
Catalyst Center **Tools > Template Hub**. It does **not** push CLI onto
switches; stage 09 later deploys the composite `BGP-EVPN-BUILD.j2`.

A **CLI project** is created if it does not already exist. This lab’s project
is named **Site-105**. Students should see that project after the first
successful run, with the regular templates and the composite inside it.

The playbook can read those files from **either** a local folder on the
machine running Ansible **or** a GitHub repository. GitHub may be public
(anonymous) or **private** (authenticated with a personal access token).
This lab defaults to the local vendored tree on Kali.

### One CLI project per campus site

EVPN templates are **per campus fabric**, not global. Each site has its own
hostnames, loopbacks, VRFs, L3OUT, and client ports in the DEFN files.
FABRIC templates `{% include %}` those helpers as
`{{ TEMPLATE_PROJECT_NAME }}/DEFN-….j2`, so DEFN, FUNC, FABRIC, and the
composite must live in the **same** CatC project.

Do not share one Template Hub project across two campus sites. A second
campus needs a **second folder of templates** and a **second CLI project**
(another `git_repo_subfolders` row with its own `path` and `project_name`).
This lab syncs only Site-105.

### How the CatC project name is derived

Each `git_repo_subfolders` row becomes one Template Hub **CLI** project.
The name is chosen in this order:

1. The row’s explicit `project_name` — **use this**. Lab value: `Site-105`.
2. If that key is missing or empty: the last segment of `path`
   (`Site BGP EVPN Templates`).
3. If `path` is also empty: the parent folder of the first `.j2` file.

`template_workflow_manager` **creates** the CLI project when the name is
new, or updates and versions templates when the project already exists.
Always set `project_name` so Hub names stay site IDs, not folder titles.

### How to choose and configure the source

Edit
`inventory/group_vars/catalyst_center/connection.yml`, or override any key
with `-e` on the command line. Stage 06 does **not** read `settings.json`.

| Variable | What it controls |
| --- | --- |
| `template_source` | `local` (scan a directory) or `git` (GitHub REST API). Lab default: `local`. |
| `template_local_root` | Root directory when `local`. Lab: `evpn/` (two dirnames up from `playbooks/`). |
| `git_repo` | `https://github.com/<org>/<repo>.git` when `git`. |
| `git_branch` | Branch to read (lab: `main`). |
| `git_repo_subfolders` | List of `{path, project_name}`. **Used for both local and git.** `path` is relative to `template_local_root` or the Git repo root. |
| `git_token` | Optional GitHub PAT for **private** repos (or to raise the anonymous rate limit). Unused when `local`. Never commit a token. |
| `template_extension` | File suffix to sync (lab: `j2`). |
| `include_diff_header` | If true and `git`, prepend commit-diff comments. Lab: `false`. |

**Local folder (this lab’s default).** Ansible finds `.j2` and composite YAML
under `template_local_root` + each `path`. No GitHub calls.

```yaml
template_source: local
template_local_root: "{{ playbook_dir | dirname | dirname }}"
git_repo_subfolders:
  - path: "Catalyst Center Templates/Site BGP EVPN Templates"
    project_name: "Site-105"
```

On Kali that folder is
`~/cisco-one-experience-lab-automation/ansible-automation/01_campus/evpn/Catalyst Center Templates/Site BGP EVPN Templates`.
To use another tree: `-e template_local_root=/path/to/evpn`.

**Public GitHub.** Set `template_source: git`. Keep `git_repo`, `git_branch`,
and `git_repo_subfolders`. Leave `git_token` unset. The role lists the tree
and fetches blobs from `api.github.com` (about 60 anonymous requests/hour).

```bash
ansible-playbook playbooks/06_template_sync.yml -e template_source=git
```

**Private GitHub.** Same as public, plus a token with classic `repo` scope or
fine-grained **Contents: Read**. Export it in the shell and pass it at
runtime (or a gitignored vault extra). Do **not** put a PAT in
`connection.yml` or this README:

```bash
export GITHUB_TOKEN=...   # your PAT; do not commit this
ansible-playbook playbooks/06_template_sync.yml \
  -e template_source=git \
  -e git_token="{{ lookup('env', 'GITHUB_TOKEN') }}"
```

HTTP 401 means a bad token; unset `git_token` for a public repo. HTTP 404
usually means a wrong `git_repo` / `git_branch`, or a private repo without a
token.

**Second campus site** (example only — add only when that site’s DEFNs exist):

```yaml
git_repo_subfolders:
  - path: "Catalyst Center Templates/Site BGP EVPN Templates"
    project_name: "Site-105"
  - path: "Catalyst Center Templates/Site 106 BGP EVPN Templates"
    project_name: "Site-106"
```

That creates (or updates) two CLI projects: **Site-105** and **Site-106**.

### Catalyst Center APIs

Writes use `cisco.dnac.template_workflow_manager`
(`/dna/intent/api/v1/template-programmer/`). That module creates the CLI
project if needed, then commits regular templates and the composite.

When `template_source=git`, the role also GETs GitHub
`/repos/{slug}`, `/branches/{branch}`, `/git/trees/{branch}?recursive=1`,
raw file URLs, and optionally commits. Local mode never calls GitHub.

### Run it

Lab default (local tree on Kali):

```bash
ansible-playbook playbooks/06_template_sync.yml
```

Force local, or point at another tree:

```bash
ansible-playbook playbooks/06_template_sync.yml -e template_source=local
ansible-playbook playbooks/06_template_sync.yml \
  -e template_source=local \
  -e template_local_root=/path/to/evpn
```

Read from GitHub instead:

```bash
ansible-playbook playbooks/06_template_sync.yml -e template_source=git
```

### Important expected output

Verified on Kali, `template_source=local` (2026-09-15): `failed=0`,
`changed=2`. Commit messages were `Synced from local directory 2026-09-15 17:19:50`.

```text
Subfolder synced: Catalyst Center Templates/Site BGP EVPN Templates
Project: Site-105
Regular templates synced: 24
Composite templates synced: 1

Template synchronization completed successfully
Projects synced: 1

PLAY RECAP
catalyst_center_api : ok=126  changed=2  failed=0  skipped=27
```

`changed=2` is the two `template_workflow_manager` calls (24 regular
templates, then composite `BGP-EVPN-BUILD.j2`). DEBUG tasks that print full
Jinja are skipped unless `-e catc_debug=true` — do not enable that on a shared
terminal; the output is huge.

A later run can still report `changed` when CatC commits a new version.
Success is recap `failed=0` and `Projects synced: 1` with project `Site-105`.

### Where to verify in Catalyst Center

Open **Tools > Template Hub** (Template Editor on some releases). A **CLI**
project named **Site-105** must exist (created on first sync if missing).
Inside it confirm:

- DEFN and FUNC helpers.
- FABRIC templates (24 regular files in this lab).
- Composite `BGP-EVPN-BUILD.j2` with the FABRIC members listed in
  `BGP-EVPN-BUILD.yml`.
- Catalyst 9300 among supported device types.

Uploading templates does not deploy them.

---

## Stage 07 — Network profiles and wireless design

**Playbook:** `playbooks/07_network_profile.yml`
**Safety:** Design change on a shared WLC. Verify `lab_pod_id` before running.

### What it accomplishes

This stage ties the design together:

- Creates/updates four switching network profiles.
- Assigns `BGP-EVPN-BUILD.j2` as the Site-105 Day-N template.
- Creates the student SSID `PSEUDOCO-PODnn`.
- Creates the wireless interfaces and FlexConnect design.
- Sets Site-105 FlexConnect native VLAN 10.
- Sets ISE AAA-override VLAN names Main, PROD, and IOT.
- Binds the SSID to Site-105/MAIN through wireless profile `HQ-Wireless`.

### Data read from settings.json

For switching:

- `project[].network_profile.profile_name`
- `project[].network_profile.DayNTemplateNames[].TemplateName`
- `project[].network_profile.Day0TemplateNames[].TemplateName`
- the hierarchy fields used to build target site paths

For wireless:

- `project[].wireless_design.interfaces`
- `project[].wireless_design.ssids`
- `project[].wireless_design.flex_connect_configuration`
- `project[].wireless_design.flex_connect_aaa_override`
- `project[].wireless_profile.profile_name`
- `project[].wireless_profile.site_names`
- `project[].wireless_profile.ssid_details`
- `project[].wireless_profile.additional_interfaces`

`{POD}` is replaced from `lab_pod_id`, zero-padded to two digits.

### Catalyst Center APIs

Workflow modules manage switching profiles, wireless design, and wireless
profiles:

- `cisco.dnac.network_profile_switching_workflow_manager`
- `cisco.dnac.wireless_design_workflow_manager`
- `cisco.dnac.network_profile_wireless_workflow_manager`

The role also directly calls:

- `POST /dna/system/api/v1/auth/token`
- `GET /dna/intent/api/v1/sites`
- `GET` and `PUT
  /dna/intent/api/v1/sites/{siteId}/wirelessSettings/flexConnectNativeVlan`
- `GET` and `PUT
  /dna/intent/api/v1/sites/{siteId}/wirelessSettings/flexConnectAaaOverride`
- returned execution-status URLs when CatC responds asynchronously

### Run it

```bash
ansible-playbook playbooks/07_network_profile.yml
```

For a one-time pod override:

```bash
ansible-playbook playbooks/07_network_profile.yml -e lab_pod_id=7
```

### Important expected output

```text
4 network profile(s) to create/update.
Switching network profile(s) created/updated successfully
SSID name 'PSEUDOCO-PODnn' resolved.
Wireless design object(s) created/updated successfully
FlexConnect native VLAN 10 ...
Wireless network profile(s) created/updated successfully
```

### Where to verify in Catalyst Center

Open **Design > Network Profiles > Switching**:

- Confirm `BGP-EVPN-Switching` is assigned to Site-105/MAIN.
- Confirm its Day-N template is `BGP-EVPN-BUILD.j2`.

Open the wireless design area under **Design > Network Settings**:

- Confirm SSID `PSEUDOCO-PODnn`.
- Confirm Enterprise WPA2/WPA3 and 802.1X settings.
- Confirm interfaces for Main, PROD, IOT, and the local VLAN.
- Confirm Site-105 FlexConnect native VLAN 10.
- Confirm AAA-override mappings Main=10, PROD=101, IOT=102.

Open **Design > Network Profiles > Wireless**:

- Confirm `HQ-Wireless` is assigned to Site-105/MAIN.
- Confirm it contains the student's SSID.

### Important shared-WLC warning

The wireless workflow uses merge behavior: it adds but does not prune an old
student SSID. Do not change pod numbers after deploying stage 07. A pod change
can leave the old SSID attached and make the profile update fail. Never delete
the stock dCloud SSID `PSEUDOCO-POD#`.

---

## Stage 08 — Provision devices

**Playbook:** `playbooks/08_provision_devices.yml`
**Safety:** **Potentially disruptive. WLC/AP changes can reboot APs.**

### What it accomplishes

Provisioning makes CatC apply the site settings and profiles created earlier.
This stage runs three passes:

1. Provision the three Site-105 switches.
2. Provision the WLC and its managed AP location.
3. Name, site-assign, and provision APs so CatC creates their policy, site, and
   RF tags.

Without the AP provision action, an AP can remain on default tags and fail to
broadcast the student SSID.

### Data read from settings.json

- `project[].device_list` and hierarchy fields
- `project[].wireless_controller.managed_ap_locations`
- `project[].wireless_controller.skip_ap_provision`
- `project[].wireless_controller.rolling_ap_upgrade`
- `project[].access_points[].mac_address`
- AP name, mode, location, floor/site, and optional RF profile

AP `{APn_MAC}` values come from `lab_ap_macs`. Enter the AP's **Ethernet MAC**,
not its radio MAC. Unresolved AP rows are skipped.

### Catalyst Center APIs

Wired provisioning:

- `GET /dna/intent/api/v1/site?name=<path>`
- `GET /dna/intent/api/v1/network-device?managementIpAddress=<ip>`
- `GET /dna/intent/api/v1/sda/provisionDevices`
- `POST /dna/intent/api/v1/sda/provisionDevices`
- `PUT /dna/intent/api/v1/sda/provisionDevices` only when forced
- `GET /dna/intent/api/v1/task/{taskId}`

WLC and AP handling uses CatC workflow modules plus:

- `GET /dna/intent/api/v1/network-device?family=Unified%20AP`
- `GET /dna/intent/api/v1/site-member/{siteId}/member`
- `GET
  /dna/intent/api/v1/wireless/accesspoint-configuration/summary?key=<MAC>`
- `GET /dna/intent/api/v1/wireless/rf-profile`
- `POST /dna/intent/api/v1/wirelessAccessPoints/provision`

The AP provision call requires `cisco.catalystcenter` 2.11.0 or newer and an RF
profile. This lab defaults to `TYPICAL`.

### Run it

Review the settings and AP MACs first, then:

```bash
ansible-playbook playbooks/08_provision_devices.yml
```

Do not add force flags during a normal student run.

### Important expected output

Healthy output includes summaries showing:

- Wired devices submitted or already provisioned.
- Wireless controller provisioned with its managed AP location.
- Unresolved AP token rows skipped.
- AP already in its site or newly assigned.
- AP `provisioningStatus` true, or a successful AP provision task.

The exact CatC task text varies. The play must end with `failed=0`.

### Where to verify in Catalyst Center

Open **Provision > Inventory**:

- Site-105 switches should show provisioned.
- The WLC should show provisioned under DC-Site-10/MAIN.
- The AP should have the expected name and provisioning status.

Inspect AP configuration/tags:

- Site tag should point at Site-105.
- Policy tag should map `PSEUDOCO-FLEX-Profile`.
- RF tag should be `TYPICAL` unless overridden.

An AP's `siteHierarchy` field or location can remain empty/default even after a
successful provision. Confirm membership from the site side and confirm the
tags. AP location is a separate CatC workflow.

### Disruption warning

Changing managed AP locations, assigning an AP to a new site, or reprovisioning
an AP can reboot it for several minutes. Wired devices are skipped when already
provisioned unless forced. AP provisioning is skipped when
`provisioningStatus` is already true unless forced.

---

## Stage 09 — Deploy the EVPN composite

**Playbook:** `playbooks/09_deploy_composite.yml`
**Safety:** **Disruptive. Pushes rendered CLI to the three fabric switches.**

### What it accomplishes

This is the stage that builds the live EVPN/VXLAN fabric. CatC renders
`BGP-EVPN-BUILD.j2` and copies the resulting VRF, VLAN, NVE, multicast, BGP
EVPN, overlay, NAC, and telemetry configuration to:

- `172.30.255.1` — Site_105-Leaf1
- `172.30.255.2` — Site_105-Leaf2
- `172.30.255.3` — Site_105-Border-Spine

### Data read from settings.json

From `project[].network_profile.DayNTemplateNames[]`:

- `TemplateName`
- `Project`
- `DeployTemplate`
- `TemplateTarget`
- `TemplateTag`

Only entries with `DeployTemplate: true` and a template name are queued. In the
current file that is the Site-105 `BGP-EVPN-BUILD.j2` entry.

### Catalyst Center APIs

- `POST /dna/system/api/v1/auth/token`
- `GET /dna/intent/api/v1/template-programmer/template?projectNames=Site-105`
- `GET /dna/intent/api/v1/template-programmer/template/{rootId}`
- `GET /dna/intent/api/v1/network-device?managementIpAddress=<ip>`
- `POST /dna/intent/api/v2/template-programmer/template/deploy`
- `GET /dna/intent/api/v1/task/{taskId}`

The role deploys once per device and polls each CatC task. It deliberately uses
raw API calls because the collection module cannot set a payload option needed
to copy the rendered configuration to the device.

### Run it

Only run after reviewing stages 06–08:

```bash
ansible-playbook playbooks/09_deploy_composite.yml
```

### Important expected output

```text
1 composite deployment(s) to process.
TASK [... deploy ... 172.30.255.1]
TASK [... deploy ... 172.30.255.2]
TASK [... deploy ... 172.30.255.3]
Deployment summary | BGP-EVPN-BUILD.j2
```

Review every row in the final deployment summary. The role continues across
per-device failures so one failure does not hide the other device results.

CatC task `SUCCESS` proves that CatC accepted/completed its workflow; it does
not by itself prove that EVPN is healthy. Run stage 10.

### Where to verify in Catalyst Center

Open **Tools > Template Hub > Site-105 > BGP-EVPN-BUILD.j2** and inspect its
deployment history or Activities. Confirm successful deployment to all three
loopback targets.

Also inspect the devices under **Provision > Inventory**, but use stage 10 for
the authoritative CLI state.

### Disruption warning

The deployment forces template application and can rewrite the switch running
configuration even when there is no visible diff. Do not rerun stage 09 casually
on a live lab.

---

## Stage 10 — Verify the fabric

**Playbook:** `playbooks/10_verify_collect_facts.yml`
**Safety:** Read-only.

### What it accomplishes

Stage 10 bypasses CatC and SSHs to the three switches at management addresses
`198.18.128.22–24`. It runs show commands and saves a snapshot under
`evidence/`, which is gitignored.

### Data read

Stage 10 does not read `settings.json` and does not use the pod number. It reads:

- switch names and management IPs from `inventory/static_inventory.yml`
- SSH usernames/passwords from
  `lab_access[inventory_hostname]` in the encrypted lab vault

### APIs and commands

There are no Catalyst Center API calls. The play uses
`cisco.ios.ios_command` to run:

```text
show version
show ip interface brief
show ip ospf neighbor
show ip bgp summary
show bgp l2vpn evpn summary
show nve peers
show vrf brief
show vlan brief
```

### Run it

```bash
ansible-playbook playbooks/10_verify_collect_facts.yml
```

To check only the leaves:

```bash
ansible-playbook playbooks/10_verify_collect_facts.yml --limit evpn_leaves
```

### Important expected output

```text
TASK [Run show commands for underlay and overlay discovery]
ok: [Site_105-Leaf1]
ok: [Site_105-Leaf2]
ok: [Site_105-Border-Spine]
```

Open:

```text
evidence/Site_105-Leaf1.txt
evidence/Site_105-Leaf2.txt
evidence/Site_105-Border-Spine.txt
```

Look for:

- OSPF neighbors up.
- EVPN BGP session to the route reflector established.
- NVE peers up.
- VRFs Main, PROD, and IOT.
- Expected L2 and L3 VLANs.

### Where to verify in Catalyst Center

Stage 10 changes nothing in CatC, so there is no required UI check. You can
compare device reachability under **Provision > Inventory**, but the saved
switch CLI is the actual verification evidence.

---

## Full orchestrator

`playbooks/00_site_deploy.yml` imports stages 01–09 in order. It excludes stage
10. For a beginner lab, running stages one at a time is safer because you can
check CatC after each stage and stop before disruptive stages 08 and 09.

```bash
ansible-playbook playbooks/00_site_deploy.yml
```

Use the orchestrator only after you understand the individual stages and have
verified the student's pod and AP values.

## Troubleshooting

- **`lab_pod_id` is `REPLACE_ME`:** edit
  `inventory/group_vars/all/lab.yml`, or pass `-e lab_pod_id=<number>`.
- **Stage 02 prints `FAILED - RETRYING`:** the CatC job is still running. Wait
  for `Network settings successfully applied for '...'` on all four MAIN floors
  and recap `failed=0`. That is success. `changed=0` is normal for this stage.
- **Stage 02: Domain Name (or DHCP/DNS/NTP/ISE) at MAIN still says Inherited
  from Global:** expected on stock dCloud. Those values already match Global;
  CatC will not create a floor override. Check timezone and MOTD for a
  site-local change. See stage 02 “CatC UX: Inherited from Global is success”.
- **Stage 03 reports `0 missing global type(s)` but Phase A is `changed`:**
  expected. Nothing was created; the workflow manager re-applied the CLI,
  SNMP, and HTTP assignments to the four MAIN floors. Success is recap
  `failed=0`, not `changed=0`. A non-zero missing count means a description
  was absent and got created — check Design > Network Settings > Device
  Credentials for a duplicate name in that case.
- **Vault file missing on Kali:** rerun collection 00 from the student laptop.
  Do not recreate the demo passphrase manually on Kali.
- **CatC name does not resolve:** reconnect the dCloud VPN and rerun the laptop
  bootstrap so lab DNS is restored.
- **Stage 04 recap `changed=1` with two `changed` items:** one looped task,
  two jobs (`C9800-WLC`, `Site-105-Discovery`). That is success if `failed=0`.
  Site-11 and Site-106 do not create discovery jobs. Then open **Tools >
  Discovery** and confirm each job completed with reachable devices — the
  play can succeed while a host is still down.
- **Stage 05 recap `changed=0` with two `ok` assign items:** success if
  `failed=0`. The WLC and three loopbacks were already at DC-Site-10/MAIN and
  Site-105/MAIN. “Submitted successfully” does not poll CatC; confirm the Site
  column in **Provision > Inventory**. If the site is unchanged and a device
  was already assigned elsewhere, this API will not move it.
- **Stage 06 GitHub 401:** `git_token` was rejected. For a public repo, unset
  it. For a private repo, use a PAT with repo/contents read and do not commit
  it.
- **Stage 06 GitHub 404:** wrong `git_repo` / `git_branch`, or a private repo
  without a token. Local mode does not use GitHub.
- **Stage 07 fails after changing pod numbers:** merge mode leaves the old SSID.
  Restore the intended pod and inspect the shared wireless profile.
- **Stage 10 times out on `198.18.128.22–24`:** the dCloud VPN is usually down.

Use `-e catc_debug=true` or `-e dnac_debug=true` only when troubleshooting.
Debug output can include API payloads and live tokens; redact it before sharing
and never commit it.

## Security note

The repository's supported credential source is vault-encrypted
`Lab Topology/lab_access.yml`; `.vault` is gitignored. Do not add passwords,
shared secrets, tokens, private keys, or certificates to this README, a
playbook, inventory, or unencrypted settings file. A production deployment
must also validate the Catalyst Center TLS certificate rather than using the
lab's `verify: false` setting.
