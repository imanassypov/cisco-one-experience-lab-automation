# Site-105 wireless client cannot join `PSEUDOCO-POD12`

Session record: 2026-09-03, after Catalyst Center stages 07 (wireless design/profile) and 08 (WLC + AP provision). Controller `C9800` at `198.18.5.103`. Privilege 15 CLI.

This is the live troubleshooting path, not a generic 9800 playbook. Each step records the command, the output that mattered, and **why that output chose the next command**. Dead-end commands are left in so the same false trails are not re-walked.

SSID `PSEUDOCO-POD12` is WPA2/WPA3 Enterprise (802.1X → ISE `198.18.5.101`). FlexConnect local switching at Site-105. AP trunk on each leaf `Gi1/0/2` is native VLAN 10, allowed `10,101,102` (`DEFN-CLIENT-PORTS.j2`). ISE authorization profiles in this lab return VLAN **names** `Main` / `PROD` / `IOT`, matching the three overlay VRFs.

---

## Symptom

A test wireless client could see and attempt `PSEUDOCO-POD12` but never reached RUN. CatC inventory showed the WLC and AP as provisioned. The dCloud pre-built SSID `PSEUDOCO-POD#` (WLAN 1) was still present and had historically worked.

Starting hypothesis, in priority order:

1. AP not joined, radios down, or SSID not on the AP (provisioning did not stick).
2. Policy / site / RF tags still on the dCloud defaults, so WLAN 17 is not bound to this AP.
3. 802.1X / ISE (wrong SSID security, RADIUS down, reject).
4. FlexConnect VLAN / native-VLAN / AAA-override mismatch (client authenticates, then datapath fails).

The order is deliberate: do not debug ISE until the AP is actually offering the SSID, and do not assume RADIUS until a client MAC is visible on the controller.

---

## Lab facts used as given (not re-discovered)

| Item | Value |
|------|--------|
| WLC | `198.18.5.103` (`C9800`). Lookup `C9800-WLC` lists `.102`; that is AD/DNS. |
| AP | `SITE-105-AP-1`, Ethernet `04:5f:b9:ca:03:58`, radio `68:7d:b4:90:95:00` |
| Intended CatC tags (stage 08) | site `ST_Durha_Site-105_d97a1_0`, policy `PT_Durha_Site-_MAIN_70ab7`, RF `TYPICAL` |
| Intended WLAN | profile `PSEUDOCO-FLEX-Profile`, SSID `PSEUDOCO-POD12`, policy VLAN name `PSEUDOCO-VLAN10` → 10 |
| Intended Flex native VLAN | 10 (`wireless_design.flex_connect_configuration[].vlan_id`) |
| Working dCloud WLAN | profile `DCLOUD-XAR-FLEX-Profile`, SSID `PSEUDOCO-POD#`, policy VLAN **numeric** 10 |

SSH as the CatC CLI Admin credential (`settings.json` `device_credentials.cli_credential` on the DC-Site-10 row). `terminal length 0` first.

---

## Step 0 — Reachability

**Why first.** Client-join debugging on a 9800 is pointless if the session cannot talk to the controller. VPN must be up; lab DNS on the Mac often does not resolve `wlc.corp.pseudoco.com`.

```text
ping 198.18.5.103          # 74 ms, 0% loss
nc -z 198.18.5.103 22      # SSH open
nc -z 198.18.5.103 443     # HTTPS open
```

`ping wlc.corp.pseudoco.com` failed (no lab resolver on the Mac). Continue by IP.

**Transition.** Box is up. SSH and confirm exec privilege before any `show`.

```text
C9800# show privilege
Current privilege level is 15
C9800# show running-config | include hostname
hostname C9800
```

---

## Step 1 — Is the AP joined, FlexConnect, and offering WLAN 17?

**Why.** If the AP is not Registered, or radios are down, or WLAN 17 is missing from the BSSID table, the client never gets as far as 802.1X. That would be a stage-08 problem, not an ISE/VLAN problem.

```text
C9800# show ap summary
Number of APs: 1

AP Name                          Slots AP Model             Ethernet MAC   Radio MAC      CC   RD   IP Address                                State        Location
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
SITE-105-AP-1                    3     C9130AXI-B           045f.b9ca.0358 687d.b490.9500 US   -B   10.10.255.101                             Registered   Leaf1
```

```text
C9800# show ap tag summary
AP Name                           AP Mac           Site Tag Name                     Policy Tag Name                   RF Tag Name                       Misconfigured    Tag Source
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
SITE-105-AP-1                     045f.b9ca.0358   ST_Durha_Site-105_d97a1_0         PT_Durha_Site-_MAIN_70ab7         TYPICAL                           No               Static
```

`show ap name SITE-105-AP-1 tag` is incomplete on 17.12 (`% Incomplete command`). Use `show ap tag summary` plus `config general`.

Relevant `show ap name SITE-105-AP-1 config general` lines:

```text
IP Address                                      : 10.10.255.101
Gateway IP Address                              : 10.10.255.1
Site Tag Name                                   : ST_Durha_Site-105_d97a1_0
RF Tag Name                                     : TYPICAL
Policy Tag Name                                 : PT_Durha_Site-_MAIN_70ab7
Flex Profile                                    : FP_Durha_Site-_d97a1
Operation State                                 : Registered
AP Mode                                         : FlexConnect
AP VLAN tagging state                           : Disabled
AP VLAN tag                                     : 0
Join Date and Time                              : 09/03/2026 10:02:28
```

AP is in `10.10.255.0/24` — Site-105 VLAN 10 — so the switchport native VLAN really is 10. Flex profile name is the CatC-generated `FP_Durha_Site-_d97a1`, not `DCLOUD-XAR-FLEX-Profile`. Tag source Static, not Misconfigured: stage 08 did bind CatC tags.

```text
C9800# show ap name SITE-105-AP-1 wlan dot11 5ghz
Slot id  : 1
  WLAN ID    BSSID
  -------------------------
  17         687d.b490.950f
Slot id  : 2
  WLAN ID    BSSID
  -------------------------
  17         687d.b490.9507

C9800# show ap name SITE-105-AP-1 wlan dot11 24ghz
Slot id  : 0
  WLAN ID    BSSID
  -------------------------
  17         687d.b490.9500
```

Only WLAN **17** is on this AP. The dCloud WLAN 1 is not bound to the CatC policy tag. The client is talking to `PSEUDOCO-POD12`, not accidentally to `PSEUDOCO-POD#`.

```text
C9800# show ap status
SITE-105-AP-1                       Enabled    FlexConnect       US

C9800# show ap dot11 24ghz summary
SITE-105-AP-1  ...  Slot 0  Enabled  Up    channel 6    REAP

C9800# show ap dot11 5ghz summary
SITE-105-AP-1  ...  Slot 1  Enabled  Up    (128,124)    REAP
SITE-105-AP-1  ...  Slot 2  Disabled Down  (36)         REAP
```

2.4 GHz and one 5 GHz radio are up. Slot 2 down is not this failure — the client later shows `11n(2.4)`.

```text
C9800# show wlan summary
ID   Profile Name                     SSID                             Status 2.4GHz/5GHz Security
1    DCLOUD-XAR-FLEX-Profile          PSEUDOCO-POD#                    UP     [WPA2][802.1x][AES]
17   PSEUDOCO-FLEX-Profile            PSEUDOCO-POD12                   UP     [WPA2 + WPA3][802.1x][AES][PMF 802.1X]
```

WLAN 17 is UP, broadcast on, 802.1X. SSID admin-down and PSK-vs-Enterprise are ruled out.

**Transition.** Provisioning and RF path are healthy. Next: is a client even visible, and if so in what state?

---

## Step 2 — Client state and delete reasons (the fork)

**Why.** `show wireless client summary` is the cheapest way to distinguish “never associated” from “associated then killed”. Delete-reason counters then name the killer without debug traces.

```text
C9800# show wireless client summary
Number of Clients: 0

Number of Excluded Clients: 1

MAC Address    AP Name                          Type ID   State              Protocol Method
------------------------------------------------------------------------------------------------
d8ec.5e08.09f1 SITE-105-AP-1                    WLAN 17   Excluded           11n(2.4) Dot1x
```

The client **did** reach WLAN 17 on this AP, via Dot1x. Exclusion, not “not found”. Hypothesis 1 and 2 (AP/SSID/tags) are done.

```text
C9800# show wireless stats client delete reasons
...
802.1X authentication credential failure                        : 0
802.1X authentication timeout                                   : 0
Incorrect credentials                                           : 0
AAA server unavailable                                          : 0
Wrong PSK                                                       : 0
...
VLAN failure                                                    : 2
```

Every 802.1X / PSK / AAA-dead counter is zero. The only non-zero datapath delete is **VLAN failure: 2**.

```text
C9800# show wireless exclusionlist
Number of Excluded Clients : 1

MAC Address       Description                       Exclusion Reason                    Time Remaining
------------------------------------------------------------------------------------------------------
d8ec.5e08.09f1                                      VLAN failure                                    78
```

**Transition.** Do not open ISE yet. Authentication is succeeding often enough to get an exclusion with reason VLAN failure. Confirm RADIUS is up (so this is not a misleading counter), then inspect the VLAN the policy profile and Flex profile actually assign.

---

## Step 3 — RADIUS is up; this is not an ISE reject

**Why.** VLAN failure can be a side-effect of a bad Access-Accept. Confirm ISE is reachable and accepting before treating the VLAN as the root cause.

```text
C9800# show aaa servers
RADIUS: id 1, priority 1, host 198.18.5.101, auth-port 1812, acct-port 1813, hostname ISE
     State: current UP, duration 217983s, previous duration 0s
     Dead: total time 0s, count 0
     Authen: request 55, timeouts 0, failover 0, retransmission 0
             Response: accept 2, reject 0, challenge 53
             Transaction: success 55, failure 0
             Dot1x transactions:
             Transaction: total 2, success 2, failure 0
     Author: request 11, timeouts 0, failover 0, retransmission 0
             Response: accept 11, reject 0
```

ISE is UP. 2 Dot1x transactions, 2 accepts, 0 rejects, 0 timeouts. The client passed 802.1X. Authorization also accepts (11/11).

`show radius server all` shows CatC-created groups `dnac-rGrp-PSEUDOCO-P-d37105d1` and `dnac-acct-PSEUDOCO-P-d37105d1` pointing at the same ISE. WLAN 17 uses `802.1x authentication list name : dnac-cts-PSEUDOCO-P-d37105d1`. Consistent with stage 07.

**Transition.** Authn/authz succeed; the controller then cannot apply a VLAN. Next objects: policy profile VLAN, Flex VLAN-name map, native VLAN, and whether AAA override is on.

---

## Step 4 — Policy tag maps the right WLAN; policy VLAN is a *name*

**Why.** CatC binds WLAN profile → policy profile inside a policy tag. If that map were empty or pointed at the dCloud policy, WLAN 17 would not be on the AP (already disproved) or would use VLAN 10 numeric. Need the actual VLAN string.

```text
C9800# show wireless tag policy detailed PT_Durha_Site-_MAIN_70ab7
Policy Tag Name : PT_Durha_Site-_MAIN_70ab7
Number of WLAN-POLICY maps: 1
WLAN Profile Name                 Policy Name
------------------------------------------------------------------------
PSEUDOCO-FLEX-Profile             PSEUDOCO-FLEX-Profile
```

One map, CatC names. No leftover dCloud WLAN on this tag.

```text
C9800# show wireless profile policy detailed PSEUDOCO-FLEX-Profile
Policy Profile Name                 : PSEUDOCO-FLEX-Profile
VLAN                                : PSEUDOCO-VLAN10
WLAN Switching Policy
  Flex Central Switching            : DISABLED
  Flex Central Authentication       : ENABLED
  Flex Central DHCP                 : DISABLED
Exclusionlist                       : ENABLED
Exclusion Timeout                   : 180
AAA Override                        : ENABLED
Vlan Fallback                       : DISABLED
```

Three facts that lock the rest of the path:

1. **Named VLAN** `PSEUDOCO-VLAN10`, not VLAN ID 10. FlexConnect will resolve it through the Flex profile’s VLAN-name table, not the IOS VLAN database alone.
2. **AAA override enabled, VLAN fallback disabled.** If ISE returns a VLAN name that is not in that table, the session fails. It will not fall back to `PSEUDOCO-VLAN10`.
3. Local switching, central auth — matches FlexConnect at a remote site. The WLC does not need an SVI in VLAN 10 (`show ip interface brief` is only `GigabitEthernet1 198.18.5.103`; that is expected).

Compare the dCloud policy that used to work:

```text
C9800# show wireless profile policy detailed DCLOUD-XAR-FLEX-PP
VLAN                                : 10
Flex Central Switching              : DISABLED
AAA Override                        : ENABLED
Vlan Fallback                       : DISABLED
DHCP required                       : ENABLED
DHCP server address                 : 198.18.5.102
```

Same AAA-override/fallback posture, but VLAN is **numeric 10**. Numeric VLAN does not depend on a name being present in the Flex map for the default assignment. ISE can still override to a *name*; that name still has to exist in the Flex map.

**Transition.** Named VLAN + AAA override + no fallback means the Flex profile map is now the critical object. Also check native VLAN against the AP subnet `10.10.255.0/24`.

---

## Step 5 — Flex profile: native VLAN 1, only one name mapped

**Why.** `show wireless flex profile summary` is the wrong word order on 17.12 (`% Invalid input`). The 9800 command is `show wireless profile flex …`.

```text
C9800# show wireless tag site detailed ST_Durha_Site-105_d97a1_0
Site Tag Name        : ST_Durha_Site-105_d97a1_0
Flex Profile         : FP_Durha_Site-_d97a1
AP Profile           : default-ap-profile
Local-site           : No
```

```text
C9800# show wireless profile flex detailed FP_Durha_Site-_d97a1
VLAN Name - VLAN ID mapping  :
  VLAN Name                         VLAN ID
  ----------------------------------------------------------------------------------------------------------------
  PSEUDOCO-VLAN10                   10
Native vlan ID                 : 1
```

Two defects against intent:

| Intent (settings.json / DEFN) | Live CatC Flex profile |
|-------------------------------|-------------------------|
| Native VLAN **10** (AP trunk, `flex_connect_configuration.vlan_id`) | Native VLAN **1** |
| Client VLANs 10 / 101 / 102 for Main / PROD / IOT (ISE names) | Only `PSEUDOCO-VLAN10 → 10` |

`show running-config | section wireless profile flex FP_Durha` confirmed there was no `native-vlan-id` line at all (9800 default 1) and a single `vlan-name PSEUDOCO-VLAN10 / vlan-id 10`.

IOS VLAN database on the WLC (used for names on the *controller*, not the Flex map):

```text
C9800# show vlan brief
VLAN Name                             Status    Ports
1    default                          active    Gi2, Gi3
10   Main                             active
101  PROD                             active
102  IOT                              active
```

VLAN 10’s IOS name is **`Main`**, not `PSEUDOCO-VLAN10`. `PSEUDOCO-VLAN10` exists only as a Flex name. That is legal for the default policy VLAN, but ISE in this lab does not return `PSEUDOCO-VLAN10`.

**Transition.** Before changing anything, prove what the working Flex profile looks like, and get the syslog attribute name. Guessing `PROD` from the VLAN table is not enough.

---

## Step 6 — Working dCloud Flex profile is the template

**Why.** Same AP, same ISE, same AAA-override. The dCloud SSID worked because its Flex map listed the ISE VLAN names and native VLAN 10. If CatC’s profile is a strict subset of that, the delta *is* the bug.

```text
C9800# show wireless profile flex detailed DCLOUD-XAR-FLEX-Profile
VLAN Name - VLAN ID mapping  :
  IOT                               102
  Main                              10
  PROD                              101
Native vlan ID                 : 10
CTS Policy:
  Inline tagging               : ENABLED
  SGACL enforcement            : ENABLED
```

```text
C9800# show wireless tag site detailed FLEX-SITE
Flex Profile         : DCLOUD-XAR-FLEX-Profile
```

dCloud site tag `FLEX-SITE` → flex profile with Main/PROD/IOT and native 10. CatC site tag → flex profile with only `PSEUDOCO-VLAN10` and native 1.

Stage 08 moved the AP off `FLEX-SITE` / `DCLOUD-XAR-FLEX-PT` onto the CatC tags. That is why POD# would still work *if* the AP were on dCloud tags, and why POD12 fails on CatC tags even though 802.1X is the same ISE.

**Transition.** Last evidence before a config change: syslog for MAC `d8ec.5e08.09f1` should name the AAA attribute that failed.

---

## Step 7 — Syslog names the failed attribute: `PROD`

**Why.** VLAN failure + ISE returning a name that is absent from the Flex map is the predicted mechanism. The log must show the name, not just “VLAN Failure”.

```text
C9800# show logging | include d8ec.5e08.09f1|VLAN failure|vlan fail
Sep  3 17:43:42.082: %SESSION_MGR-5-FAIL: Chassis 1 R0/0: wncd: Authorization failed or unapplied for client (d8ec.5e08.09f1) on Interface capwap_90000005 AuditSessionID 000000000000000B685E444A. Failure Reason: VLAN Failure. Failed attribute name PROD.
Sep  3 17:43:42.083: %CLIENT_EXCLUSION_SERVER-5-ADD_TO_EXCLUSIONLIST_REASON_DYNAMIC: Chassis 1 R0/0: wncmgrd: Client MAC: d8ec.5e08.09f1 was added to exclusion list associated with AP Name:SITE-105-AP-1, BSSID:MAC: 687d.b490.9500, reason:VLAN failure
Sep  3 17:43:42.086: %DOT1X-5-RESULT_OVERRIDE: Chassis 1 R0/0: wncd: Authentication result overridden for client (d8ec.5e08.09f1) on Interface capwap_90000005 AuditSessionID 000000000000000B685E444A
Sep  3 17:48:44.627: %CLIENT_EXCLUSION_SERVER-5-ADD_TO_EXCLUSIONLIST_REASON_DYNAMIC: ... reason:VLAN failure
Sep  3 17:48:44.627: %SESSION_MGR-5-FAIL: ... Failure Reason: VLAN Failure. Failed attribute name PROD.
```

`Failed attribute name PROD` twice, ~5 minutes apart (exclusion timeout 180 s, client retried). 802.1X succeeded; applying VLAN name `PROD` failed because `FP_Durha_Site-_d97a1` had no `PROD → 101` row. `%DOT1X-5-RESULT_OVERRIDE` is the controller discarding the Access-Accept.

`show wireless client mac-address d8ec.5e08.09f1 detail` returned empty while the client was excluded. Exclusion-list + syslog were the useful views.

**Transition.** Cause is closed. Fix the Flex map to match dCloud (and intent), set native VLAN 10, then the client can retry. Do not enable VLAN fallback as the fix — that would park a PROD user on VLAN 10.

---

## Root cause

ISE AAA-override returned VLAN name **`PROD`**. The CatC-generated Flex profile on the AP did not map that name (or `Main` / `IOT`), so the 9800 failed authorization with **VLAN failure** and excluded the client.

Contributing CatC gap: `wireless_design.flex_connect_configuration` asked for native VLAN 10, but the live profile stayed at native VLAN **1**. `wireless_design.interfaces` only declared `PSEUDOCO-VLAN10`. Stage 07 therefore never created the ISE VLAN-name table that dCloud shipped in `DCLOUD-XAR-FLEX-Profile`. Moving the AP to CatC tags in stage 08 orphaned the client from that table.

802.1X, AP join, radios, SSID broadcast, and policy-tag WLAN mapping were all fine.

```
client → AP (WLAN 17) → WLC 802.1X → ISE Access-Accept (VLAN=PROD)
                                      → Flex map lookup PROD
                                      → miss
                                      → SESSION_MGR VLAN Failure
                                      → exclusion list
```

---

## Step 8 — Remediation on the WLC

Aligned `FP_Durha_Site-_d97a1` with the working dCloud Flex profile. CatC is still SSOT for the next provision; this is a live repair.

```text
C9800# configure terminal
C9800(config)# wireless profile flex FP_Durha_Site-_d97a1
C9800(config-wireless-flex-profile)# native-vlan-id 10
C9800(config-wireless-flex-profile)# vlan-name Main
C9800(config-wireless-flex-profile-vlan)# vlan-id 10
C9800(config-wireless-flex-profile-vlan)# vlan-name PROD
C9800(config-wireless-flex-profile-vlan)# vlan-id 101
C9800(config-wireless-flex-profile-vlan)# vlan-name IOT
C9800(config-wireless-flex-profile-vlan)# vlan-id 102
C9800(config-wireless-flex-profile-vlan)# end
```

Verify:

```text
C9800# show wireless profile flex detailed FP_Durha_Site-_d97a1
VLAN Name - VLAN ID mapping  :
  IOT                               102
  Main                              10
  PROD                              101
  PSEUDOCO-VLAN10                   10
Native vlan ID                 : 10
```

`clear wireless exclusionlist mac-address d8ec.5e08.09f1` is invalid on this 17.12 image. The 180 s timer had already expired:

```text
C9800# show wireless exclusionlist
Number of Excluded Clients : 0
```

```text
C9800# write memory
Building configuration...
[OK]
```

CTS inline tagging / SGACL are still disabled on the CatC Flex profile (enabled on dCloud). That was not this failure; SGT-on-the-air is a separate follow-up.

---

## Commands that wasted a cycle (keep out of the next pass)

| Attempt | Result | Use instead |
|---------|--------|-------------|
| `show ap name SITE-105-AP-1 tag` | `% Incomplete command` | `show ap tag summary` |
| `show wireless flex profile summary` | invalid word order | `show wireless profile flex summary` |
| `show wireless vlan group summary` | invalid | not used on this 9800 for these VLANs |
| `show ap capwap summary` | invalid | `show ap summary` / `config general` |
| `show wireless client mac-address <mac> detail` while Excluded | empty | `show wireless exclusionlist` + `show logging \| include <mac>` |
| `clear wireless exclusionlist mac-address <mac>` | invalid on 17.12 | wait for timeout, or `show wireless exclusionlist` |

---

## Replay checklist (same symptom)

1. `show ap summary` / `show ap tag summary` — Registered, CatC tags, not Misconfigured.
2. `show wlan summary` / `show ap name <ap> wlan dot11 24ghz` — WLAN 17 on a live radio.
3. `show wireless client summary` — Excluded vs nothing.
4. `show wireless exclusionlist` and `show wireless stats client delete reasons` — if VLAN failure, skip ISE GUI.
5. `show aaa servers` — confirm accept/reject so VLAN failure is not covering a reject.
6. `show wireless profile policy detailed PSEUDOCO-FLEX-Profile` — named VLAN, AAA override, no fallback.
7. `show wireless profile flex detailed FP_Durha_Site-_d97a1` — native 10, names Main/PROD/IOT present.
8. `show logging | include Failed attribute name` — the ISE VLAN name that missed the map.
9. Diff against `show wireless profile flex detailed DCLOUD-XAR-FLEX-Profile`.

---

## Pipeline follow-up

Stage 07 now declares ISE VLAN names and pins native VLAN 10 so a later `07_network_profile.yml` / `08_provision_devices.yml` rebuilds the Flex profile with the same map as the CLI repair.

- `wireless_design.interfaces` includes `PSEUDOCO-VLAN10` plus `Main` / `PROD` / `IOT` (10 / 101 / 102).
- `wireless_design.flex_connect_aaa_override` is the CatC object that renders those names as Flex `vlan-name` rows (`PUT /wirelessSettings/flexConnectAaaOverride`). `wireless_profile.additional_interfaces` is extra WLC interfaces on `HQ-Wireless` and is **not** this map — 07 stored Main/PROD/IOT there and the WLC Flex profile still only had `PSEUDOCO-VLAN10`.
- `flex_connect_configuration.vlan_id: 10` is still declared, and stage 07 PUTs `/wirelessSettings/flexConnectNativeVlan` then GET-asserts, because the design WFM skips create when no override exists.

A re-provision of the WLC/AP (stage 08) is still required after 07 for CatC to push the new Flex profile onto `C9800`. The 2026-09-03 CLI repair on `FP_Durha_Site-_d97a1` already matches that intent.
