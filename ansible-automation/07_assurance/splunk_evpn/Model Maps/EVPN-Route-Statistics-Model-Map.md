# EVPN Route Statistics — CLI ⇄ Operational Model Mapping

> **Source PDF:** `EVPN-CLI to Operational Model Mapping for EVPN Route Statistics-270526-203721.pdf`
> (the same mapping is also appended to both EVPN Manager Component PDFs).
> **Platform scope:** This feature is available **only on CAT9k platforms**.
> This document is a faithful, cleaned-up transcription of the Cisco mapping PDF. It maps the
> `show l2vpn evpn routes summary` CLI counters to the Cisco native YANG xpaths and internal TDL
> (Telemetry Definition Language) encoder paths.

---

## Why this matters for the Splunk EVPN Assurance pipeline

The dashboards in `campus_evpn_assurance` consume the route-count container
`/evpn-oper-data/evpn-stats/evpn-vni-rt-cnt` (TDL `ios_oper/evpn_stats/evpn-vni-rt-cnt`).

> **Telemetry note (cumulative counters):** Every `local-add` / `local-del` / `remote-add` /
> `remote-del` leaf is a **cumulative Update/Delete counter** — it only ever increases for the life
> of the route process. To chart "routes churn", take a `delta`/`rate` in Splunk rather than the raw
> gauge.

---

## Enablement requirement

Route statistics are **off by default** and must be enabled under the EVPN address family:

```text
l2vpn evpn
 telemetry enable
 statistics
```

Note these are **two nested commands**, not a single `telemetry enable statistics` line.

> **Not available on the Site-105 fabric (verified 2026-09-19).** The C9300 running
> IOS-XE 26.01.02 does not implement this keyword at all:
>
> ```text
> Site_105-Leaf1(config-evpn)#telemetry ?
> % Unrecognized command
> ```
>
> `show running-config all | include telemetry enable` also returns nothing, and the
> command is equally invalid on 17.12.01 — so this is a platform gap, not a release
> gate. Catalyst Center rejected it with `NCTP10214 … Invalid CLI`, which aborted the
> rest of the composite. The enable block was therefore removed from
> `FABRIC-TELEMETRY-SPLUNK.j2`.
>
> Consequence: **subscription 40113 (`/evpn-oper-data/evpn-stats`) will report no
> counters on this fabric**, so the "EVPN Route Updates" dashboard panels stay empty.
> The subscription is left configured so it starts working automatically if the fabric
> moves to a platform that supports the feature.

The reference topology adds two VLAN-based EVIs (1 and 2), an Ethernet Segment, and a Port-channel
access port, but the only config that gates these counters is `telemetry enable` + `statistics`.

### Show commands covered

| CLI command | Scope |
| --- | --- |
| `show l2vpn evpn routes summary` | All EVIs (aggregate) |
| `show l2vpn evpn routes vni <vni> summary` | Per-VNI |
| `show l2vpn evpn routes global summary` | Global (EAD/EVI, EAD/ES, ES only) |

Representative `show l2vpn evpn routes summary` output from the PDF:

```text
Route       Local Updates   Local Deletes   Remote Updates   Remote Deletes
EAD/EVI         0               0               4                3
EAD/ES          2               1               6                0
MAC             2               1               7                6
IMET            6               4               5                5
ES              2               1               9                0
IP-Prefix       4               2               8                6
Total          16               9              39               20
Last update: 1d01h ago
```

> The CLI `summary` table does not print a separate **MAC/IP** row, but the model **does** expose
> dedicated `mac-ip-cnt` counters in all four categories (see matrix below).

---

## Keys

**Container:** `/evpn-oper-data/evpn-stats` &nbsp;•&nbsp; **TDL:** `ios_oper/evpn_stats`

| YANG xpath | YANG type | TDL path | TDL type | Comments |
| --- | --- | --- | --- | --- |
| `/evpn-oper-data/evpn-stats/evpn-stats-id` | uint32_t | `ios_oper/evpn_stats` | u_int32 | **key** |
| `/evpn-oper-data/evpn-stats/evpn-vni-rt-cnt/vni` | uint32_t | `ios_oper/evpn_stats/evpn-vni-rt-cnt/vni` | u_int32 | per-VNI key |

---

## Route-count matrix

All counters live under `/evpn-oper-data/evpn-stats/evpn-vni-rt-cnt/` (TDL
`ios_oper/evpn_stats/evpn-vni-rt-cnt/`) and are **`uint64_t` / `u_int64`**. The leaf name is
`<category>/<route-type>-cnt`, where the category prefix selects the CLI column:

| Category prefix | Maps to CLI column |
| --- | --- |
| `local-add/` | **Local Updates** |
| `local-del/` | **Local Deletes** |
| `remote-add/` | **Remote Updates** |
| `remote-del/` | **Remote Deletes** |

| Route type | Leaf suffix | `local-add/` (Local Updates) | `local-del/` (Local Deletes) | `remote-add/` (Remote Updates) | `remote-del/` (Remote Deletes) |
| --- | --- | --- | --- | --- | --- |
| EAD/EVI | `ead-evi-cnt` | `local-add/ead-evi-cnt` | `local-del/ead-evi-cnt` | `remote-add/ead-evi-cnt` | `remote-del/ead-evi-cnt` |
| EAD/ES | `ead-es-cnt` | `local-add/ead-es-cnt` | `local-del/ead-es-cnt` | `remote-add/ead-es-cnt` | `remote-del/ead-es-cnt` |
| MAC | `mac-cnt` | `local-add/mac-cnt` | `local-del/mac-cnt` | `remote-add/mac-cnt` | `remote-del/mac-cnt` |
| MAC/IP | `mac-ip-cnt` | `local-add/mac-ip-cnt` | `local-del/mac-ip-cnt` | `remote-add/mac-ip-cnt` | `remote-del/mac-ip-cnt` |
| IMET | `imet-cnt` | `local-add/imet-cnt` | `local-del/imet-cnt` | `remote-add/imet-cnt` | `remote-del/imet-cnt` |
| ES | `es-cnt` | `local-add/es-cnt` | `local-del/es-cnt` | `remote-add/es-cnt` | `remote-del/es-cnt` |
| IP-Prefix | `ip-prefix-cnt` | `local-add/ip-prefix-cnt` | `local-del/ip-prefix-cnt` | `remote-add/ip-prefix-cnt` | `remote-del/ip-prefix-cnt` |

That is **28 counters** (7 route types × 4 categories), each `uint64_t`.

### Last update

| YANG xpath | YANG type | TDL path | TDL type | Mapped `show` CLI |
| --- | --- | --- | --- | --- |
| `/evpn-oper-data/evpn-stats/evpn-vni-rt-cnt/last-update` | uint64_t | `ios_oper/evpn_stats/evpn-vni-rt-cnt/last-update` | calendar_time | `Last update` |

---

## Full leaf reference (flat list)

For tooling that needs the exact leaf paths, here is the complete flat enumeration as printed in
the PDF (all under `/evpn-oper-data/evpn-stats/evpn-vni-rt-cnt/`, type `uint64_t`):

```text
local-add/ead-evi-cnt      → EAD/EVI - Local Updates
local-add/ead-es-cnt       → EAD/ES  - Local Updates
local-add/mac-cnt          → MAC     - Local Updates
local-add/mac-ip-cnt       → MAC/IP  - Local Updates
local-add/imet-cnt         → IMET    - Local Updates
local-add/es-cnt           → ES      - Local Updates
local-add/ip-prefix-cnt    → IP-Prefix - Local Updates

local-del/ead-evi-cnt      → EAD/EVI - Local Deletes
local-del/ead-es-cnt       → EAD/ES  - Local Deletes
local-del/mac-cnt          → MAC     - Local Deletes
local-del/mac-ip-cnt       → MAC/IP  - Local Deletes
local-del/imet-cnt         → IMET    - Local Deletes
local-del/es-cnt           → ES      - Local Deletes
local-del/ip-prefix-cnt    → IP-Prefix - Local Deletes

remote-add/ead-evi-cnt     → EAD/EVI - Remote Updates
remote-add/ead-es-cnt      → EAD/ES  - Remote Updates
remote-add/mac-cnt         → MAC     - Remote Updates
remote-add/mac-ip-cnt      → MAC/IP  - Remote Updates
remote-add/imet-cnt        → IMET    - Remote Updates
remote-add/es-cnt          → ES      - Remote Updates
remote-add/ip-prefix-cnt   → IP-Prefix - Remote Updates

remote-del/ead-evi-cnt     → EAD/EVI - Remote Deletes
remote-del/ead-es-cnt      → EAD/ES  - Remote Deletes
remote-del/mac-cnt         → MAC     - Remote Deletes
remote-del/mac-ip-cnt      → MAC/IP  - Remote Deletes
remote-del/imet-cnt        → IMET    - Remote Deletes
remote-del/es-cnt          → ES      - Remote Deletes
remote-del/ip-prefix-cnt   → IP-Prefix - Remote Deletes

last-update                → Last update (calendar_time)
```
