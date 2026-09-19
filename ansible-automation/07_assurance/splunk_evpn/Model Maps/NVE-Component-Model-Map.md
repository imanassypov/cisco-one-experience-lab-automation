# NVE Component — CLI ⇄ Operational Model Mapping

> **Source PDF:** `EVPN-CLI to Operational Model Mapping for NVE component-270526-203607.pdf`
> **Platform scope:** This feature is available **only on CAT9k platforms**.
> This document is a faithful, cleaned-up transcription of the Cisco mapping PDF. It maps the
> `show nve …` CLI fields to their OpenConfig (OC) xpaths, Cisco native YANG xpaths, and the
> internal TDL (Telemetry Definition Language) paths used by the streaming-telemetry encoder.

---

## Why this matters for the Splunk EVPN Assurance pipeline

The OTel collector streams the **Cisco native YANG** paths in this document (the
`/nve-oper-data/...` xpaths, encoded internally as the `ios_oper/nve_oper/...` TDL paths). The
dashboards in `campus_evpn_assurance` consume:

- `nve-vni-oper` (VNI state per VTEP)
- `nve-peer-oper` / `peer-vni-group` (the NVE Peer Adjacency Sankey)
- `nve-oper-counters` and `nve-vni-oper-counters` (traffic counters)

> **Telemetry note (peer-vni-group):** Rows 7–9 of the **PEER** table below (`peer-vni-group/vni`,
> `/evni`, `/rmac`) are the **17.18 replacement** for the deprecated `cp-vnis` / top-level `rmac`
> leaves. The `vni` and `evni` leaves are **list keys of type `uint32`**. Collector releases
> before `otelcol-contrib` 0.161.0 could not emit numeric list keys as Splunk dimensions, so
> per-VNI rows had to be discriminated by the **`rmac`** value instead. The lab now runs
> 0.161.0 or later, where the numeric keys arrive as dimensions. See
> [`../otel-collector/yanggrpcreceiver-numeric-key-issue.md`](../otel-collector/yanggrpcreceiver-numeric-key-issue.md).

---

## Reference test topology & configuration

The PDF documents a single VTEP (`VTEP1`) with a symmetric IRB EVPN/VXLAN setup. The salient
configuration that produces the operational state below:

```text
hostname VTEP1
vrf definition red
 rd 100:101
 address-family ipv4
  route-target export 100:100
  route-target import 100:100
  route-target export 100:100 stitching
  route-target import 100:100 stitching
 address-family ipv6
  route-target export 100:200
  route-target import 100:200
  route-target export 100:200 stitching
  route-target import 100:200 stitching

l2vpn evpn
 instance 1 vlan-based
  encapsulation vxlan

vlan configuration 3
 member vni 30000
vlan configuration 11
 member evpn-instance 1 vni 20011

interface nve1
 no ip address
 source-interface Loopback1
 host-reachability protocol bgp
 member vni 30000 vrf red          ! L3 VNI
 member vni 20011 mcast-group 227.0.0.11   ! L2 VNI

router bgp 100
 bgp router-id 1.1.1.1
 neighbor 2.2.2.1 remote-as 100
 neighbor 2.2.2.1 update-source Loopback0
 address-family l2vpn evpn
  neighbor 2.2.2.1 activate
  neighbor 2.2.2.1 send-community both
  neighbor 2.2.2.1 encap vxlan

! On-box telemetry / programmability
gnxi
gnxi server
netconf-yang
restconf
```

### Show commands covered

| CLI command | Maps to model container |
| --- | --- |
| `show nve interface nve1 detail` | **NVE** (`/nve-oper-data/nve-oper`) |
| `show nve vni 20011 detail` / `show nve vni 30000 detail` | **VNI** (`/nve-oper-data/nve-oper/nve-vni-oper`) |
| `show nve peers detail` | **PEER** (`/nve-oper-data/nve-oper/nve-peer-oper`) |
| `show nve interface nve1 detail` (counters) | **NVE Counters** (`/nve-oper-data/nve-oper-counters`) |
| `show nve vni … detail` (counters) | **VNI Counters** (`/nve-oper-data/nve-oper-counters/nve-vni-oper-counters`) |

Example `show nve peers detail` output from the PDF:

```text
Interface  VNI      Type Peer-IP          RMAC/Num_RTs   eVNI   state flags  UP time
nve1       30000    L3CP 2.2.2.2          cc70.ed5a.9367 30000  UP    A/-/4  00:05:36
nve1       30000    L3CP 2.2.2.2          cc70.ed5a.9367 30000  UP    A/M/6  00:05:36
nve1       20011    L2CP 2.2.2.2          cc70.ed5a.9367 20011  UP    N/A    00:05:36
```

---

## Column legend (applies to every mapping table)

| Column | Meaning |
| --- | --- |
| **Id** | Row number as printed in the source PDF |
| **OpenConfig xpath** | OC model path (`openconfig-network-instance` tree). `—` = not present in PDF |
| **YANG xpath** | Cisco **native** model path (`Cisco-IOS-XE-nve-oper`) — this is what is streamed |
| **YANG type** | YANG leaf type |
| **TDL path** | Internal encoder path (`ios_oper/nve_oper/…`) |
| **Mapped `show` CLI** | The CLI field/value the leaf corresponds to |
| **Comments** | Notes from the PDF (keys, deprecations, version gates) |

---

## 1. NVE

**Container:** `/nve-oper-data/nve-oper` &nbsp;•&nbsp; **TDL:** `ios_oper/nve_oper` &nbsp;•&nbsp; **Key:** `unit-number`

| Id | OpenConfig xpath | YANG xpath | YANG type | TDL path | Mapped `show` CLI | Comments |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | — | `/nve-oper-data/nve-oper/unit-number` | uint32 | `ios_oper/nve_oper/unit_number` | `NVE id: 1` | **key** |
| 2 | `…/connection-point[connection-point-id]/endpoints/endpoint[endpoint-id]/vxlan/state/description` | `/nve-oper-data/nve-oper/nve-if` | string | `ios_oper/nve_oper/nve_if` | `interface name: nve1` | OC model also uses this as key for `endpoints` and `connection-points` |
| 3 | `…/vxlan/state/enabled` | `/nve-oper-data/nve-oper/admin-state` | enum | `ios_oper/nve_oper/admin_state` | `Admin state (Up)` | |
| 4 | — | `/nve-oper-data/nve-oper/oper-state` | enum | `ios_oper/nve_oper/oper_state` | `Oper State (Up)` | |
| 5 | — | `/nve-oper-data/nve-oper/nve-encap` | enum | `ios_oper/nve_oper/nve_encap` | `Encapsulation: Vxlan IPv4` | |
| 6 | — | `/nve-oper-data/nve-oper/nve-mcast-encap` | enum | `ios_oper/nve_oper/nve_mcast_encap` | `Multicast BUM encapsulation: Vxlan IPv4` | |
| 7 | — | `/nve-oper-data/nve-oper/is-bgp-signal` | boolean | `ios_oper/nve_oper/is_bgp_signal` | `BGP host reachability` | `Enabled = True` |
| 8 | — | `/nve-oper-data/nve-oper/vxlan-port` | uint16 | `ios_oper/nve_oper/vxlan_port` | `VxLAN dport: 4789` | |
| 9 | — | `/nve-oper-data/nve-oper/l2dp-vni-num` | uint32 | `ios_oper/nve_oper/l2dp_vni_num` | `L2DP 0` | |
| 10 | — | `/nve-oper-data/nve-oper/l2cp-vni-num` | uint32 | `ios_oper/nve_oper/l2cp_vni_num` | `L2CP 1` | |
| 11 | — | `/nve-oper-data/nve-oper/l3cp-vni-num` | uint32 | `ios_oper/nve_oper/l3cp_vni_num` | `L3CP 1` | |
| 12 | `…/vxlan/state/source-interface` | `/nve-oper-data/nve-oper/src-if` | string | `ios_oper/nve_oper/src_if` | `source-interface: Loopback1` | |
| 13 | — | `/nve-oper-data/nve-oper/src-ipv4-address` | inet:ipv4-address | `ios_oper/nve_oper/src_ipv4_addres` | `primary: 1.1.1.2` | |
| 14 | — | `/nve-oper-data/nve-oper/src-ipv6-address` | inet:ipv6-address | `ios_oper/nve_oper/src_ipv6_addres` | | Displayed if V6 or dual stack |
| 15 | — | `/nve-oper-data/nve-oper/src-vrf` | string | `ios_oper/nve_oper/src_vrf` | `vrf: 0` | |
| 16 | — | `/nve-oper-data/nve-oper/tunnel-if` | string | `ios_oper/nve_oper/tunnel_if` | `tunnel interface: Tunnel0` | |
| 17 | — | `/nve-oper-data/nve-oper/v6-tunnel-if` | string | `ios_oper/nve_oper/v6_tunnel_if` | | Displayed if V6 or dual stack |

---

## 2. VNI

**Container:** `/nve-oper-data/nve-oper/nve-vni-oper` &nbsp;•&nbsp; **TDL:** `ios_oper/nve_oper/nve_vni_oper` &nbsp;•&nbsp; **Key:** `vni-id`

All OpenConfig xpaths below share the prefix
`…/connection-point/endpoints/endpoint/vxlan/endpoint-vnis/endpoint-vni/state/`.

| Id | OpenConfig leaf (under `endpoint-vni/state/`) | YANG xpath | YANG type | TDL path | Mapped `show` CLI | Comments |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `vni` | `/nve-oper-data/nve-oper/nve-vni-oper/vni-id` | uint32 | `…/nve_vni_oper/vni_id` | `VNI: 20011` | **key** |
| 2 | — | `/nve-oper-data/nve-oper/nve-vni-oper/nve-id` | uint32 | `…/nve_vni_oper/nve_id` | `Id from Interface: nve1` | |
| 3 | `vni-state` | `/nve-oper-data/nve-oper/nve-vni-oper/vni-oper-state` | enum | `…/nve_vni_oper/vni_oper_state` | `VNI State: Up` | |
| 4 | `bridge-domain` | `/nve-oper-data/nve-oper/nve-vni-oper/vlan-id` | uint32 | `…/nve_vni_oper/vlan_id` | `VLAN: 11` | |
| 5 | `vni-type` | `/nve-oper-data/nve-oper/nve-vni-oper/vni-type` | enum | `…/nve_vni_oper/vni_type` | `Part of Mode: L2CP` | |
| 6 | `learning-mode` | `/nve-oper-data/nve-oper/nve-vni-oper/vni-learning-mode` | enum | `…/nve_vni_oper/vni_learning_mode` | `Part of Mode: L2CP` | |
| 7 | `l3-vrf-name` | `/nve-oper-data/nve-oper/nve-vni-oper/nve-vni-vrf` | string | `…/nve_vni_oper/nve_vni_vrf` | `vrf: red` | |
| 8 | — | `/nve-oper-data/nve-oper/nve-vni-oper/l3-vni-id` | uint32 | `…/nve_vni_oper/l3_vni_id` | `L3VNI: 30000` | |
| 9 | — | `/nve-oper-data/nve-oper/nve-vni-oper/svi-vlan-id` | uint32 | `…/nve_vni_oper/svi_vlan_id` | `VLAN: 3` | |
| 10 | — | `/nve-oper-data/nve-oper/nve-vni-oper/svi-mac` | yang:mac-address | `…/nve_vni_oper/svi_mac` | `SVI MAC: 6C8B.D36D.471F` | |
| 11 | — | `/nve-oper-data/nve-oper/nve-vni-oper/local-routing` | boolean | `…/nve_vni_oper/local_routing` | `Local routing: Disabled` | |
| 12 | — | `/nve-oper-data/nve-oper/nve-vni-oper/mcast-v4-address` | inet:ip-address | `…/nve_vni_oper/mcast_v4_address` | `Multicast-group: 227.0.0.1` | Could be dual |
| 13 | — | `/nve-oper-data/nve-oper/nve-vni-oper/mcast-v6-address` | inet:ip-address | `…/nve_vni_oper/mcast_v6_address` | `Multicast-group` (could be V6) | Could be dual |
| 14 | — | `/nve-oper-data/nve-oper/nve-vni-oper/trm-mdt-v4-address` | inet:ip-address | `…/nve_vni_oper/trm_mdt_v4_address` | `IPv4 TRM mdt group: N/A` | |
| 15 | — | `/nve-oper-data/nve-oper/nve-vni-oper/trm-mdt-v6-address` | inet:ip-address | `…/nve_vni_oper/trm_mdt_v6_address` | `IPv6 TRM mdt group: N/A` | |
| 16 | `multidestination-traffic` (OC type `union`) | `/nve-oper-data/nve-oper/nve-vni-oper/replication-type` | enum | `…/nve_vni_oper/repl_type` | — | Not in CLI; calculated from multicast address, ingress replication and NVE encapsulation |
| 17 | `svi-state` | `/nve-oper-data/nve-oper/nve-vni-oper/svi-state` | enum | `…/nve_vni_oper/svi_state` | — | Not available in CLI |

---

## 3. PEER

**Container:** `/nve-oper-data/nve-oper/nve-peer-oper` &nbsp;•&nbsp; **TDL:** `ios_oper/nve_oper/nve_peer_oper` &nbsp;•&nbsp; **Key:** `peer-addr` (plus `peer-vni-group` keys `vni`, `evni`)

OpenConfig xpaths share the prefix
`…/connection-point/endpoints/endpoint/vxlan/endpoint-peers/endpoint-peer/`.

| Id | OpenConfig leaf | YANG xpath | YANG type | TDL path | Mapped `show` CLI | Comments |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `state/peer-address` | `/nve-oper-data/nve-oper/nve-peer-oper/peer-addr` | inet:ip-address | `…/nve_peer_oper/peer_addr` | `Peer-IP: 2.2.2.2` | **key** |
| 2 | — | `/nve-oper-data/nve-oper/nve-peer-oper/nve-id` | uint32 | `…/nve_peer_oper/nve_id` | `id from interface nve1` | |
| 3 | `state/control-plane-vnis` | `/nve-oper-data/nve-oper/nve-peer-oper/cp-vnis` | leaf-list uint32 | `…/nve_peer_oper/cp_vnis` | `eVNI: 20011, 30000` | **Deprecated** (`status deprecated`) |
| 4 | `state/router-mac` | `/nve-oper-data/nve-oper/nve-peer-oper/rmac` | yang:mac-address | `…/nve_peer_oper/rmac` | `RMAC: cc70.ed5a.9367` | **Deprecated** (`status deprecated`) |
| 5 | `state/uptime` | `/nve-oper-data/nve-oper/nve-peer-oper/peer-up-time` | yang:date-and-time (OC `oc-types:timeticks64`) | `…/nve_peer_oper/peer_up_time` | `UP time: 00:05:36` | Calendar time at discovery time |
| 6 | `state/peer-state` | `/nve-oper-data/nve-oper/nve-peer-oper/peer-state` | enum | `…/nve_peer_oper/peer_state` | `state: UP` | |
| 7 | `vni-peer-groups/vni-peer-group/state/cp-vni` | `/nve-oper-data/nve-oper/nve-peer-oper/peer-vni-group/vni` | uint32 | `…/nve_peer_oper/peer_vni_group/vni` | `eVNI: 20011, 30000` | **key** (`peer-vni-group` key `vni evni`) |
| 8 | `vni-peer-group/state/egress-vni` | `/nve-oper-data/nve-oper/nve-peer-oper/peer-vni-group/evni` | uint32 | `…/nve_peer_oper/peer_vni_group/evni` | `eVNI: 20011, 30000` | **key** (`peer-vni-group` key `vni evni`) |
| 9 | `vni-peer-group/state/router-mac` | `/nve-oper-data/nve-oper/nve-peer-oper/peer-vni-group/rmac` | yang:mac-address | `…/nve_peer_oper/peer_vni_group/rmac` | `RMAC: cc70.ed5a.9367` | replacement for deprecated top-level `rmac` |

---

## 4. NVE Counters

**Container:** `/nve-oper-data/nve-oper-counters` &nbsp;•&nbsp; **TDL:** `ios_oper/nve_oper_counters` &nbsp;•&nbsp; **Key:** `unit-number`

| Id | YANG xpath | YANG type | TDL path | Mapped `show` CLI | Comments |
| --- | --- | --- | --- | --- | --- |
| 1 | `/nve-oper-data/nve-oper-counters/unit-number` | uint32 | `…/unit_number` | `id from interface nve1` | **key** |
| 2 | `…/uc-input-packets` | uint64 | `…/uc_input_packets` | `Pkts In: 0` | Displayed as **UcastPkts RX** if multicast supported |
| 3 | `…/uc-input-bytes` | uint64 | `…/uc_input_bytes` | `Bytes In: 0` | Displayed as **UcastBytes RX** if multicast supported |
| 4 | `…/mc-input-packets` | uint64 | `…/mc_input_packets` | — | Displayed as **McastPkts RX** if multicast supported |
| 5 | `…/mc-input-bytes` | uint64 | `…/mc_input_bytes` | — | Displayed as **McastBytes RX** if multicast supported |
| 6 | `…/uc-output-packets` | uint64 | `…/uc_output_packets` | `Pkts Out: 17` | Displayed as **UcastPkts TX** if multicast supported |
| 7 | `…/uc-output-bytes` | uint64 | `…/uc_output_bytes` | `Bytes Out: 2290` | Displayed as **UcastBytes TX** if multicast supported |
| 8 | `…/mc-output-packets` | uint64 | `…/mc_output_packets` | — | Displayed as **McastPkts TX** if multicast supported |
| 9 | `…/mc-output-bytes` | uint64 | `…/mc_output_bytes` | — | Displayed as **McastBytes TX** if multicast supported |

---

## 5. VNI Counters

**Container:** `/nve-oper-data/nve-oper-counters/nve-vni-oper-counters` &nbsp;•&nbsp; **TDL:** `ios_oper/nve_oper_counters/nve_vni_oper_counters` &nbsp;•&nbsp; **Keys:** `vni-id`, `nve-id`

| Id | YANG xpath | YANG type | TDL path | Mapped `show` CLI | Comments |
| --- | --- | --- | --- | --- | --- |
| 1 | `…/nve-vni-oper-counters/vni-id` | uint32 | `…/nve_vni_oper_counters/vni_id` | `VNI: 20011` | **key** |
| 2 | `…/nve-vni-oper-counters/nve-id` | uint32 | `…/nve_vni_oper_counters/nve_id` | `id from interface nve1` | |
| 3 | `…/uc-input-packets` | uint64 | `…/uc_input_packets` | `Pkts In: 0` | Displayed as **UcastPkts RX** if multicast supported |
| 4 | `…/uc-input-bytes` | uint64 | `…/uc_input_bytes` | `Bytes In: 0` | Displayed as **UcastBytes RX** if multicast supported |
| 5 | `…/mc-input-packets` | uint64 | `…/mc_input_packets` | — | Displayed as **McastPkts RX** if multicast supported |
| 6 | `…/mc-input-bytes` | uint64 | `…/mc_input_bytes` | — | Displayed as **McastBytes RX** if multicast supported |
| 7 | `…/uc-output-packets` | uint64 | `…/uc_output_packets` | `Pkts Out: 17` | Displayed as **UcastPkts TX** if multicast supported |
| 8 | `…/uc-output-bytes` | uint64 | `…/uc_output_bytes` | `Bytes Out: 2290` | Displayed as **UcastBytes TX** if multicast supported |
| 9 | `…/mc-output-packets` | uint64 | `…/mc_output_packets` | — | Displayed as **McastPkts TX** if multicast supported |
| 10 | `…/mc-output-bytes` | uint64 | `…/mc_output_bytes` | — | Displayed as **McastBytes TX** if multicast supported |

---

## Version-gating summary (17.18)

| Leaf | Status in 17.18 | Replacement |
| --- | --- | --- |
| `nve-peer-oper/cp-vnis` | **Deprecated** | `nve-peer-oper/peer-vni-group/vni` + `/evni` (keys) |
| `nve-peer-oper/rmac` | **Deprecated** | `nve-peer-oper/peer-vni-group/rmac` |
| `nve-peer-oper/peer-vni-group/{vni,evni,rmac}` | **New** | — |

> Devices in the Campus EVPN lab run an experimental 26.x build that already exposes the
> `peer-vni-group` list, which is why the collector receives one `(peer-addr, rmac)` tuple per VNI.
