# Splunk EVPN Assurance

Streaming telemetry from the Site 105 campus EVPN/VXLAN fabric into Splunk, rendered as
role-aware operational dashboards.

The campus collection (`01_campus/evpn`) answers **"did my intent deploy?"**. This one
answers **"is the fabric healthy right now?"** — and it answers it from the switches'
own operational YANG state, not from a config diff.

## Overview

| Capability | What it does |
| --- | --- |
| Fabric telemetry | Enables 21 IOS-XE MDT subscriptions (IDs 40101–40121) on every fabric node, covering NVE, EVPN, BGP and interface operational state |
| Collection | Runs a patched OpenTelemetry collector that turns KV-GPB YANG telemetry into Splunk metric points |
| Storage | Creates the `evpn_assurance` metrics index and a scoped HEC token |
| Context | Generates the device and segment lookup CSVs **from the fabric intent**, so dashboards cannot drift from what was built |
| Visualisation | Installs a Splunk Dashboard Studio app with Summary, Details and Alerts views |
| Verification | Proves the whole path end to end and writes an evidence report |

### Pipeline

```
Site 105 fabric                       Splunk host 198.18.5.109
  Site_105-Leaf1              gRPC     ┌──────────────────────────────────────┐
  Site_105-Leaf2           dial-out    │ splunk-otel-collector.service        │
  Site_105-Border-Spine ──────────────▶│   yang_grpc     :57444               │
                                       │   hostmetrics                        │
  telemetry ietf subscription 40101+   │   batch                              │
  encode-kvgpb, source-vrf Mgmt-vrf    │   splunk_hec ────┐                   │
                                       └──────────────────┼───────────────────┘
                                                          │ https://localhost:8088
                                                          ▼
                                            index=evpn_assurance (metric)
                                                          │
                                                          ▼
                                            app: campus_evpn_assurance
                                            Summary │ Details │ Alerts
```

The fabric half of that diagram is configured by `01_campus/evpn`, not by this collection.
See [Relationship to the campus collection](#relationship-to-the-campus-collection).

## Prerequisites

| Requirement | Value |
| --- | --- |
| Fabric | Site 105 EVPN built by [`01_campus/evpn`](../../01_campus/evpn/) |
| IOS-XE | 17.18.02 or later on Catalyst 9000 |
| Splunk | Enterprise 8.0+ (Dashboard Studio v2), reachable at `198.18.5.109` |
| Splunk access | Admin account able to create indexes and HEC tokens (`Splunk Enterprise` in the vault) |
| SSH access | A **separate** Linux account on the Splunk host with `sudo` (`splunk_server` in the vault) |
| Collector binary | `otelcol-yangfix` — built elsewhere and staged, or built in place with Go 1.25+ and `ocb` |
| Control node | The Kali script server, bootstrapped by [`00_scriptserver_bootstrap`](../../00_scriptserver_bootstrap/) |

No extra Galaxy collections are needed — every task is `ansible.builtin`.

> **Transport note.** The Splunk host is reached with `ansible.builtin.paramiko_ssh`, not the
> default OpenSSH transport. Credentials live in the vault as a password, and the ssh
> transport would need `sshpass` — which cannot be installed on the Kali script server,
> because it pulls `libc6` forward and apt refuses against the pinned `libc6-dev`. paramiko
> does password auth in-process and is already pinned in
> [`ansible-automation/requirements.txt`](../../requirements.txt).

> **Why a patched collector?** The stock `yanggrpcreceiver` silently drops numeric YANG
> list keys (`vni`, `evni`, `vlan-id`), so every per-VNI panel comes back empty. The patch
> and its analysis are in
> [`otel-collector/yanggrpcreceiver-numeric-key-issue.md`](otel-collector/yanggrpcreceiver-numeric-key-issue.md).

## Directory structure

```
splunk_evpn/
├── README.md                          This document
├── SETUP_GUIDE.md                     Manual equivalent of the automated stages
├── ansible/
│   ├── ansible.cfg                    Inventory, roles path, vault file, vars plugin
│   ├── collections/requirements.yml   Empty by design (ansible.builtin only)
│   ├── inventory/
│   │   ├── hosts.yml                  splunk_server → 198.18.5.109 (the repo's only SSH target)
│   │   └── group_vars/
│   │       ├── all/assurance.yml      Index, HEC, collector paths, fabric cross-references
│   │       └── splunk_servers/vars.yml  SSH + sudo credentials from the vault
│   ├── playbooks/
│   │   ├── 00_assurance_deploy.yml    Orchestrator — imports 01–08
│   │   ├── 01_preflight.yml           Read-only host probe
│   │   ├── 02_splunk_index_hec.yml    Metrics index + HEC token
│   │   ├── 03_build_collector.yml     Build or stage otelcol-yangfix
│   │   ├── 04_deploy_collector.yml    Config + systemd + restart  (disruptive)
│   │   ├── 05_render_lookups.yml      Generate lookups from fabric intent (local)
│   │   ├── 06_deploy_splunk_app.yml   Package + install the app     (disruptive)
│   │   ├── 07_enable_fabric_telemetry.yml  Read-only campus cross-check
│   │   └── 08_verify_assurance.yml    Read-only end-to-end proof
│   ├── roles/
│   │   ├── splunk_preflight/          Probe Splunk, systemd, toolchain, receiver port
│   │   ├── splunk_index_hec/          Create the metrics index and HEC token
│   │   ├── otel_collector_build/      Compile or stage otelcol-yangfix
│   │   ├── otel_collector_deploy/     Render config, systemd drop-in, restart
│   │   ├── assurance_lookups/         Render both CSVs from DEFN-*.j2 intent
│   │   ├── splunk_app_deploy/         Build .spl, install, restart, assert build
│   │   └── assurance_verify/          Five end-to-end checks + evidence report
│   └── evidence/                      Verification reports (gitignored)
├── splunk-app/campus_evpn_assurance/  Dashboard app source
│   ├── default/
│   │   ├── app.conf                   Version and build number
│   │   ├── macros.conf                evpn_index, evpn_lookup, evpn_segment_lookup, …
│   │   ├── transforms.conf            Lookup definitions
│   │   └── data/ui/views/             Summary, Details, Alerts (Dashboard Studio v2)
│   └── lookups/                       Generated by stage 05 — do not hand-edit
├── otel-collector/
│   ├── README.md                      Collector architecture and troubleshooting
│   ├── agent_config.yaml.j2           Rendered to /etc/otel/collector/agent_config.yaml
│   ├── builder.yaml                   ocb manifest for otelcol-yangfix
│   ├── receiver_yang_26_05_27.tar.gz  Patched yang_grpc receiver source (tracked)
│   ├── systemd/override.conf.example  Reference copy of the systemd drop-in
│   └── yanggrpcreceiver-numeric-key-issue.md
├── packaging/
│   ├── build-app.sh                   Tars splunk-app/ into dist/<app>-<version>.spl
│   └── dist/                          Build output (gitignored)
├── tools/
│   ├── validate_studio.py             Three-tier Dashboard Studio validation
│   └── xml_to_studio.py               Classic Simple XML → Dashboard Studio converter
└── Model Maps/                        CLI ⇄ YANG xpath reference for the streamed models
```

## Installation

Run from the script server, with the dCloud VPN up.

1. **Add the Splunk credentials to the vault.** Two entries are needed — see
   [`lab_access.yml.example`](../../../Lab%20Topology/lab_access.yml.example):

   | Key | Purpose |
   | --- | --- |
   | `Splunk Enterprise` | Admin account for Splunk Web `:8000` and REST `:8089` — creates the index, HEC token, installs the app. Usually already present in the lab vault. |
   | `splunk_server` | **Separate** Linux account on `198.18.5.109` with `sudo` — manages the collector. Normally has to be added. |

   ```bash
   cd ~/cisco-one-experience-lab-automation
   ansible-vault edit "Lab Topology/lab_access.yml"
   ```

2. **Point the fabric at the collector.** In
   [`01_campus/evpn/Settings/settings.json`](../../01_campus/evpn/Settings/settings.json),
   the Site-105 project carries:

   ```json
   "telemetry": {
     "splunk": {
       "enabled": true,
       "receiver_ip": "198.18.5.109",
       "receiver_port": "57444",
       "roles": ["SPINE", "BORDER", "CLIENT"]
     }
   }
   ```

3. **Push the subscriptions from the campus collection:**

   ```bash
   cd ansible-automation/01_campus/evpn/ansible
   ansible-playbook playbooks/06_template_sync.yml
   ansible-playbook playbooks/09_deploy_composite.yml
   ```

4. **Stage the collector binary** (see [Building the collector](#building-the-collector)).

5. **Run this collection:**

   ```bash
   cd ../../../07_assurance/splunk_evpn/ansible
   ansible-playbook playbooks/00_assurance_deploy.yml \
     -e otel_staged_binary=/opt/build/otelcol-yangfix
   ```

## Configuration

All of these live in [`inventory/group_vars/all/assurance.yml`](ansible/inventory/group_vars/all/assurance.yml)
and can be overridden with `-e`.

| Variable | Default | Description |
| --- | --- | --- |
| `splunk_home` | `/opt/splunk` | Splunk install root |
| `splunk_mgmt_port` | `8089` | Splunk management/REST port |
| `splunk_assurance_index` | `evpn_assurance` | **Must** be a metrics index |
| `splunk_hec_port` | `8088` | HTTP Event Collector port |
| `splunk_hec_token_name` | `evpn-collector` | HEC token name; reused if it exists |
| `splunk_hec_url` | `https://localhost:8088/services/collector` | Loopback — collector and Splunk share the host |
| `splunk_hec_tls_insecure` | `true` | Accept the self-signed HEC certificate |
| `splunk_app_name` | `campus_evpn_assurance` | Splunk app id |
| `splunk_restart_timeout` | `180` | Seconds to wait for splunkd after a restart |
| `otel_receiver_port` | `57444` | gRPC dial-out listener; must match `receiver_port` in settings.json |
| `otel_config_path` | `/etc/otel/collector/agent_config.yaml` | Rendered collector config (gitignored — carries the token) |
| `otel_service_name` | `splunk-otel-collector` | systemd unit |
| `otel_service_user` | `otelcol` | Service account, created only when this role installs the unit |
| `otel_custom_binary` | `/usr/local/bin/otelcol-yangfix` | Patched collector |
| `otel_stock_binary` | `/usr/bin/otelcol` | Only exists if the Splunk OTel distro is installed |
| `otel_use_custom_binary` | `true` | `false` falls back to stock `/usr/bin/otelcol` and loses per-VNI panels. Only valid on a host that has the collector package installed. |
| `otel_build_mode` | `staged` | `staged` copies a prebuilt binary; `local` compiles with `ocb` |
| `otel_staged_binary` | `""` | Path to a prebuilt `otelcol-yangfix` when `otel_build_mode: staged` |
| `assurance_site` | `Site-105` | Matches `HierarchyBldg` in settings.json and the `site` column in the lookups |
| `assurance_debug` | `false` | Dump the extracted fabric intent in stage 05 |

## How it works

### Stage 01 — preflight

Read-only. Confirms `sudo`, that Splunk is installed and running, that the vault
credentials actually authenticate, whether the `splunk-otel-collector` unit exists,
whether Go and `ocb` are available, and whether anything already holds port 57444.

It fails early and specifically. The most common stop is having no collector binary and no
way to build one, which reports exactly which of the three escape hatches to use.

### Stage 02 — index and HEC token

Creates `evpn_assurance` with `-datatype metric`, then asserts the datatype through REST.
This assertion matters: the OTel HEC exporter emits metric points, and an **event** index
accepts the HTTP POST and then silently discards them. The symptom is indistinguishable
from a dead collector.

Then it enables HEC and creates a token scoped to that index. Both steps are idempotent —
an existing index or token is reused, so re-running never invalidates a live collector.

### Stage 03 — build the collector

Puts `otelcol-yangfix` at `/usr/local/bin`. See [Building the collector](#building-the-collector).
No-op if the binary is already there.

### Stage 04 — deploy the collector

Renders [`agent_config.yaml.j2`](otel-collector/agent_config.yaml.j2) with the HEC token
(mode `0640`, root-owned), then makes systemd run it. Two shapes, decided by whether the
host already has a collector package:

| Host state | What stage 04 does |
| --- | --- |
| No `splunk-otel-collector.service` | Creates an `otelcol` system account and installs its own unit. Safe because `otelcol-yangfix` is a static Go binary with no package dependencies. **This is the lab Splunk host.** |
| Unit already present | Installs only an `ExecStart` drop-in, leaving the package alone. Reversible — delete `override.conf` and the stock binary returns. |

Either way it reloads, restarts, waits for port 57444, then reads
`systemctl show -p ExecStart` back and asserts it matches the binary that was requested.

> **Expect a telemetry gap of up to `TimeoutStopSec` on restart.** The fabric holds
> long-lived gRPC streams that do not drain on `SIGTERM`, so systemd waits and then kills
> the process. This is normal.

### Stage 05 — render the lookups

Runs entirely on the control node. Reads the `DEFN-*.j2` files and `settings.json` out of
`01_campus/evpn`, concatenates them into one Jinja scope, appends the same
`zz-defn-extract-epilogue.j2` that stage 11 of the campus collection uses, renders the
fabric intent to JSON, and templates both CSVs from it.

This is the part worth understanding, because it removes the pipeline's nastiest failure
mode. Every panel does:

```spl
| mstats ... BY "cisco.node_id" | `evpn_lookup`
```

and `evpn_lookup` expands to `rename "cisco.node_id" AS hostname | lookup
evpn_device_inventory hostname OUTPUT site role ...`. If `hostname` does not match exactly
what the collector emits as `cisco.node_id`, every panel renders correctly and returns
nothing. Generating the CSV from the same DEFN files that named the devices makes that
mismatch impossible.

For Site 105 that produces:

| hostname | loopback | role |
| --- | --- | --- |
| `Site_105-Leaf1.corp.pseudoco.com` | 172.30.255.1 | `leaf` |
| `Site_105-Leaf2.corp.pseudoco.com` | 172.30.255.2 | `leaf` |
| `Site_105-Border-Spine.corp.pseudoco.com` | 172.30.255.3 | `border-spine` |

> Site 105 folds spine, route-reflector and border onto one node, so it gets the single
> role `border-spine` rather than two rows. The lookup is keyed on `hostname` and would
> only ever return the first match. The Details view's role selector offers
> **Leafs** and **Border-Spine** to match.

### Stage 06 — deploy the app

`build-app.sh` reads the version from `default/app.conf`, rsyncs the app (excluding
`local/`, `.DS_Store`, `__pycache__`), and tars it into `packaging/dist/<app>-<version>.spl`.
The package is uploaded, installed with `-update 1`, and splunkd is restarted.

Afterwards the installed `build` number is read back and asserted against the source.
Splunk will keep serving a cached older app if an install half-fails, and the build number
is the only reliable signal.

> **Bump `build` in `default/app.conf` whenever a dashboard changes**, or the assertion
> cannot tell old from new.

### Stage 07 — fabric telemetry cross-check

Read-only. Asserts that `telemetry.splunk` for this site in the campus `settings.json`
actually targets this collector's IP, port and a non-empty role list — then prints the
campus playbooks to run. It deliberately does **not** configure the switches; see below.

### Stage 08 — verify

Five checks, one per hop, so a failure localises the break:

| Check | Proves |
| --- | --- |
| Collector service running | `systemctl is-active` |
| Fabric devices streaming | Established TCP sessions on port 57444 |
| HEC export failures | `otelcol_exporter_send_failed_metric_points` is 0 |
| Nodes resolving through the lookup | An `mstats` probe joined through `evpn_lookup` returns rows |
| Dashboard Studio validation | `tools/validate_studio.py` exits 0 |

Writes `evidence/assurance-verification.md` and `.html` in the same shape as the campus
stage 11 report, then fails the play if any check did not pass.

## Relationship to the campus collection

The switch-side configuration lives in `01_campus/evpn`, not here. Duplicating that
pipeline would create two places that can disagree about what the fabric is running.

```
Settings/settings.json
  telemetry.splunk.{enabled, receiver_ip, receiver_port, roles}
          │
          │  stage 06 template_sync substitutes the literal placeholders
          ▼
DEFN-TELEMETRY-SPLUNK.j2      {{ TELEMETRY_RECEIVER_IP }} → 198.18.5.109
FABRIC-TELEMETRY-SPLUNK.j2    {{ TELEMETRY_ROLE_GUARD }}  → DEVICE_HOSTNAME in DEFN_NODE_ROLES['SPINE'] or …
          │
          │  stage 09 deploy_composite pushes the rendered CLI
          ▼
telemetry ietf subscription 40101…40121 on each fabric node
          │
          │  stage 11 verify_intent confirms Valid + Connected
          ▼
07_assurance/splunk_evpn  ← this collection
```

Setting `telemetry.splunk.enabled` to `false` blanks the receiver IP, which makes
`FABRIC-TELEMETRY-SPLUNK.j2` render nothing at all. That is the supported way to keep the
fabric silent.

## Building the collector

`otelcol-yangfix` is the stock collector rebuilt with the patched `yang_grpc` receiver. The
source bundle ([`receiver_yang_26_05_27.tar.gz`](otel-collector/receiver_yang_26_05_27.tar.gz),
49 KB) is tracked in git precisely so the binary can always be rebuilt.

The lab Splunk appliance normally has neither a Go toolchain nor internet egress, so the
default is to build elsewhere and stage the result.

**On a host with Go 1.25+ and `ocb` v0.150.0** (the script server, or your laptop):

```bash
mkdir -p /tmp/otelbuild/src && cd /tmp/otelbuild
cp <repo>/ansible-automation/07_assurance/splunk_evpn/otel-collector/builder.yaml .
tar -xzf <repo>/.../otel-collector/receiver_yang_26_05_27.tar.gz -C ./src
ocb --config builder.yaml          # → ./_build/otelcol-yangfix
```

> **The layout matters.** `builder.yaml` replaces the upstream receiver module with
> `../src/receiver/yanggrpcreceiver`. That path is copied verbatim into `_build/go.mod`,
> so Go resolves it relative to `_build/` — not to the directory you ran `ocb` from. Keep
> `builder.yaml` and `src/` as siblings, with `_build/` generated beside them, or the build
> fails with `reading src/receiver/yanggrpcreceiver/go.mod: no such file or directory`.

Then:

```bash
ansible-playbook playbooks/00_assurance_deploy.yml \
  -e otel_staged_binary=/tmp/otelbuild/_build/otelcol-yangfix
```

**If the Splunk host does have Go and `ocb`**, build in place instead:

```bash
ansible-playbook playbooks/03_build_collector.yml -e otel_build_mode=local
```

**To skip the patch entirely** — accepting that per-VNI panels will be empty:

```bash
ansible-playbook playbooks/00_assurance_deploy.yml -e otel_use_custom_binary=false
```

## Running the playbooks

```bash
cd ansible-automation/07_assurance/splunk_evpn/ansible

# Everything, in order
ansible-playbook playbooks/00_assurance_deploy.yml -e otel_staged_binary=/tmp/otelcol-yangfix

# Read-only: is the host ready?
ansible-playbook playbooks/01_preflight.yml

# Read-only: is the pipeline healthy?
ansible-playbook playbooks/08_verify_assurance.yml

# Regenerate the lookups after a fabric change, then republish the app
ansible-playbook playbooks/05_render_lookups.yml
ansible-playbook playbooks/06_deploy_splunk_app.yml

# Redeploy the collector with a new HEC token
ansible-playbook playbooks/04_deploy_collector.yml -e splunk_hec_token=<token>

# Point at a different site
ansible-playbook playbooks/05_render_lookups.yml -e assurance_site=Site-106
```

### Debug mode

```bash
ansible-playbook playbooks/05_render_lookups.yml -e assurance_debug=true
```

| Variable | Contents |
| --- | --- |
| `_assurance_intent` | The full extracted fabric intent — node roles, loopbacks, VRFs, overlay, telemetry subscriptions |
| `_telemetry_splunk` | The `telemetry.splunk` block resolved for `assurance_site` |

Credentials are wrapped in `no_log: true` throughout, so debug output stays safe to paste.

## Playbook ordering dependency

```
00_scriptserver_bootstrap     bootstrap the control node
            │
            ▼
01_campus/evpn  01 ─▶ 09      build the fabric
            │   06 template_sync    substitutes telemetry.splunk into the templates
            │   09 deploy_composite pushes the subscriptions
            ▼
07_assurance/splunk_evpn
   01 preflight        read-only
   02 index + HEC      additive
   03 build collector  additive
   04 deploy collector DISRUPTIVE  ~90 s telemetry gap
   05 render lookups   local only
   06 deploy app       DISRUPTIVE  splunkd restart
   07 fabric check     read-only
   08 verify           read-only   → evidence/
            │
            ▼
01_campus/evpn  11_verify_intent    confirms subscriptions Valid + receivers Connected
```

## Troubleshooting

| Symptom | Likely cause | Resolution |
| --- | --- | --- |
| `you must install the sshpass program` | Stale checkout still using the `ssh` transport | `git pull` — this collection uses `paramiko`, which needs no apt package. Do **not** try to apt-install sshpass on the Kali image; it drags `libc6` forward and apt refuses |
| `'dict object' has no attribute 'splunk_server'` | Stale checkout, or the vault entry is missing | `git pull`, then check `ansible-vault view "Lab Topology/lab_access.yml"` contains `splunk_server` |
| Preflight: "paramiko is not importable" | Playbook running outside the bootstrapped venv | `~/venv/bin/ansible-playbook`, or reinstall `ansible-automation/requirements.txt` |
| Preflight: "No Splunk binary at /opt/splunk/bin/splunk" | Splunk installed elsewhere | `-e splunk_home=/path/to/splunk` |
| Preflight: "No 'splunk_server' entry" | The Linux SSH account is missing from the vault | `ansible-vault edit "Lab Topology/lab_access.yml"` and add it; it is not the same account as `Splunk Enterprise` |
| Preflight: "no Go/ocb toolchain and otel_staged_binary is unset" | Nothing to install | Build elsewhere and pass `-e otel_staged_binary=...`, or `-e otel_use_custom_binary=false` |
| Preflight: port 57444 already in use | A stale collector, or another listener | `sudo ss -lntp \| grep 57444`, stop the owner |
| Stage 02 fails on datatype | `evpn_assurance` already exists as an **event** index | Delete and recreate it as `metric`; event indexes silently discard metric points |
| Dashboards render but every panel is empty | `cisco.node_id` does not match the lookup `hostname` | Run `\| mstats latest("cisco.cp-vnis.") WHERE index=evpn_assurance BY "cisco.node_id"` and compare against `evpn_device_inventory.csv`; re-run stage 05 |
| Per-VNI panels empty, others fine | Stock collector dropping numeric YANG keys | Confirm `systemctl show -p ExecStart splunk-otel-collector` points at `otelcol-yangfix` |
| No sessions on port 57444 | Fabric is not dialling out | `show telemetry ietf subscription all receivers` on a switch; check `receiver_ip` in settings.json; re-run campus stages 06 and 09 |
| Subscriptions show `Invalid` | XPath rejected by this IOS-XE release | Namespace-prefixed XPaths are rejected — use plain absolute paths. See [`Model Maps/`](Model%20Maps/) |
| HEC export failures climbing | Bad token, or index not writable by it | Re-run stage 02; it reuses or recreates the token |
| Telemetry gap after a deploy | Expected | The collector does not drain gRPC streams on `SIGTERM`; ~90 s |
| App installs but dashboards look old | Build number not bumped, or a cached browser | Bump `build` in `default/app.conf`; hard-refresh Splunk Web |
| `validate_studio.py` reports 0-row panels | No data in the window, not an error | Only structural and SPL errors fail the stage |

## Credits

Ported from the standalone *Campus BGP EVPN VXLAN Catalyst Center Automation and Splunk
Assurance* project and adapted to the Cisco One Experience lab: retargeted from a 6-node
CML fabric to Site 105, credentials moved into the repo vault, and manual setup replaced
with the staged playbooks above.
