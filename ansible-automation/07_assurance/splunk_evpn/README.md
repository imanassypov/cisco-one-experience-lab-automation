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
  Site_105-Leaf2           dial-out    │ otelcol-contrib.service              │
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
| Collector | `otelcol-contrib` **≥ 0.161.0**, installed from the official release package by stage 03 |
| Control node | The Kali script server, bootstrapped by [`00_scriptserver_bootstrap`](../../00_scriptserver_bootstrap/) |

No extra Galaxy collections are needed — every task is `ansible.builtin`. No compiler or Go
toolchain is needed either.

> **Why the 0.161.0 floor?** The `yang_grpc` receiver only began emitting numeric YANG list
> keys (`vni`, `evni`, `vlan-id`) as dimensions in that release. Up to and including
> v0.155.0 it gated key extraction on the protobuf value being a string, so every per-VNI
> series silently collapsed into one — dashboards rendered correctly and showed nothing.
> Full analysis:
> [`otel-collector/yanggrpcreceiver-numeric-key-issue.md`](otel-collector/yanggrpcreceiver-numeric-key-issue.md).

> **Transport note.** The Splunk host is reached with `ansible.builtin.paramiko_ssh`, not the
> default OpenSSH transport. Credentials live in the vault as a password, and the ssh
> transport would need `sshpass` — which cannot be installed on the Kali script server,
> because it pulls `libc6` forward and apt refuses against the pinned `libc6-dev`. paramiko
> does password auth in-process and is already pinned in
> [`ansible-automation/requirements.txt`](../../requirements.txt).

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
│   │   ├── 03_install_collector.yml   Install otelcol-contrib from its release package
│   │   ├── 04_deploy_collector.yml    Config + systemd + restart  (disruptive)
│   │   ├── 05_render_lookups.yml      Generate lookups from fabric intent (local)
│   │   ├── 06_deploy_splunk_app.yml   Package + install the app     (disruptive)
│   │   ├── 07_enable_fabric_telemetry.yml  Read-only campus cross-check
│   │   └── 08_verify_assurance.yml    Read-only end-to-end proof
│   ├── roles/
│   │   ├── splunk_preflight/          Probe Splunk, systemd, toolchain, receiver port
│   │   ├── splunk_index_hec/          Create the metrics index and HEC token
│   │   ├── otel_collector_install/    Download and install the collector package
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
│   ├── agent_config.yaml.j2           Rendered to /etc/otelcol-contrib/config.yaml
│   └── yanggrpcreceiver-numeric-key-issue.md   Why the 0.161.0 version floor exists
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
   ansible-playbook playbooks/10_deploy_composite.yml
   ```

4. **Run this collection:**

   ```bash
   cd ../../../07_assurance/splunk_evpn/ansible
   ansible-playbook playbooks/00_assurance_deploy.yml
   ```

   Stage 03 downloads and installs the collector package, so there is nothing to build or
   stage beforehand. The Splunk host needs a route to `github.com` for that one step.

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
| `otel_package_version` | `0.161.0` | **Floor, not a preference** — earlier releases drop numeric YANG list keys |
| `otel_package_name` | `otelcol-contrib` | The core distribution does not carry `yang_grpc` |
| `otel_package_base_url` | GitHub releases | Override for an internal mirror |
| `otel_binary` | `/usr/bin/otelcol-contrib` | Installed by the package |
| `otel_config_path` | `/etc/otelcol-contrib/config.yaml` | Rendered collector config (gitignored — carries the token) |
| `otel_service_name` | `otelcol-contrib` | systemd unit, owned by the package |
| `assurance_site` | `Site-105` | Matches `HierarchyBldg` in settings.json and the `site` column in the lookups |
| `assurance_debug` | `false` | Dump the extracted fabric intent in stage 05 |

## How it works

### Stage 01 — preflight

Read-only. Confirms the vault carries both credential sets, that `sudo` works, that Splunk
is installed and running, that the admin credentials actually authenticate, whether the
collector package is already present and at what version, whether the release is reachable
at all, and whether anything already holds port 57444.

It fails early and specifically, so a missing vault entry or an unreachable Splunk reports
itself here rather than halfway through a deploy.

### Stage 02 — index and HEC token

Creates `evpn_assurance` with `-datatype metric`, then asserts the datatype through REST.
This assertion matters: the OTel HEC exporter emits metric points, and an **event** index
accepts the HTTP POST and then silently discards them. The symptom is indistinguishable
from a dead collector.

Then it enables HEC and creates a token scoped to that index. Both steps are idempotent —
an existing index or token is reused, so re-running never invalidates a live collector.

### Stage 03 — install the collector

Downloads the official `otelcol-contrib` release package matching the host's OS family and
architecture, and installs it from the local file rather than through a repo — so a host
with a broken package index still works. No-op when the pinned version is already present.

Then it runs `otelcol-contrib components` and **asserts `yang_grpc` is in the list**. The
core distribution does not carry that receiver; a wrong package would start cleanly and
then give the fabric nothing to dial into.

### Stage 04 — deploy the collector

Renders [`agent_config.yaml.j2`](otel-collector/agent_config.yaml.j2) with the HEC token
over the config the package ships (`0640`, owned by the packaged service account), then
restarts. The package owns the unit, binary and user, so there is nothing to override.

> **Expect a telemetry gap on restart.** The fabric holds long-lived gRPC streams that do
> not drain on `SIGTERM`, so systemd waits out `TimeoutStopSec` before the new process
> starts listening. This is normal.

### Stage 05 — render the lookups

Runs entirely on the control node. Nothing is written to the Splunk host, and nothing
outside `splunk-app/.../lookups/` is modified.

**Why this stage exists.** Every dashboard panel joins telemetry to context through the
device inventory:

```spl
| mstats latest("cisco.cp-vnis.") WHERE `evpn_index` BY "cisco.node_id" | `evpn_lookup`
```

where `evpn_lookup` expands to
`rename "cisco.node_id" AS hostname | lookup evpn_device_inventory hostname OUTPUT site role ...`.

If `hostname` does not match **exactly** what the collector emits as `cisco.node_id`, every
panel renders correctly and returns nothing. That is the nastiest failure mode in this
system, because it looks like "no data" rather than an error — no panel goes red, no search
logs a warning. Generating the CSV from the same files that named the devices in the first
place removes the possibility of drift.

> **The key is the SHORT hostname.** IOS-XE builds `node_id_str` from the bare `hostname`
> command and does not append `ip domain name`, so the fabric emits `Site_105-Leaf1` while
> the DEFN intent keys (and Catalyst Center inventory) use
> `Site_105-Leaf1.corp.pseudoco.com`. The lookup templates strip the domain for the
> `hostname` column and keep the FQDN in `source`. This bit us on 2026-09-19: generating
> from intent is necessary but not sufficient, because intent is keyed differently from
> telemetry. There is no device-side option to send the FQDN — the
> `telemetry ietf subscription` submode has no node-id knob (checked on IOS-XE 26.01.02).
> The same rule applies to `overlay_leaves` / `access_leaves` in the segment lookup, which
> `executive_overview` splits and renames to `cisco.node_id` before joining.

**How it works.** The `DEFN-*.j2` files are pure `{% set %}` blocks — data, no output. So
concatenating them puts every variable in a single Jinja scope, and an epilogue appended
last emits the lot as JSON:

```
01_campus/evpn/Catalyst Center Templates/Site BGP EVPN Templates/
  DEFN-ROLES.j2 ┐
  DEFN-VRF.j2   ├─ copied to a tempdir as 00-, 01-, 02-… so order is deterministic
  DEFN-OVERLAY.j2 ┤   and the zz- epilogue always sorts last
  …             ┘
        │
        │  assemble  →  extract.j2
        ▼
  {{ {"node_roles": DEFN_NODE_ROLES, "loop_underlay": DEFN_LOOP_UNDERLAY,
      "overlay": DEFN_OVERLAY, "vrfs": DEFN_VRF, …} | to_json }}
        │
        │  render  →  intent.json
        ▼
  evpn_device_inventory.csv     evpn_segment_inventory.csv
```

Three details that are load-bearing:

- **The epilogue is shared with the campus collection.** Stage 05 uses the very same
  [`zz-defn-extract-epilogue.j2`](../../01_campus/evpn/ansible/roles/verify_intent/files/zz-defn-extract-epilogue.j2)
  that stage 12 uses to verify intent, so the two collections cannot disagree about what
  the fabric is. Adding a field there makes it available to both.
- **Placeholders are substituted first.** `DEFN-TELEMETRY-SPLUNK.j2` carries literal
  `{{ TELEMETRY_RECEIVER_IP }}` markers that `template_sync` fills at sync time. Left
  alone, `{% set X = {{ Y }} %}` is a Jinja syntax error, so stage 05 applies the same
  substitution before rendering — which is also why the telemetry receiver and
  subscription IDs end up in the extracted intent.
- **`copy:` with `content:` is not re-templated.** Ansible renders the expression once;
  the `{% set %}` blocks in the result pass through untouched.

**Assembling it by hand** is occasionally useful when a DEFN change breaks the render:

```bash
ansible-playbook playbooks/05_render_lookups.yml -e assurance_debug=true
```

That dumps `_assurance_intent` — the full extracted structure — before the CSVs are
written.

**What it produces for Site 105:**

| hostname | loopback | role |
| --- | --- | --- |
| `Site_105-Leaf1.corp.pseudoco.com` | 172.30.255.1 | `leaf` |
| `Site_105-Leaf2.corp.pseudoco.com` | 172.30.255.2 | `leaf` |
| `Site_105-Border-Spine.corp.pseudoco.com` | 172.30.255.3 | `border-spine` |

and one segment row per overlay VLAN, with `l2vni = L2VNIOFFSET + vlan` and the `l3vni`
taken from the matching `DEFN_VRF` entry:

| vlan | l2vni | l3vni | vrf |
| --- | --- | --- | --- |
| 10 | 100010 | 110010 | Main |
| 101 | 100101 | 110101 | PROD |
| 102 | 100102 | 110102 | IOT |

> Site 105 folds spine, route-reflector and border onto one node, so it gets the single
> role `border-spine` rather than two rows. The lookup is keyed on `hostname` and would
> only ever return the first match. The Details view's role selector offers
> **Leafs** and **Border-Spine** to match.

> **The generated CSVs are committed**, so the repo always shows what the dashboards are
> joining against — but they are generated output. Re-run this stage after any fabric
> change rather than editing them by hand.

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
stage 12 report, then fails the play if any check did not pass.

#### 3/5 with the last two checks failing — look at the Splunk licence first

> **This is a pod fault, not a pipeline fault.** Before chasing `cisco.node_id`
> or a broken panel query, check whether Splunk will run *any* search at all.

If stage 08 reports exactly this:

```text
3/5 checks passed.
Failed: Nodes resolving through the device inventory lookup; Dashboard Studio validation.
```

…note which checks passed. The first three test the **write** path and never run
SPL — `systemctl is-active`, the `ss` session count, and the collector's own
`:8888/metrics` counter. The last two are the only ones that **search**. When
those two fail together and the first three pass, the telemetry pipeline is
healthy end to end and Splunk is refusing to search.

Confirm it by running the verify role's own probe by hand. A licence stop looks
like this, and has nothing to do with your data:

```text
[FATAL] Error in 'mstats' command: Your Splunk license expired or you have
exceeded your license limit too many times.
```

The appliance-side detail is in two REST endpoints. Neither needs search, so
both still answer when searching is dead:

```bash
curl -sk -u <admin> "https://198.18.5.109:8089/services/licenser/localslave?output_mode=json"
curl -sk -u <admin> "https://198.18.5.109:8089/services/messages?output_mode=json"
```

Observed on a broken pod (2026-09-22):

```text
"LocalSearch": "DISABLED_DUE_TO_GRACE_PERIOD"
manager_uri:                       https://dcloud-lm.splunk.show:8089
last_manager_contact_success_time: 2026-05-09        # months ago
last_manager_contact_attempt_time: now               # still retrying, still failing

[warn] LM__FAILED_TO_CONECT_TO_MANAGER
  Failed to contact license manager: reason='WARN: path=/masterlm/usage:
  Signature mismatch between license slave=<pod NAT ip> and this License Master.
  Please make sure that the pass4SymmKey setting in server.conf, under [general],
  is the same for the License Master and all its slaves'
```

The lab's Splunk is a **licence peer of the shared dCloud licence manager**
`dcloud-lm.splunk.show`. When the host is cloned or restored without its
`[general] pass4SymmKey` being reconciled, it can never check in; once the
72-hour grace period lapses, `LocalSearch` is disabled and splunkd refuses any
search that reads a **non-internal** index. Connectivity is a red herring — DNS
resolves and TCP 8089 connects even with the wrong key, so a reachability test
proves nothing.

The most convincing detail is that **the licence manager answers**. It receives
the request, checks the signature, rejects it, and sends that sentence back. So
the pod's path out to `dcloud-lm.splunk.show` is healthy and this is a refused
login, not a network problem. Two more readings confirm the host has no
entitlement of its own: `licenser/licenses` returns zero installed licences and
`licenser/groups` shows no active group.

Read the timestamps carefully, because they say different things:

| Field | What it tells you |
| --- | --- |
| `last_manager_contact_success_time` | When the licence actually last worked. This dates the outage. |
| `first failure time=` in the message | Only the failures since the last splunkd restart. The message is posted fresh at every startup, so a fault running for months shows today's date here. |

Treat a today's date in `first failure time=` as meaningless on its own — it
does not mean the problem just started. To tell whether splunkd restarted, list
the messages and compare the `timeCreated_iso` values: if they all land within a
few seconds of each other, that is a startup sequence, not several faults
appearing at once. `NoAllowedDomainsList` only ever appears at startup, so its
presence alongside the others confirms it.

To date the fault properly, count the retries in the log instead — this survives
restarts because it reads the indexed history:

```spl
index=_internal component=LMTracker "Signature mismatch" | timechart span=1h count
```

A steady count every hour (roughly 60, as it retries once a minute) is a
continuous fault. That, with `last_manager_contact_success_time`, is what to put
in an escalation.

Often seen alongside it on a degraded pod: `KVSTORE_FAILED` /
`KVSTORE_PROCESS_TERMINATED` (mongod exiting with code 1). That is a separate
fault and worth reporting, but it does **not** cause the lookup check to fail —
`evpn_device_inventory.csv` is a file lookup, so `| inputlookup` keeps working
with KV Store down. It has its own section below, because it looks like the
deploy playbook broke it.

#### KV Store fails right after the deploy playbook runs — the certificate expired

The deploy role ends with `splunk restart`, so the KV Store errors appear
moments after the playbook finishes and it looks like the app install broke
something. It did not. The restart is the trigger, not the cause.

mongod checks its certificate only when it starts. Once running it never looks
again, so an expired certificate goes unnoticed until something restarts
splunkd — and on a lab pod that is usually this playbook, weeks after the
certificate lapsed.

Confirm it with mongod's own reason:

```spl
index=_internal source=*mongod.log* id=20574 | head 1 | table _raw
```

```json
{
  "code": 140,
  "codeName": "InvalidSSLConfiguration",
  "errmsg": "ssl client initialization problem for certificate:
             /opt/splunk/etc/auth/mycerts/server.pem :: caused by ::
             The provided SSL certificate is expired or not yet valid.
             notBefore 2025-07-17 ... notAfter 2026-07-22 ..."
}
```

The same certificate is on the management port, so you can read its dates
without logging into the host:

```bash
echo | openssl s_client -connect 198.18.5.109:8089 2>/dev/null \
  | openssl x509 -noout -subject -dates
```

It is set once in `server.conf` and inherited:

| Stanza | Setting | Value on the lab pod |
| --- | --- | --- |
| `[sslConfig]` | `serverCert` | `/opt/splunk/etc/auth/mycerts/server.pem` |
| `[sslConfig]` | `sslRootCAPath` | `/opt/splunk/etc/auth/mycerts/chain.pem` |
| `[kvstore]` | `sslKeysPath` | not set — so KV Store uses the `[sslConfig]` certificate |

Read those over REST rather than hunting through files:
`GET /services/properties/server/sslConfig` and `.../server/kvstore`.

**To prove the playbook is not responsible**, compare when splunkd started with
when KV Store failed:

```spl
index=_internal sourcetype=splunkd "Splunkd starting" | timechart span=1d count
index=_internal sourcetype=splunkd ("KV Store changed status to failed" OR "KVStore process terminated") | timechart span=1d count
```

Every KV Store failure lands on a day splunkd started, and the certificate
expiry predates all of them. On 2026-09-24 the pod showed two starts and six
failures, against a certificate that had expired on 2026-07-22 — the fault was
waiting for any restart, and the playbook happened to be the first one.

**Fix.** Replace the expired certificate, or point Splunk back at its own
generated one. Both need root on the Splunk host and a restart, and the
certificate belongs to the pod build rather than to this repo, so treat it as an
escalation. There is no setting that makes mongod overlook its own expired
certificate.

**Impact on this collection is small.** Telemetry, indexing and the dashboards
are unaffected, and the lookup is a CSV file. The Ansible here connects with
certificate validation turned off, so an expired certificate does not break the
playbooks either. Report it as pod health rather than a pipeline failure.

Internal indexes stay searchable, which is why the instance looks alive:

| Search | Under this fault |
| --- | --- |
| `index=_internal`, `index=_audit` | works — internal indexes are exempt |
| `\| makeresults`, `\| inputlookup` | works — reads no index |
| `index=main` or any other event index | `FATAL … litsearch … license expired` |
| `\| mstats` / `\| msearch` on `evpn_assurance` | `FATAL … license expired` |

> **Settings > Licensing will show no alerts, and that is expected.** Licence
> *alerts* are daily-volume violations, and those are tracked on the licence
> **manager**, not on a peer — the Alerts tab reads `/services/licenser/messages`,
> which is empty on a healthy peer too. This fault is a peer-registration
> failure, so it surfaces as a general splunkd message instead: look at the 🔔
> **bell icon** in the top-right nav, not at the Licensing page.

Prove your own pipeline is healthy without searching, straight off the index:

```bash
curl -sk -u <admin> "https://198.18.5.109:8089/services/data/indexes/evpn_assurance?output_mode=json"
```

`datatype: metric` with `totalEventCount` climbing and `maxTime` at the current
minute means every hop through HEC works and only the read path is blocked.
`| inputlookup evpn_device_inventory.csv` also still works, so you can confirm
stage 05 produced correct domain-stripped hostnames while search is down.

**Resolution.** The matching `pass4SymmKey` is a dCloud secret; it cannot be
derived locally, and guessing at a shared host's `server.conf` is not a fix.
Raise it with the proctor, or request a pod reset. Once the key matches and
splunkd restarts, search returns immediately and a plain re-run of
`playbooks/08_verify_assurance.yml` goes 5/5 with no change to this collection.
Converting the instance to a standalone licence is possible, but the Free tier
**disables authentication entirely**, which changes how every REST call in this
collection authenticates — do not do it without the lab owner's decision.

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
          │  stage 10 deploy_composite pushes the rendered CLI
          ▼
telemetry ietf subscription 40101…40121 on each fabric node
          │
          │  stage 12 verify_intent confirms Valid + Connected
          ▼
07_assurance/splunk_evpn  ← this collection
```

Setting `telemetry.splunk.enabled` to `false` blanks the receiver IP, which makes
`FABRIC-TELEMETRY-SPLUNK.j2` render nothing at all. That is the supported way to keep the
fabric silent.

## The collector

Stage 03 installs upstream `otelcol-contrib` from its official release package — the same
binary anyone else would run. There is no fork, no patch and no build step.

That was not always true. This work originally shipped a patched `yang_grpc` receiver,
because the upstream one discarded numeric YANG list keys. Upstream has since fixed it,
using the same approach, so the patch is gone and the version floor replaces it.

| Release | `extractKeys` behaviour |
| --- | --- |
| ≤ v0.155.0 | Gated on `field.ValueByType.(*pb.TelemetryField_StringValue)` — numeric keys dropped |
| ≥ v0.161.0 | `formatValueToString(subField)` with no type gate — numeric keys emitted |

So `otel_package_version` is a **floor, not a preference**. Pinning below 0.161.0 gives you
dashboards that render perfectly and show nothing on every per-VNI panel. Stage 03 asserts
`yang_grpc` is in `otelcol-contrib components` for the same reason — the *core*
distribution does not carry that receiver.

To move to a newer release:

```bash
ansible-playbook playbooks/03_install_collector.yml -e otel_package_version=0.162.0
ansible-playbook playbooks/08_verify_assurance.yml     # confirms the dimensions still join
```

The receiver is **alpha** stability upstream, so verify after bumping rather than assuming.

### No route to GitHub

Stage 03 downloads from `github.com`. If the Splunk host cannot reach it, fetch the package
elsewhere and install it by hand, then run stage 04 onwards:

```bash
curl -fLO https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.161.0/otelcol-contrib_0.161.0_linux_amd64.deb
sudo apt-get install -y ./otelcol-contrib_0.161.0_linux_amd64.deb   # or: sudo rpm -Uvh <rpm>
```

Point `otel_package_base_url` at an internal mirror to automate that.

## Running the playbooks

```bash
cd ansible-automation/07_assurance/splunk_evpn/ansible

# Everything, in order
ansible-playbook playbooks/00_assurance_deploy.yml

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
   01 preflight         read-only
   02 index + HEC       additive
   03 install collector additive    upstream contrib package
   04 deploy collector  DISRUPTIVE  telemetry gap while the service restarts
   05 render lookups   local only
   06 deploy app       DISRUPTIVE  splunkd restart
   07 fabric check     read-only
   08 verify           read-only   → evidence/
            │
            ▼
01_campus/evpn  12_verify_intent    confirms subscriptions Valid + receivers Connected
```

## Troubleshooting

| Symptom | Likely cause | Resolution |
| --- | --- | --- |
| `you must install the sshpass program` | Stale checkout still using the `ssh` transport | `git pull` — this collection uses `paramiko`, which needs no apt package. Do **not** try to apt-install sshpass on the Kali image; it drags `libc6` forward and apt refuses |
| `'dict object' has no attribute 'splunk_server'` | Stale checkout, or the vault entry is missing | `git pull`, then check `ansible-vault view "Lab Topology/lab_access.yml"` contains `splunk_server` |
| Preflight: "paramiko is not importable" | Playbook running outside the bootstrapped venv | `~/venv/bin/ansible-playbook`, or reinstall `ansible-automation/requirements.txt` |
| Preflight: "No Splunk binary at /opt/splunk/bin/splunk" | Splunk installed elsewhere | `-e splunk_home=/path/to/splunk` |
| Preflight: "No 'splunk_server' entry" | The Linux SSH account is missing from the vault | `ansible-vault edit "Lab Topology/lab_access.yml"` and add it; it is not the same account as `Splunk Enterprise` |
| Preflight: "release download NOT reachable" | No route to github.com | Install the package by hand, or point `otel_package_base_url` at a mirror |
| Stage 03: "has no yang_grpc receiver" | Core distribution installed instead of contrib | `otel_package_name` must be `otelcol-contrib` |
| Preflight: port 57444 already in use | A stale collector, or another listener | `sudo ss -lntp \| grep 57444`, stop the owner |
| Stage 02 fails on datatype | `evpn_assurance` already exists as an **event** index | Delete and recreate it as `metric`; event indexes silently discard metric points |
| Dashboards render but every panel is empty | `cisco.node_id` does not match the lookup `hostname` | Run `\| mstats latest("cisco.cp-vnis.") WHERE index=evpn_assurance BY "cisco.node_id"` and compare against `evpn_device_inventory.csv`; re-run stage 05 |
| Per-VNI panels empty, others fine | Collector older than 0.161.0 dropping numeric YANG keys | `otelcol-contrib --version` on the Splunk host; re-run stage 03 |
| No sessions on port 57444 | Fabric is not dialling out | `show telemetry ietf subscription all receivers` on a switch; check `receiver_ip` in settings.json; re-run campus stages 06 and 09 |
| Subscriptions show `Invalid` | XPath rejected by this IOS-XE release | Namespace-prefixed XPaths are rejected — use plain absolute paths. See [`Model Maps/`](Model%20Maps/) |
| HEC export failures climbing | Bad token, or index not writable by it | Re-run stage 02; it reuses or recreates the token |
| Telemetry gap after a deploy | Expected | The fabric's gRPC streams do not drain on `SIGTERM`, so systemd waits out `TimeoutStopSec` |
| App installs but dashboards look old | Build number not bumped, or a cached browser | Bump `build` in `default/app.conf`; hard-refresh Splunk Web |
| `validate_studio.py` reports 0-row panels | No data in the window, not an error | Only structural and SPL errors fail the stage |
| Stage 08 is 3/5, failing **both** the lookup check and Dashboard Studio validation, while the collector / session / HEC checks pass | Splunk search is disabled — the host lost its licence-peer registration with `dcloud-lm.splunk.show` (`pass4SymmKey` mismatch) and the grace period lapsed | Pod fault, not yours. Confirm with `/services/licenser/localslave` (`LocalSearch: DISABLED_DUE_TO_GRACE_PERIOD`) and `/services/messages`, then escalate — [detail above](#35-with-the-last-two-checks-failing--look-at-the-splunk-licence-first) |
| Any search returns `Your Splunk license expired or you have exceeded your license limit too many times` | Same as above | Same as above |

## Known gaps

### EVPN Route Statistics (sub 40113) is disabled on C9300

The **"EVPN Route Updates by Device"** and **"EVPN Route Updates by Role"** panels on the
executive overview will render empty, and the `evpn_route_update_deltas` macro returns no
rows. This is expected on the current image, not a misconfiguration.

The feature needs two things and the Catalyst 9300 supports neither on IOS-XE 17.12.01 or
26.01.02:

| Requirement | Observed |
| --- | --- |
| CLI `l2vpn evpn` → `telemetry enable` → `statistics` | `telemetry ?` under `config-evpn` → `% Unrecognized command`. Catalyst Center rejected the push with `NCTP10214 … Invalid CLI` |
| Subscription on `/evpn-oper-data/evpn-stats` | `40113  Configured Invalid  Invalid XPath filter: '/evpn-oper-data/evpn-stats'` |

Both were removed on 2026-09-19 — the CLI from
`FABRIC-TELEMETRY-SPLUNK.j2` and the subscription from `DEFN-TELEMETRY-SPLUNK.j2` — because
a rejected CLI aborts the remaining composite members for that device, and an invalid
subscription just consumes one of the 150 slots.

> **Removing it from the template does not remove it from the devices.** The composite
> deploy only adds configuration; it never deletes a subscription pushed by an earlier run.
> Until someone clears it, `show telemetry ietf subscription summary` will keep reporting
> `Invalid 1`. Clean it up once per switch with:
>
> ```text
> configure terminal
> no telemetry ietf subscription 40113
> ```

The dashboard panels and the `evpn_route_update_deltas` macro were deliberately left in
place so nothing needs rebuilding when the platform catches up.

> **TODO — re-test on the official IOS-XE 26.2 release.** Restore the enable block and sub
> 40113 **together**; neither is useful alone. Probe first, it is read-only and settles it
> in one command:
>
> ```text
> configure terminal
> l2vpn evpn
> telemetry ?
> ```
>
> If the keyword exists, restore the CLI as **two nested commands** (`telemetry enable`,
> then `statistics`) — not the single `telemetry enable statistics` line the template
> originally emitted, which was wrong independently of platform support. Both files carry
> the verbatim restore blocks in their header comments.

## Credits

Ported from the standalone *Campus BGP EVPN VXLAN Catalyst Center Automation and Splunk
Assurance* project and adapted to the Cisco One Experience lab: retargeted from a 6-node
CML fabric to Site 105, credentials moved into the repo vault, and manual setup replaced
with the staged playbooks above.
