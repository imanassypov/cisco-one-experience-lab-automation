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
8. Provision the switches and WLC. Leave `lab_ap_macs` empty — no AP is in
   Catalyst Center inventory yet.
9. Deploy the EVPN composite. That programs the AP-facing leaf ports so an
   AP can join the WLC and appear as a Unified AP in Inventory.
10. SSH to the switches and collect read-only verification evidence.
11. Once the AP is Registered on the WLC **and** visible in Catalyst Center
    Inventory, put its Ethernet MAC in `lab_ap_macs` and re-run stage 08. That
    pass names the AP, assigns it to Site-105, then provisions it.

Stages 01–09 use the Catalyst Center API. Stage 10 is the only playbook that
logs in to the switches.

## Before you begin

Complete [GETTING_STARTED.md](GETTING_STARTED.md) first. In particular:

- Connect your laptop to the dCloud VPN, then `ssh cisco@198.18.134.12`.
- Clone this repository onto the script server and run collection
  `00_scriptserver_bootstrap` there. `stage-script-server.sh` installs the base
  packages and `~/venv`; `01_bootstrap_script_server.yml` adds Cisco
  collections, SDKs, Genie/pyATS, and lab DNS.
- Create the repo-root `.vault` on the script server. Everything below runs on
  that host, from that checkout.
- Set `lab_pod_id` in `inventory/group_vars/all/lab.yml`. The bootstrap seeds
  that file from `lab.yml.example` with `REPLACE_ME`; stages that load
  `settings.json` stop until you replace it. The file is gitignored, so your
  values survive later pulls. Leave `lab_ap_macs: []` until **after** stage 09. Stage 08
  provision does not program AP ports. The composite does (`Gi1/0/2` trunk,
  native VLAN 10). Until that CLI is on the leaves, the AP cannot DHCP or
  CAPWAP-join, so Catalyst Center has no Unified AP to provision. After
  stage 09, **one** AP is enough — but wait until it is Registered on the WLC
  **and** has synced through to Catalyst Center Inventory, which lags the
  controller by a few minutes. Stage 08 resolves the AP from Catalyst Center by
  Ethernet MAC, so running it while only the WLC knows the AP fails the
  "has joined the controller" assertion. Then put that Ethernet MAC in
  `lab_ap_macs` (first entry is `{AP1_MAC}`) and re-run stage 08.
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
present. They may still be unassigned or under Global until stage 05. Do
**not** expect a Unified AP here — stage 04 never discovers APs, and the AP
cannot join until stage 09 programs `Gi1/0/2`.

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

This stage ties switching profiles, the student SSID, FlexConnect, and
`HQ-Wireless` together. DC-Site-11 and Site-106 get switching profiles only
(no wireless block). Uploading a profile does not provision devices.

### What each pass is

| Pass | What CatC gets |
| --- | --- |
| Switching profiles | `HQ-Switching`, `Remote-DC-Switching`, `BGP-EVPN-Switching`, `Branch-Switching`. Only `BGP-EVPN-Switching` binds Day-N `BGP-EVPN-BUILD.j2` to Site-105/MAIN. |
| Wireless design | SSID `PSEUDOCO-PODnn` (this run: `PSEUDOCO-POD12`), interfaces Main/PROD/IOT, FlexConnect at Site-105/MAIN. |
| Flex native VLAN | Site-105/MAIN native VLAN **10** (URI GET/PUT, not the design WFM). |
| Flex AAA-override | VLAN **names** Main, PROD, IOT at Site-105/MAIN so ISE can pick VRF. |
| Wireless profile | `HQ-Wireless` assigned to Site-105/MAIN, carrying the student SSID. |

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

Verified on Kali against stock dCloud CatC (2026-09-15): `failed=0`,
`changed=3`, SSID `PSEUDOCO-POD12`.

```text
Settings data loaded — 4 entries found.
4 network profile(s) to create/update.
changed: [catalyst_center_api]   # Create/update switching network profile
Profiles processed: HQ-Switching, Remote-DC-Switching, BGP-EVPN-Switching, Branch-Switching

SSID name 'PSEUDOCO-POD12' resolved.
changed: [catalyst_center_api]   # Create/update wireless design objects
SSIDs: PSEUDOCO-POD12

1 site(s) declare Flex AAA-override VLAN names.
Site ID 919ce2a1-… for Global/NORTH CAROLINA/Durham/Site-105/MAIN
ok: … PUT FlexConnect native VLAN 10 …
FlexConnect native VLAN 10 confirmed at '…/Site-105/MAIN'.
ok: … PUT FlexConnect AAA-override VLANs …
FlexConnect AAA-override IOT, Main, PROD confirmed at '…/Site-105/MAIN'.

changed: [catalyst_center_api]   # Create/update wireless network profile
Profiles processed: HQ-Wireless

PLAY RECAP
catalyst_center_api : ok=55  changed=3  failed=0  skipped=15
```

`changed=3` is the three workflow-manager tasks (switching, wireless design,
wireless profile). Recap is not four profiles plus Flex. The Flex native and
AAA-override PUTs often report `ok` when the GET already matches VLAN 10 and
names Main/PROD/IOT — that is still success; the asserts must print
**confirmed**.

`{POD}` came from `lab_pod_id` (12 → `PSEUDOCO-POD12`). If that assert shows
`PSEUDOCO-POD{POD}` or `REPLACE_ME`, stop and fix `lab.yml`.

The `17 existing sites` dump is the hierarchy UUID map used only to resolve
Site-105/MAIN for the Flex URIs. DEBUG tasks that dump full WFM payloads stay
skipped unless `-e catc_debug=true`.

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

Provisioning applies site settings and profiles. Three passes, in order:

### What each pass is

| Pass | Devices | How |
| --- | --- | --- |
| Wired (`provision_switches.yml`) | Site-105 loopbacks `172.30.255.1–3` | `POST /sda/provisionDevices`. Already-provisioned switches are skipped unless `-e force_reprovision=true`. |
| Wireless (`provision_wireless.yml`) | WLC `198.18.5.103` at DC-Site-10/MAIN | `provision_workflow_manager`. Deferred from the wired pass (`NCWL10092`). Default `force_wireless_provisioning: true` so a changed managed AP location actually lands. |
| Access points (`provision_accesspoints.yml`) | Rows in `access_points[]` whose `{APn_MAC}` resolved from `lab_ap_macs` | Name, assign site, then `POST /wirelessAccessPoints/provision` (raw REST). Empty `lab_ap_macs` skips the whole pass. |

The WLC is listed in DC-Site-10’s `device_list` but is **not** sent to the SDA
provision API. APs are not in `device_list` and are **not** expected in
Inventory on this first run. Stage 08 does not program `Gi1/0/2`. The AP
cannot join until stage 09 deploys the composite. Leave `lab_ap_macs: []`
so the AP pass skips. After stage 09, fill the Ethernet MAC and re-run 08
for name / site / provision. Without that later pass, a joined AP stays on
default tags and never broadcasts `PSEUDOCO-PODnn`.

### Data read from settings.json

- `project[].device_list` and hierarchy fields
- `project[].wireless_controller.managed_ap_locations`
- `project[].wireless_controller.skip_ap_provision`
- `project[].wireless_controller.rolling_ap_upgrade`
- `project[].access_points[].mac_address`
- AP name, mode, location, floor/site, and optional RF profile

AP `{APn_MAC}` values come from `lab_ap_macs`. On the first 08 leave the
list empty. After stage 09, enter the AP's **Ethernet MAC**, not its radio
MAC. Unresolved AP rows are skipped.

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
- `GET /dna/intent/api/v1/task/{taskId}`

The AP provision call is made directly with `ansible.builtin.uri`, not through
`wireless_access_points_provision`: every shipped build of that module (in both
`cisco.dnac` and `cisco.catalystcenter`) sends `siteId`, `rfProfileName` and
`networkDevices` as URL query parameters with an empty JSON body, so it
provisions nothing while still reporting `ok`. An RF profile is required; this
lab defaults to `TYPICAL`. The returned task is polled and the stage fails if
it errors.

### Run it

Review the settings. On the first run, `lab_ap_macs` should still be empty:

```bash
ansible-playbook playbooks/08_provision_devices.yml
```

Do not add force flags during a normal student run.

### Important expected output

Verified on Kali (2026-09-15): `failed=0`, `changed=1`. Wired Site-105 was
first-time POST SUCCESS; WLC was deferred then force-provisioned; AP pass
skipped because `lab_ap_macs: []`.

```text
2 site(s) / 4 device(s) to provision.

# DC-Site-10/MAIN — WLC only
Deferring 1 wireless device(s) … NCWL10092 … 198.18.5.103
Status        : DEFERRED — wireless device(s) handled by the later passes
New (POST)    : 0   Reprov (PUT) : 0   Wireless defer: 1

# Site-105/MAIN — three 9300s
FAILED - RETRYING: … Poll POST provision task … (60 retries left).
Status        : SUCCESS
New (POST)    : 3 device(s)
Progress      : Provisioning Devices | Status: successful | 3 child operation(s)
[1/3] … [2/3] … [3/3] status: SUCCESS | detail: TASK_PROVISION

# Wireless pass
1 wireless controller(s) to provision.
changed: [catalyst_center_api]   # Provision wireless controllers
198.18.5.103 → Global/CALIFORNIA/San Jose/DC-Site-10/MAIN
AP locations  : Global/NORTH CAROLINA/Durham/Site-105/MAIN
Force provis  : True
Status        : Wireless device(s) '198.18.5.103' provisioned successfully.

# AP pass (this lab.yml)
Skipping SITE-105-AP-1, SITE-105-AP-2 — no matching entry in lab_ap_macs …
No resolvable access_points entry … nothing to name or assign.

PLAY RECAP
catalyst_center_api : ok=58  changed=1  failed=0  skipped=79
```

`FAILED - RETRYING` is the wired-task poll (same idea as stage 02), not a play
failure. Recap `changed=1` is the **WLC** workflow manager only. The Site-105
`uri` POST is recorded as `ok` even when CatC created three new provisions.

A later run typically skips the three switches (“already provisioned”) and
still force-provisions the WLC unless `-e force_wireless_provisioning=false`.
Do not fill `lab_ap_macs` or chase a Unified AP row yet. Stage 09 programs
the AP ports. After a Unified AP appears in Inventory, the MAC + AP-pass
re-run (and its expected output) is under stage 09.

### Where to verify in Catalyst Center

Open **Provision > Inventory**. After this first 08, expect **four**
reachable devices — **no Unified AP**:

- Site-105 switches provisioned at Site-105/MAIN
- WLC provisioned at DC-Site-10/MAIN

CDP on Leaf1/Leaf2 `Gi1/0/2` only means the AP is powered. Stage 04 does
not discover APs (the WLC RANGE job is `198.18.5.103` only). Stage 08 does
not set the AP trunk. Do not expect the AP on the WLC or in CatC until
stage 09 has deployed.

### Disruption warning

Changing managed AP locations, assigning an AP to a new site, or reprovisioning
an AP can reboot it for several minutes. Wired devices are skipped when already
provisioned unless forced. The AP pass always re-asserts the provision, because
that is the only way to repair an AP that drifted back onto default tags; it
does not re-assign an AP that is already in its floor.

---

## Stage 09 — Deploy the EVPN composite

**Playbook:** `playbooks/09_deploy_composite.yml`
**Safety:** **Disruptive. Pushes rendered CLI to the three fabric switches.**

### What it accomplishes

This is the stage that builds the live EVPN/VXLAN fabric **and** programs
the AP-facing ports. CatC renders `BGP-EVPN-BUILD.j2` (DEFN/FUNC/FABRIC,
including `DEFN-CLIENT-PORTS.j2` on `Gi1/0/2`) and copies it to the three
Site-105 loopbacks. Four `project[]` rows load; only Site-105 has
`DeployTemplate: true`, so the play queues **one** composite.

Until this deploy lands, `Gi1/0/2` is still access/VLAN 1. The AP can show
in CDP but cannot get a VLAN 10 address or CAPWAP-join the WLC. Catalyst
Center therefore has **no Unified AP** after stages 04–08. The AP appears
in **Provision > Inventory** only after this composite programs the trunk
and the AP joins.

### What each target is

| Loopback | Role | Hostname |
| --- | --- | --- |
| `172.30.255.1` | Leaf | `Site_105-Leaf1` |
| `172.30.255.2` | Leaf | `Site_105-Leaf2` |
| `172.30.255.3` | Spine + RR + border | `Site_105-Border-Spine` |

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

Verified on Kali (2026-09-15): `failed=0`, `changed=0`. All three devices
`SUCCESS` under one Template Deployment ID.

```text
Settings data loaded — 4 entries found.
1 composite deployment(s) to process.
ok: … Deploy composite template | BGP-EVPN-BUILD.j2  (172.30.255.1, .2, .3)

FAILED - RETRYING: … Poll async task status | BGP-EVPN-BUILD.j2 (60 retries left).
ok: … 172.30.255.1 → <taskId>
ok: … 172.30.255.2 → <taskId>
ok: … 172.30.255.3 → <taskId>

Device: 172.30.255.1 | deploymentId: <uuid> | result: SUCCESS
Device: 172.30.255.2 | deploymentId: <same uuid> | result: SUCCESS
Device: 172.30.255.3 | deploymentId: <same uuid> | result: SUCCESS

│ Template         │ BGP-EVPN-BUILD.j2
│ Project          │ Site-105
│ Site             │ Global/NORTH CAROLINA/Durham/Site-105/MAIN
│ Target devices   │ 172.30.255.1, 172.30.255.2, 172.30.255.3
│ API errors       │ none
│ 172.30.255.1–3   │ SUCCESS

PLAY RECAP
catalyst_center_api : ok=31  changed=0  failed=0  skipped=13
```

`FAILED - RETRYING` is the deploy-task poll, not a play failure. Recap
`changed=0` is normal: the deploy `uri` calls are `ok`. One `deploymentId`
shared across three IPs is CatC grouping one Template Hub job, not a bug.

The role continues across per-device failures so one red row does not hide
the others. CatC `SUCCESS` means the workflow finished; it does **not** prove
EVPN or the AP trunk is in running-config. Run stage 10, and on each leaf:

```text
show running-config interface GigabitEthernet1/0/2
show nve peers
show bgp l2vpn evpn summary
```

Expect trunk native VLAN 10 on `Gi1/0/2` after this deploy. That port
programming is what makes AP discovery possible. Stage 08 provision does
not push it.

Verified on Leaf1/Leaf2 after the 2026-09-15 deploy: both `Gi1/0/2` blocks
match `DEFN-CLIENT-PORTS.j2` (description `AP`, trunk, native 10, allowed
`10,101,102`, CTS SGT 2, portfast trunk). Leaf2 NVE is the fuller picture:
L3CP `110010`/`110101`/`110102` (Main/PROD/IOT) to `.1` and `.3`, plus L2CP
`100010` (VLAN 10) to the other leaf. Leaf1 can take a few extra minutes to
show IOT `110102` and L2CP `100010`; re-run `show nve peers` before assuming
a miss. VLAN names on the box are `Main` / `PROD` / `IOT`.

### Where to verify in Catalyst Center

Open **Tools > Template Hub > Site-105 > BGP-EVPN-BUILD.j2** and inspect
deployment history / Activities. Confirm SUCCESS to `172.30.255.1–3`.

Then open **Provision > Inventory** (all families, or the Wireless
Controllers / Switches / Access Points chips). This is the first stage
where a Unified AP is expected. After the composite programs `Gi1/0/2`
and at least one AP joins, expect **five** reachable rows. Verified
2026-09-15:

| Device (inventory name) | IP | Family | Site | Provisioning |
| --- | --- | --- | --- | --- |
| `C9800.corp.pseudoco.com` | `198.18.5.103` | Wireless Controller | DC-Site-10/MAIN | Success |
| `Site-105-Border-Spine…` | `172.30.255.3` | Switches and Hubs | Site-105/MAIN | Success |
| `Site-105-Leaf1…` | `172.30.255.1` | Switches and Hubs | Site-105/MAIN | Success |
| `Site-105-Leaf2…` | `172.30.255.2` | Switches and Hubs | Site-105/MAIN | Success |
| `SITE_105-Pod09-AP-1` (WLC name) | `10.10.255.101` | Unified AP | **Unassigned** | **Not Provisioned** |

The four wired/WLC rows were already Success after stage 08. The fifth
row is new here: CatC learned the AP **from the WLC after the join**,
not from stage 04 RANGE jobs and not from stage 08 provision. Stage 10
is still the authoritative switch running-config.

### Inventory: at least one AP discovered

Give the AP a few minutes after the deploy to DHCP on VLAN 10 and
CAPWAP-join `198.18.5.103`. Then filter Inventory **Access Points**.

**One Unified AP is enough.** Do not hunt a second CDP neighbor. Success
looks like:

- Family **Unified AP**
- Reachable
- IP on VLAN 10 (this lab: `10.10.255.101`)
- Site **Unassigned** (normal until you re-run 08 with a MAC)
- Provisioning **Not Provisioned** (normal until that AP pass)
- Name still the WLC name (`SITE_105-Pod09-AP-1` is fine)

If that row is missing, confirm the trunk landed, then the join:

```text
show running-config interface GigabitEthernet1/0/2
show vlan brief | include 10
show cdp neighbors GigabitEthernet1/0/2 detail
```

On the WLC (use `198.18.5.103`, not the `.102` in `lab_access['C9800-WLC']`).
Commands from the Catalyst 9800 Command Reference and Cisco’s 9800 AP-join
tech note
([218396](https://www.cisco.com/c/en/us/support/docs/wireless/catalyst-9800-series-wireless-controllers/218396-troubleshoot-catalyst-9800-ap-join-or-di.html)):

```text
show ap summary
show wireless stats ap join summary
show wireless stats ap discovery
```

`Registered` on `show ap summary` is the join. Use
`show wireless stats ap join summary` (not `show ap join stats`) for a
Not Joined / last failure phase. If an AP has a VLAN 10 IP but never
appears, check discovery counters, then on a C9117/AP4800 console use
the Catalyst 9100 AP Command Reference: `show capwap client rcb` and,
to drop a leftover primary WLC, `capwap ap erase all` (not classic-IOS
`clear capwap private-config`).

An AP’s `siteHierarchy` can stay null even after a later assign. Read
membership from the site, not only the Inventory Site column.

### Next: put the Ethernet MAC in lab.yml and provision the AP

1. On the WLC, Ethernet MAC from `show ap summary` ([9800 Command
   Reference](https://www.cisco.com/c/en/us/td/docs/wireless/controller/9800/command-reference/b_wireless_cr/show-commands.html)).
   This lab: `084f.a950.f028` → `08:4f:a9:50:f0:28`. Use **Ethernet**, not
   Radio MAC (`10b3.d66c.c860`). CatC search uses radio MAC; `lab_ap_macs`
   does not.

2. On Kali, in `inventory/group_vars/all/lab.yml`, one entry is enough
   (`{AP1_MAC}`). Do not commit this file if it is only your pod:

   ```yaml
   lab_ap_macs:
     - "08:4f:a9:50:f0:28"
   ```

   `{AP2_MAC}` stays empty and that `access_points[]` row is dropped.

3. Re-run stage 08. Wired devices stay skipped if already provisioned.
   `force_wireless_provisioning` defaults **true**, so this run also
   force-provisions the WLC. The AP pass has no force flag — it always
   re-asserts the provision. Do not add `force_reprovision` (that
   PUT-reprovisions the fabric switches):

   ```bash
   ansible-playbook playbooks/08_provision_devices.yml
   ```

   `198.18.5.103` is shared across pods, and a controller re-provision
   without Skip AP Provision reprovisions every AP it manages. To touch
   only your AP, disable the controller pass:

   ```bash
   ansible-playbook playbooks/08_provision_devices.yml -e wireless_provision_enabled=false
   ```

4. Open **Provision > Inventory** again. Right after the play, verified
   2026-09-15 18:17:

   | Device | IP | Family | Site | Provisioning |
   | --- | --- | --- | --- | --- |
   | `C9800.corp.pseudoco.com` | `198.18.5.103` | Wireless Controller | DC-Site-10/MAIN | Success |
   | three Site-105 9300s | `172.30.255.1–3` | Switches and Hubs | Site-105/MAIN | Success |
   | `SITE-105-AP-1` | `10.10.255.101` | Unified AP | **Site-105/MAIN** | **Configuring** |

   Compared with the post-09 row: the WLC name `SITE_105-Pod09-AP-1` is
   gone, the AP is no longer Unassigned / Not Provisioned, and it is at
   Site-105/MAIN. **Configuring** is the provision job still running (AP
   reboot + tag apply). Wait a few minutes and refresh — it should become
   **Success**. Do not re-run 08 while it says Configuring.

   **Default tags on the WLC while Inventory says Configuring are
   expected.** CatC 3.1.x creates and attaches site / policy / RF tags
   only during AP provision, not when the WLC is provisioned or the AP
   is named and site-assigned
   ([Wireless Network Configuration Use Cases](https://www.cisco.com/c/en/us/td/docs/cloud-systems-management/network-automation-and-management/catalyst-center/3-1-x/user_guide/b_cisco_catalyst_center_user_guide_3_1_x/m-wireless-network-configuration-use-cases.html)).
   Stage 08 now polls that job to completion and fails if it errors, so
   a green play means the job finished, not merely that it was accepted.

   After Inventory is **Success**, the WLC shows CatC-generated tags.
   Verified on Kali 2026-09-15 with the simplified AP pass:

   ```text
   show ap tag summary
   SITE-105-AP-1  084f.a950.f028  ST_Durha_Site-105_d97a1_0
                  PT_Durha_Site-_MAIN_70ab7  TYPICAL  No  Static
   ```

   `Tag Source Static` is the CatC assignment; `Default` is the 9800
   factory one. `show ap summary` also moves from `default location`
   to the `location` set in `settings.json` (here `Leaf1`).

   Verify on the 9800 with the commands from the
   [9800 Command Reference](https://www.cisco.com/c/en/us/td/docs/wireless/controller/9800/command-reference/b_wireless_cr/show-commands.html)
   and
   [Configuration Model — Verifying](https://www.cisco.com/c/en/us/td/docs/wireless/controller/9800/config-guide/newconfigmodel/b_catalyst-9800-configuration-model/m_validating_configuration.html):

   ```text
   show ap tag summary
   show wireless tag policy summary
   show wireless tag site summary
   ```

   After a successful run the CatC-generated tags are present alongside
   the dCloud pre-built `DCLOUD-XAR-FLEX-PT` and the factory defaults —
   three policy tags and three site tags in this lab.

   While Inventory is still Configuring, this lab showed (2026-09-15):

   ```text
   SITE-105-AP-1  084f.a950.f028  default-site-tag  default-policy-tag
                  default-rf-tag  No  Default
   ```

   `Tag Source Default` is the 9800 factory assignment. Stage 08 polls the
   provision task, so if the play finished green and tags are still
   Default, the job completed but CatC did not apply them — open the
   activity in **Activities > Audit Logs**. Do not assign tags by hand.

   After Success, expect CatC names and `Tag Source Static`. Verified on
   Kali 2026-09-15 with the simplified AP pass and
   `-e wireless_provision_enabled=false` (so the shared WLC is left
   alone): `failed=0`, `changed=1`.

   ```text
   ok: … Provision the access points
         SITE-105-AP-1 → …/Site-105/MAIN (TYPICAL)
   ok: … Assert every access point provisioning call returned a task ID
   ok: … Poll access point provisioning tasks
   ok: … Assert every access point provisioned successfully
         1 access point provisioning task(s) completed.

   │ Access points : 1
   │   SITE-105-AP-1 → 10:b3:d6:6c:c8:60
   │ Floor         : Global/NORTH CAROLINA/Durham/Site-105/MAIN
   │ Skipped       : SITE-105-AP-2
   │ Named changed : True
   │ Newly joined  : none — already members
   │ Provisioned   : SITE-105-AP-1

   PLAY RECAP
   catalyst_center_api : ok=62  changed=1  failed=0  skipped=55
   ```

   `changed=1` is **Name and locate**. `Provision the access points` is
   `ok` because `uri` does not report change, but the proof it ran is the
   task ID assertion and the poll — the poll retries while the job is in
   flight, which a no-op call cannot do.

   Or, in CatC, provision only that AP: Inventory → select
   `SITE-105-AP-1` → Actions → Provision → Provision Device
   ([Provision Cisco APs on day 1](https://www.cisco.com/c/en/us/td/docs/cloud-systems-management/network-automation-and-management/catalyst-center/3-1-x/user_guide/b_cisco_catalyst_center_user_guide_3_1_x/m_provision-wireless-devices.html#id_91719)).
   Open **See Details** for the CatC error if it fails again.

   **Do not re-provision the WLC in the CatC UI.** `198.18.5.103` is
   shared across pods. A controller re-provision without Skip AP
   Provision also reprovisions every AP it manages
   ([3.1.x use cases](https://www.cisco.com/c/en/us/td/docs/cloud-systems-management/network-automation-and-management/catalyst-center/3-1-x/user_guide/b_cisco_catalyst_center_user_guide_3_1_x/m-wireless-network-configuration-use-cases.html)).
   Do not use `-e force_reprovision=true` — that PUT-reprovisions the
   three fabric switches.

### Important expected output (AP pass after stage 09)

Verified on Kali (2026-09-15) with one Ethernet MAC in `lab_ap_macs` and
`-e wireless_provision_enabled=false`: `failed=0`, `changed=1`.

```text
2 site(s) / 4 device(s) to provision.

# Wired — both sites already done
DC-Site-10/MAIN  : DEFERRED — WLC 198.18.5.103 (NCWL10092)
Site-105/MAIN    : SKIPPED — 3 already-provisioned (172.30.255.1–3)

# Wireless pass — disabled by the -e extra
wireless_provision_enabled is false — leaving wireless controllers
site-assigned but unprovisioned.

# AP pass
Skipping SITE-105-AP-2 — no matching entry in lab_ap_macs …
1 access point(s) to configure.
changed: … Name and locate access points
skipping: … Assign access points to their floor   (already a member)
ok:      … Provision the access points
           SITE-105-AP-1 → …/Site-105/MAIN (TYPICAL)
ok:      … Assert every access point provisioning call returned a task ID
ok:      … Poll access point provisioning tasks
ok:      … Assert every access point provisioned successfully

│ Access points : 1
│   SITE-105-AP-1 → 10:b3:d6:6c:c8:60
│ Floor         : Global/NORTH CAROLINA/Durham/Site-105/MAIN
│ Skipped       : SITE-105-AP-2
│ Named changed : True
│ Newly joined  : none — already members
│ Provisioned   : SITE-105-AP-1

PLAY RECAP
catalyst_center_api : ok=62  changed=1  failed=0  skipped=55
```

What that means:

- `changed=1` is **Name and locate**. The other two AP steps are `uri`
  and `assign_device_to_site`, neither of which reports change.
- `SITE-105-AP-2` skipped is success for a one-AP pod.
- The summary MAC `10:b3:d6:6c:c8:60` is the **radio** MAC CatC uses to
  name the AP. `lab_ap_macs` stays the Ethernet MAC; the role translates.
- `Newly joined : none` means the AP was already in its floor, so it was
  not re-assigned and not bounced. On a first run this shows the AP
  management IP instead.
- The real evidence the provision happened is the **task ID assertion**
  and the **poll**, not the `ok`. The poll retries while the CatC job is
  in flight; a no-op call has no task to poll.

The AP can reboot while tags apply. Inventory often shows **Configuring**
for several minutes, then **Success**. Filter **Access Points** if the Site
column still looks empty (`siteHierarchy` can stay null for a Unified AP).
Do not treat Configuring as a failed play, and do not re-run 08 to
“finish” it.

### Disruption warning

The deployment forces template application and can rewrite the switch running
configuration even when there is no visible diff. Do not rerun stage 09 casually
on a live lab.

---

## Stage 10 — Verify intent against the fabric

**Playbook:** `playbooks/10_verify_intent.yml`
**Safety:** Read-only.

### What it accomplishes

Stage 10 closes the loop: it compares what the pipeline *declared* against what
the devices are *actually running*, and writes a pass/fail report.

Live state is collected through Catalyst Center **Command Runner**, so the play
needs no SSH to the switches. It runs from the Kali script server like every
other stage and keeps working when the path to `198.18.128.22–24` is down.

### Data read

Intent comes from two places:

| Source | What it declares |
| --- | --- |
| `settings.json` | Wireless SSID, VLANs, access points, `TemplateTarget[]` device list |
| `DEFN-*.j2` **in Catalyst Center** | VRFs, L3VNIs, loopbacks, node roles, overlay SVIs, client ports, L3OUT |

The DEFN templates are read from Catalyst Center Template Programmer, **not**
from the repo checkout. Stage 06 seeds Catalyst Center from git or a local
folder depending on `template_source`; stage 10 verifies what was actually
deployed. A DEFN file edited locally and never synced therefore cannot produce
a false pass, and the stage works from a checkout with no templates in it.

### APIs and commands

```text
GET  /dna/intent/api/v1/template-programmer/project
GET  /dna/intent/api/v1/template-programmer/template/{id}
GET  /dna/intent/api/v1/network-device?managementIpAddress=<ip>
POST /dna/intent/api/v1/network-device-poller/cli/read-request
GET  /dna/intent/api/v1/task/{taskId}
GET  /dna/intent/api/v1/file/{fileId}
```

Collected per switch (`Site_105-Leaf1`, `Site_105-Leaf2`, `Site_105-Border-Spine`):

| Command | Intent it proves |
| --- | --- |
| `show vrf` | Every declared VRF exists, with the right route distinguisher |
| `show vlan` | Tenant overlay VLANs are present and active |
| `show nve vni` | Each L3VNI is bound to its transit VLAN and VRF, and is operationally up |
| `show nve peers` | VXLAN tunnels to the other fabric nodes are up |
| `show ip interface brief` | Underlay loopbacks and tenant SVIs carry the declared addresses and are up |
| `show ip interface` | DHCP helper addresses are applied to the tenant SVIs |
| `show interfaces status` | Client-facing ports exist in the declared mode and are connected |
| `show ip bgp all summary` | Correct BGP AS, EVPN sessions established, L3OUT neighbours up on the border |

Collected per wireless controller (`C9800`):

| Command | Intent it proves |
| --- | --- |
| `show wlan summary` | The `settings.json` SSID is provisioned and administratively up |
| `show ap summary` | The declared access points are registered, with matching Ethernet MACs |
| `show ap tag summary` | APs carry the Catalyst Center site and policy tags, not the factory defaults |

Every response is parsed with **Genie** and compared field by field — no text
matching. `show running-config` is deliberately not collected: each intent it
used to prove has an operational equivalent that parses, and those prove the
fabric is working rather than merely configured. `show nve vni` reports
`vni_state`, `show interfaces status` reports `connected`, `show ip interface
brief` reports `protocol up`; a config line proves none of that.

> pyATS/Genie is therefore a hard dependency, installed by
> `00_scriptserver_bootstrap` (pinned `genie==26.8`, `pyats==26.8`; about
> 700 MB). Command Runner also rejects more than **five commands per request**,
> so the role chunks them. Any command Catalyst Center refuses is reported as
> `NOT VERIFIED` rather than silently passing.

> **An empty response is a result, not an error.** Genie raises
> `SchemaEmptyParserError` when a command runs but has nothing to report — a
> fabric with no NVE peers, or a controller with no access points joined. The
> `genie_parse` filter turns that into an empty dict, so the check reports the
> value as absent and fails on its own terms. Only a genuine parsing problem,
> such as a missing parser, aborts the run. Run stage 10 before stage 09 and you
> will see those checks fail, which is the correct answer.

### Run it

```bash
ansible-playbook playbooks/10_verify_intent.yml
```

Report without failing the play, for a known-broken demo fabric:

```bash
ansible-playbook playbooks/10_verify_intent.yml -e verify_fail_on_mismatch=false
```

### Important expected output

```text
│ Devices       : 4  (Site_105-Leaf1, Site_105-Leaf2, Site_105-Border-Spine, C9800)
│ Checks        : 51
│ Pass          : 44
│ Fail          : 0
│ Not verified  : 0
│ Not applicable: 7
│ Report        : …/evidence/stage10-verification.md
│ HTML          : …/evidence/stage10-verification.html
```

`Not applicable` is expected: `FABRIC-OVERLAY.j2` skips the L2 sections on
SPINE and BORDER, so tenant VLAN, SVI and DHCP-helper checks do not apply to
`Site_105-Border-Spine`, and client-port checks do not apply to a device with
no `DEFN_CLIENT_PORTS` entry.

Two reports are written, both on **the host that ran the play** — Kali when
driven from the script server, not your laptop:

| File | Use |
| --- | --- |
| `evidence/stage10-verification.md` | Reading in a terminal or editor, diffing between runs |
| `evidence/stage10-verification.html` | A formal verification report for sharing or printing |

Read the markdown on the script server. `rich` is installed in the venv and
renders the headings and tables in colour:

```bash
python -m rich.markdown evidence/stage10-verification.md | less -R
```

Or plainly, with no renderer: `less evidence/stage10-verification.md`.

Or pull either file back:

```bash
scp cisco@198.18.134.12:cisco-one-experience-lab-automation/ansible-automation/01_campus/evpn/ansible/evidence/stage10-verification.html .
```

Both contain the result counts, the devices in scope, which Catalyst Center
template revisions the intent came from, and a per-device table putting each
declared value next to the value observed on the device, plus the exceptions
behind any failure. The HTML version adds a contents list, a control index, and
numbered sections, and is self-contained — no external CSS, fonts or scripts —
so it opens offline and prints cleanly. Raw command output is in neither;
re-run with `-e catc_debug=true` if you need it.

`evidence/` is deliberately gitignored so live run output never lands in the
repo. For illustration, a captured pair from a passing run is committed
separately:

| Sample | View it |
| --- | --- |
| [`docs/sample-reports/stage10-verification.md`](docs/sample-reports/stage10-verification.md) | Renders directly on GitHub |
| [`docs/sample-reports/stage10-verification.html`](docs/sample-reports/stage10-verification.html) | Download and open in a browser — GitHub shows HTML as source |

These are a point-in-time snapshot of Site-105, not output from your pod. Use
them to see the report shape before you run the stage.

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
- **Vault file missing:** recreate the repo-root `.vault` on the script server
  with the proctor's passphrase, then run `00_preflight.yml` to confirm it
  decrypts before re-running anything else.
- **CatC name does not resolve:** reconnect the dCloud VPN and rerun
  `01_bootstrap_script_server.yml` so lab DNS is restored.
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
- **Stage 07 recap `changed=3`:** the three workflow managers. Flex native /
  AAA-override `ok` with “confirmed” is success when VLAN 10 and names
  Main/PROD/IOT already match. Success is `failed=0` and SSID
  `PSEUDOCO-PODnn` resolved, not `changed=0`.
- **Stage 07 fails after changing pod numbers:** merge mode leaves the old SSID.
  Restore the intended pod and inspect the shared wireless profile.
- **Stage 08: DC-Site-10 is `DEFERRED` and Site-105 shows `FAILED - RETRYING`:**
  expected. The WLC cannot use `sda/provisionDevices` (`NCWL10092`); the
  wireless pass provisions it. The retry banner is the wired POST poll. Success
  is Site-105 `SUCCESS` with 3 child tasks, WLC “provisioned successfully”,
  and recap `failed=0`. Recap `changed=1` is the WLC only.
- **Stage 08 skips SITE-105-AP-1/AP-2:** expected on the first 08.
  `lab_ap_macs` stays empty until after stage 09. CDP on the leaf is not a
  CatC discovery and does not mean the AP has joined.
- **AP-pass 08 after 09, `changed=1`:** expected. The one change is
  name/locate. `SITE-105-AP-2` skipped is a one-AP pod. Summary
  `→ 10:b3:d6:6c:c8:60` is radio MAC, not a wrong `lab_ap_macs` entry.
- **Inventory AP Success but WLC still on default tags:** check the AP pass
  output. `Poll access point provisioning tasks` must have retried and
  `Assert every access point provisioned successfully` must have passed —
  a green play with neither means the request never reached CatC.
  Expected good state on the 9800 is `Tag Source Static` with
  `ST_Durha_Site-105_d97a1_0` / `PT_Durha_Site-_MAIN_70ab7` / `TYPICAL`,
  alongside the dCloud pre-built `DCLOUD-XAR-FLEX-PT` and the factory
  defaults.
- **AP on CDP, missing on WLC/CatC before stage 09:** expected. Stage 08
  does not program `Gi1/0/2`. After the composite deploy, confirm trunk
  native 10, VLAN 10 + NVE up, AP DHCP, then CAPWAP to `198.18.5.103`.
  See stage 09 “Inventory: at least one AP discovered”.
- **Stage 09 recap `changed=0` with `FAILED - RETRYING` then three SUCCESS
  rows:** expected. Poll, not failure. Shared `deploymentId` is one CatC job.
  Still verify CLI (stage 10 / `Gi1/0/2`); do not re-run 09 on a live lab
  unless asked.
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
