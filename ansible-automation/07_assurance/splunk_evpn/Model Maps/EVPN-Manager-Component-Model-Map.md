# EVPN Manager Component — CLI ⇄ Operational Model Mapping

> **Source PDF:** `EVPN-CLI to Operational Model Mapping for EVPN Manager Component-270526-194354.pdf`
> (a second, content-identical `…-270526-203647.pdf` export was removed as a duplicate). The source
> PDF also appends the EVPN Route Statistics mapping — see
> [`EVPN-Route-Statistics-Model-Map.md`](EVPN-Route-Statistics-Model-Map.md).
> **Platform scope:** This feature is available **only on CAT9k platforms**.
> This document is a faithful, cleaned-up transcription of the Cisco mapping PDF for the EVPN
> Manager component. It maps the `show l2vpn evpn …` CLI fields to their OpenConfig (OC) xpaths,
> Cisco native YANG xpaths, and the internal TDL (Telemetry Definition Language) encoder paths.

---

## Why this matters for the Splunk EVPN Assurance pipeline

The dashboards in `campus_evpn_assurance` consume the Cisco native YANG container
`/evpn-oper-data/evpn-inst` (TDL `ios_oper/evpn_inst`). The **EVI**, **VLAN**, and **Peer** tables
below back the EVPN instance/peer state views; the **RMAC** and **VTEP IP** leaves are used to
correlate VLAN-to-VTEP bindings.

---

## Reference test topology & configuration

The PDF documents a single VTEP (`VTEP1`) with a VLAN-based EVPN/VXLAN instance. Salient config:

```text
hostname VTEP1
vrf definition red
 rd 100:101
 address-family ipv4
  route-target export 100:100
  route-target import 100:100
  route-target export/import 100:100 stitching
 address-family ipv6
  route-target export 100:200
  route-target import 100:200
  route-target export/import 100:200 stitching

l2vpn evpn
 instance 1 vlan-based
  encapsulation vxlan

vlan configuration 3
 member vni 30000
vlan configuration 11
 member evpn-instance 1 vni 20011

interface nve1
 source-interface Loopback1
 host-reachability protocol bgp
 member vni 30000 vrf red
 member vni 20011 mcast-group 227.0.0.11

router bgp 100
 bgp router-id 1.1.1.1
 neighbor 2.2.2.1 remote-as 100
 neighbor 2.2.2.1 update-source Loopback0
 address-family l2vpn evpn
  neighbor 2.2.2.1 activate
  neighbor 2.2.2.1 send-community both
  neighbor 2.2.2.1 encap vxlan

gnxi
gnxi server
netconf-yang
restconf
```

### Show commands covered

| CLI command | Maps to model section |
| --- | --- |
| `show l2vpn evpn evi 1 detail` | **EVI** (`/evpn-oper-data/evpn-inst`) |
| `show l2vpn evpn evi 1 detail` (cont) | **VLAN** (`/evpn-oper-data/evpn-inst/evpn-vlan`) |
| `show l2vpn evpn evi 1 detail` (cont) | **Pseudoport** (`/evpn-oper-data/evpn-inst/evpn-vlan/evpn-pseudo-port`) |
| `show l2vpn evpn peers vxlan detail` | **Peer** (`/evpn-oper-data/evpn-inst/evpn-vlan/evpn-peer`) |

Representative `show l2vpn evpn evi 1 detail` excerpt from the PDF:

```text
EVPN instance:       1 (VLAN Based)
  RD:                1.1.1.1:1 (auto)
  Import-RTs:        100:1
  Export-RTs:        100:1
  State:             Established
  Replication Type:  Static (global)
  Encapsulation:     vxlan
  IP Local Learn:    Enabled (global)
  Adv. Def. Gateway: Enabled (global)
  Re-originate RT5:  Disabled
  Adv. Multicast:    Disabled (global)
  AR Flood Suppress: Enabled (global)
  Vlan:              11      Core Vlan:  3      L2 VNI: 20011   L3 VNI: 30000
  RMAC:              0050.568d.db7e          VTEP IP: 1.1.1.2   MCAST IP: 227.0.0.11   VRF: red
  Pseudoports:       GigabitEthernet1/0/3 service instance 11
  Peer IP Address:   2.2.2.2   Local VNI: 20011   Peer VNI: 20011   UP time: 00:29:38
```

---

## Column legend (applies to every mapping table)

| Column | Meaning |
| --- | --- |
| **Id** | Row number as printed in the source PDF |
| **OpenConfig xpath** | OC model path. `N/A` = no native YANG mapping; `—` = not present in PDF |
| **YANG xpath** | Cisco **native** model path (`Cisco-IOS-XE-evpn-oper`) — this is what is streamed |
| **Type** | YANG type (TDL type noted where it differs) |
| **TDL path** | Internal encoder path (`ios_oper/evpn_inst/…`) |
| **Mapped `show` CLI** | The CLI field/value the leaf corresponds to |
| **Comments** | Notes from the PDF (keys, "Not supported", etc.) |

---

## 1. EVI

**Container:** `/evpn-oper-data/evpn-inst` &nbsp;•&nbsp; **TDL:** `ios_oper/evpn_inst` &nbsp;•&nbsp; **Key:** `evpn-inst-id` (EVI)

OpenConfig xpaths share the prefix `/network-instances/network-instance/`.

| Id | OpenConfig xpath | YANG xpath | Type | TDL path | Mapped `show` CLI | Comments |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `name` | N/A | string | | | | OC top key, derived from VLAN or VRF |
| 2 | `state/name` | N/A | string | | | | |
| 3 | `state/type` | N/A | | | | | `L2VSI` for VLAN, `L3VRF` for VRF |
| 4 | `evpn/evpn-instances/evpn-instance/evi` | `/evpn-oper-data/evpn-inst/evpn-inst-id` | uint16 | `ios_oper/evpn_inst/evpn_inst_id` | `EVPN native instance: 1` | **key** |
| 5 | `evpn-instance/state/evi` | `/evpn-oper-data/evpn-inst/evpn-inst-id` | uint16 | `ios_oper/evpn_inst/evpn_inst_id` | | |
| 6 | — | `/evpn-oper-data/evpn-inst/evi-state` | enum | `ios_oper/evpn_inst/evpn_state` | `State: Established` | |
| 7 | `evpn-instance/state/encapsulation-type` | `/evpn-oper-data/evpn-inst/evpn-encap-type` | enum | `ios_oper/evpn_inst/evpn_encap_type` | `Encapsulation: vxlan` | |
| 8 | `evpn-instance/state/service-type` | `/evpn-oper-data/evpn-inst/evpn-type` | enum | `ios_oper/evpn_inst/evpn_type` | `(VLAN Based)` | |
| 9 | `evpn-instance/state/multicast-group` | — | oc-inet:ip-address | | | Not supported |
| 10 | `evpn-instance/state/multicast-mask` | — | oc-inet:ip-address | | | Not supported |
| 11 | `evpn-instance/state/replication-mode` | `/evpn-oper-data/evpn-inst/evpn-repl-type` | enum | `ios_oper/evpn_inst/evpn_repl_type` | `Replication Type: Static` | |
| 12 | `evpn-instance/state/route-distinguisher` | `/evpn-oper-data/evpn-inst/rd` | union → string (`tdl_vstring`) | `ios_oper/evpn_inst/rd` | `RD: 1.1.1.1:1` | |
| 13 | `evpn-instance/state/control-word-enabled` | — | boolean | | | Not supported |
| 14 | `evpn-instance/import-export-policy/state/export-route-target` | `/evpn-oper-data/evpn-inst/export-rts` | leaf-list union string (`array tdl_vstring`) | `ios_oper/evpn_inst/export_rt_rts` | `Export-RTs: 100:1` | |
| 15 | `import-export-policy/state/import-route-target` | `/evpn-oper-data/evpn-inst/import-rts` | leaf-list union string (`array tdl_vstring`) | `ios_oper/evpn_inst/import_rt_rts` | `Import-RTs: 100:1` | |
| 16 | — | `/evpn-oper-data/evpn-inst/evpn-ip-local-learn` | boolean | `ios_oper/evpn_inst/evpn_ip_local_learn` | `IP Local Learn: Enabled` | |
| 17 | — | `/evpn-oper-data/evpn-inst/evpn-dg-adv` | boolean | `ios_oper/evpn_inst/evpn_dg_adv` | `Adv. Def. Gateway: Enabled` | |
| 18 | — | `/evpn-oper-data/evpn-inst/evpn-ip-mcast-adv` | inet:ip-address | `ios_oper/evpn_inst/evpn_ip_mcast_adv` | `Adv. Multicast: Disabled` | |
| 19 | — | `/evpn-oper-data/evpn-inst/evi-re-orig-rt5` | boolean | `ios_oper/evpn_inst/evi_reoriginate_rt5` | `Re-originate RT5: Disabled` | |
| 20 | — | `/evpn-oper-data/evpn-inst/evpn-ar-flood-suppr` | boolean | `ios_oper/evpn_inst/evpn_ar_flood_suppr` | `AR Flood Suppress: Enabled` | |

---

## 2. VLAN

**Container:** `/evpn-oper-data/evpn-inst/evpn-vlan` &nbsp;•&nbsp; **TDL:** `ios_oper/evpn_inst/evpn_vlan` &nbsp;•&nbsp; **Key:** `vlan-id`

| Id | OpenConfig xpath | YANG xpath | Type | TDL path | Mapped `show` CLI | Comments |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/vlan-id` | uint16 | `…/evpn_vlan/vlan_id` | `Vlan: 11` | native **key**; provides network-instance name |
| 2a | `…/vxlan/state/vni` | `/evpn-oper-data/evpn-inst/evpn-vlan/l2-vni` | uint32 | `…/evpn_vlan/l2_vni` | `L2 VNI: 20011` | `l2_vni` used for VLAN NI |
| 2b | `…/vxlan/state/vni` | `/evpn-oper-data/evpn-inst/evpn-vlan/l3-vni` | uint32 | `…/evpn_vlan/l3_vni` | `L3 VNI: 30000` | `l3_vni` used for VRF NI |
| 3 | `…/vxlan/state/overlay-endpoint-network-instance` | — | | | | |
| 4 | `…/vxlan/state/overlay-endpoint` | `/evpn-oper-data/evpn-inst/evpn-vlan/nve-if` | string | `…/evpn_vlan/nve_if` | `NVE If: nve1` | |
| 5 | `…/vxlan/state/host-reachability-bgp` | `/evpn-oper-data/evpn-inst/evpn-vlan/host-reach-bgp` | boolean | `…/evpn_vlan/host_reach_bgp` | N/A | |
| 6 | `…/vxlan/state/multicast-group` | `/evpn-oper-data/evpn-inst/evpn-vlan/mcast-ip` | inet:ip-address | `…/evpn_vlan/mcast_ip` | `MCAST IP: 227.0.0.11` | |
| 7 | `…/vxlan/state/multicast-mask` | — | | | | Not supported |
| 8 | `…/vxlan/anycast-source-interface/state/interface` | — | | | | Not supported |
| 9 | `…/vxlan/anycast-source-interface/state/subinterface` | — | | | | Not supported |
| 10 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/vlan-protected` | boolean | `…/evpn_vlan/vlan_protected` | `Protected: False` | |
| 11 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/flood-suppr-attached` | boolean | `…/evpn_vlan/flood_suppr_attached` | `Flood Suppress: Attached` | |
| 12 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/efi-state` | enum | `…/evpn_vlan/efi_state` | `State: Established` | |
| 13 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/core-if` | string | `…/evpn_vlan/core_if` | `Core If: Vlan3` | |
| 14 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/access-if` | string | `…/evpn_vlan/access_if` | `Access If: Vlan11` | |
| 15 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/rmac` | yang:mac-address | `…/evpn_vlan/rmac` | `RMAC: 0050.568d.db7e` | |
| 16 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/core-vlan` | uint16 | `…/evpn_vlan/core_vlan` | `Core Vlan: 3` | |
| 17 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/vtep-ip` | inet:ip-address | `ios_oper/evpn_instr/evpn_vlan/vtep_ip` | `VTEP IP: 1.1.1.2` | |
| 18 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/sec-vtep-ip` | inet:ip-address | `ios_oper/evpn_instr/evpn_vlan/sec_vtep_ip` | `Sec. VTEP IP: ABCD:1::2` | |
| 19 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/vrf` | string | `…/evpn_vlan/vrf` | `VRF: red` | |
| 20 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/irb-type` | enum | `ios_oper/evpn_instance_oper/evpn_vlan_oper/irb_type` | `IPv4 IRB: Enabled` | |
| 21 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/ipv4-irb` | boolean | `…/evpn_vlan/ipv4_irb` | `IPv4 IRB: Enabled` | |
| 22 | — | `/evpn-oper-data/evpn-inst/evpn-vlan/ipv6-irb` | boolean | `…/evpn_vlan/ipv6_irb` | `IPv6 IRB: Enabled` | |

---

## 3. Pseudoport

**Container:** `/evpn-oper-data/evpn-inst/evpn-vlan/evpn-pseudo-port` &nbsp;•&nbsp; **TDL:** `ios_oper/evpn_inst/evpn_vlan/evpn_pseudo_port`

| Id | YANG xpath | Type | TDL path | Mapped `show` CLI | Comments |
| --- | --- | --- | --- | --- | --- |
| 1 | `…/evpn-pseudo-port/evpn-inst-id` | uint16 | `…/evpn_pseudo_port/evpn_inst_id` | | |
| 2 | `…/evpn-pseudo-port/vlan-id` | uint16 | `…/evpn_pseudo_port/vlan_id` | | |
| 3 | `…/evpn-pseudo-port/if-id` | uint64 | `…/evpn_pseudo_port/if_id` | | |
| 4a | `…/evpn-pseudo-port/if-name` | string | `…/evpn_pseudo_port/if_name` | `Pseudoports: GigabitEthernet1/0/3 service instance 11` | |
| 4b | `…/evpn-pseudo-port/svc-inst` | string (`u_int32`) | `…/evpn_pseudo_port/svc_inst` | `Pseudoports: GigabitEthernet1/0/3 service instance 11` | |
| 5 | `…/evpn-pseudo-port/efp-state` | enum | `…/evpn_pseudo_port/efp_state` | `State: Up` | |

---

## 4. Peer

**Container:** `/evpn-oper-data/evpn-inst/evpn-vlan/evpn-peer` &nbsp;•&nbsp; **TDL:** `ios_oper/evpn_inst/evpn_vlan/evpn_peer`

| Id | YANG xpath | Type | TDL path | Mapped `show` CLI | Comments |
| --- | --- | --- | --- | --- | --- |
| 1 | `…/evpn-peer/evpn-inst-id` | uint16 | `…/evpn_peer/evpn_inst_id` | | |
| 2 | `…/evpn-peer/vlan-id` | uint16 | `…/evpn_peer/vlan_id` | | |
| 3 | `…/evpn-peer/peer-ip-addr` | inet:ip-address | `…/evpn_peer/peer_ip_addr` | `Peer IP Address: 2.2.2.2` | |
| 4 | `…/evpn-peer/peer-up-time` | yang:date-and-time | `ios_oper/evpn_instr/evpn_vlan/evpn_peer/peer_up_time` (`calendar_time`) | `UP time: 00:29:38` | |
| 5 | `…/evpn-peer/local-vni-id` | uint32 | `…/evpn_peer/local_vni_id` | `Local VNI: 20011` | |
| 6 | `…/evpn-peer/remote-vni-id` | uint32 | `…/evpn_peer/remote_vni_id` | `Peer VNI: 20011` | |

---

## "Not supported" leaves

These OpenConfig leaves exist in the OC model but have **no native YANG / telemetry mapping** on
CAT9k per the PDF:

- `evpn-instance/state/multicast-group`, `…/multicast-mask` (EVI rows 9, 10)
- `evpn-instance/state/control-word-enabled` (EVI row 13)
- `…/vxlan/state/multicast-mask` (VLAN row 7)
- `…/vxlan/anycast-source-interface/state/interface`, `…/subinterface` (VLAN rows 8, 9)
