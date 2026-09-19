# Stage 12 — Intent verification

Generated 2026-09-16 10:13:18 UTC by `12_verify_intent.yml`.

Declared intent is compared against live device state collected through
Catalyst Center Command Runner. Intent comes from `settings.json` and from the
`DEFN-*.j2` templates **as stored in Catalyst Center**, so this report reflects
what was actually deployed rather than what the repo currently says.

## Result

| Outcome | Count |
| --- | --- |
| Pass | 44 |
| Fail | 0 |
| Not verified | 0 |
| Not applicable | 7 |

**PASSED** —
51 check(s) across
4 device(s).

## Devices

| Management IP | Catalyst Center hostname | Family | Role |
| --- | --- | --- | --- |
| `172.30.255.1` | `Site_105-Leaf1.corp.pseudoco.com` | Switches and Hubs | switch |
| `172.30.255.2` | `Site_105-Leaf2.corp.pseudoco.com` | Switches and Hubs | switch |
| `172.30.255.3` | `Site_105-Border-Spine.corp.pseudoco.com` | Switches and Hubs | switch |
| `198.18.5.103` | `C9800.corp.pseudoco.com` | Wireless Controller | wlc |

## Intent sources

Fabric definitions read from Catalyst Center Template Programmer:

| Template | Project | Template ID | Last updated |
| --- | --- | --- | --- |
| `DEFN-BORDER-DMZ-TUNNELS.j2` | Site-105 | `eb6701a3-4b80-4c0a-a806-7cf363ec9141` | 2026-09-15 17:20 |
| `DEFN-CLIENT-PORTS.j2` | Site-105 | `19f95673-76a9-4c18-9bdb-eccb32b8b4b7` | 2026-09-15 17:20 |
| `DEFN-L3OUT.j2` | Site-105 | `174412e9-c286-489e-910d-2fbfcee5af3e` | 2026-09-15 17:20 |
| `DEFN-LOOPBACKS.j2` | Site-105 | `0b1a18c6-d41d-43db-aeed-b9d14c00c1c5` | 2026-09-15 17:20 |
| `DEFN-MCAST.j2` | Site-105 | `67224eb3-c18f-41a8-bf7f-b326f167e44e` | 2026-09-15 17:20 |
| `DEFN-NAC.j2` | Site-105 | `459e601b-fe30-4571-b004-5380be60cdfd` | 2026-09-15 17:20 |
| `DEFN-OVERLAY.j2` | Site-105 | `d1659043-f7bb-42df-8aa2-96e8a993d0f6` | 2026-09-15 17:20 |
| `DEFN-ROLES.j2` | Site-105 | `66c2c21d-6fc4-4431-b086-3a499b7f1324` | 2026-09-15 17:20 |
| `DEFN-TELEMETRY-SPLUNK.j2` | Site-105 | `cde9cc44-12fb-444d-b88e-65cd1b4dca03` | 2026-09-15 17:20 |
| `DEFN-VNIOFFSETS.j2` | Site-105 | `e7b8a6ce-6cc7-496f-820a-86fb21f80ae8` | 2026-09-15 17:20 |
| `DEFN-VRF.j2` | Site-105 | `e8c85b71-3e8f-43a5-94b6-dd0528b348e0` | 2026-09-15 17:20 |

From `settings.json`: SSID `PSEUDOCO-POD12`,
wireless VLANs 10, 101, 102,
1 access point(s).

## Checks

Intended values come from `settings.json` and the DEFN templates; observed
values are the corresponding field parsed out of the device's CLI output with
Genie. Every comparison is exact equality on a parsed field.

### Site_105-Leaf1.corp.pseudoco.com (172.30.255.1)

| Check | Result | Intended | Observed |
| --- | --- | --- | --- |
| VRFs defined | PASS | `VRF Main = Main` | `Main` |
|  | PASS | `VRF PROD = PROD` | `PROD` |
|  | PASS | `VRF IOT = IOT` | `IOT` |
| VRF route distinguishers | PASS | `Main RD = 172.30.255.1:10` | `172.30.255.1:10` |
|  | PASS | `PROD RD = 172.30.255.1:101` | `172.30.255.1:101` |
|  | PASS | `IOT RD = 172.30.255.1:102` | `172.30.255.1:102` |
| L3VNI bound to its transit VLAN | PASS | `VNI 110010 VLAN = 1010` | `1010` |
|  | PASS | `VNI 110101 VLAN = 1101` | `1101` |
|  | PASS | `VNI 110102 VLAN = 1102` | `1102` |
| L3VNI operationally up | PASS | `VNI 110010 (Main) state = Up` | `Up` |
|  | PASS | `VNI 110101 (PROD) state = Up` | `Up` |
|  | PASS | `VNI 110102 (IOT) state = Up` | `Up` |
| L3VNI bound to its VRF | PASS | `VNI 110010 VRF = Main` | `Main` |
|  | PASS | `VNI 110101 VRF = PROD` | `PROD` |
|  | PASS | `VNI 110102 VRF = IOT` | `IOT` |
| Tenant overlay VLANs active | PASS | `VLAN 10 (Main) = active` | `active` |
|  | PASS | `VLAN 101 (PROD) = active` | `active` |
|  | PASS | `VLAN 102 (IOT) = active` | `active` |
| Tenant SVI addresses | PASS | `Vlan10 address = 10.10.255.1` | `10.10.255.1` |
|  | PASS | `Vlan101 address = 10.101.255.1` | `10.101.255.1` |
|  | PASS | `Vlan102 address = 10.102.255.1` | `10.102.255.1` |
| Tenant SVIs up | PASS | `Vlan10 protocol = up` | `up` |
|  | PASS | `Vlan101 protocol = up` | `up` |
|  | PASS | `Vlan102 protocol = up` | `up` |
| DHCP helper on tenant SVIs | PASS | `Vlan10 helper = 198.18.5.102` | `198.18.5.102` |
|  | PASS | `Vlan101 helper = 198.18.5.102` | `198.18.5.102` |
|  | PASS | `Vlan102 helper = 198.18.5.102` | `198.18.5.102` |
| Underlay loopback address and state | PASS | `Loopback0 address = 172.30.255.1` | `172.30.255.1` |
|  | PASS | `Loopback0 protocol = up` | `up` |
| Client-facing ports present with the declared mode | PASS | `GigabitEthernet1/0/1 mode = access` | `access` |
|  | PASS | `GigabitEthernet1/0/2 mode = trunk` | `trunk` |
|  | PASS | `GigabitEthernet1/0/3 mode = access` | `access` |
| BGP autonomous system | PASS | `local ASN = 65535` | `65535` |
| EVPN sessions established | PASS | `peer 172.30.255.3 = established` | `established` |
| NVE peers up | PASS | `peer 172.30.255.2 = UP` | `UP` |
|  | PASS | `peer 172.30.255.3 = UP` | `UP` |
| L3OUT BGP neighbours on the border | SKIPPED | not applicable to this device | — |

### Site_105-Leaf2.corp.pseudoco.com (172.30.255.2)

| Check | Result | Intended | Observed |
| --- | --- | --- | --- |
| VRFs defined | PASS | `VRF Main = Main` | `Main` |
|  | PASS | `VRF PROD = PROD` | `PROD` |
|  | PASS | `VRF IOT = IOT` | `IOT` |
| VRF route distinguishers | PASS | `Main RD = 172.30.255.2:10` | `172.30.255.2:10` |
|  | PASS | `PROD RD = 172.30.255.2:101` | `172.30.255.2:101` |
|  | PASS | `IOT RD = 172.30.255.2:102` | `172.30.255.2:102` |
| L3VNI bound to its transit VLAN | PASS | `VNI 110010 VLAN = 1010` | `1010` |
|  | PASS | `VNI 110101 VLAN = 1101` | `1101` |
|  | PASS | `VNI 110102 VLAN = 1102` | `1102` |
| L3VNI operationally up | PASS | `VNI 110010 (Main) state = Up` | `Up` |
|  | PASS | `VNI 110101 (PROD) state = Up` | `Up` |
|  | PASS | `VNI 110102 (IOT) state = Up` | `Up` |
| L3VNI bound to its VRF | PASS | `VNI 110010 VRF = Main` | `Main` |
|  | PASS | `VNI 110101 VRF = PROD` | `PROD` |
|  | PASS | `VNI 110102 VRF = IOT` | `IOT` |
| Tenant overlay VLANs active | PASS | `VLAN 10 (Main) = active` | `active` |
|  | PASS | `VLAN 101 (PROD) = active` | `active` |
|  | PASS | `VLAN 102 (IOT) = active` | `active` |
| Tenant SVI addresses | PASS | `Vlan10 address = 10.10.255.1` | `10.10.255.1` |
|  | PASS | `Vlan101 address = 10.101.255.1` | `10.101.255.1` |
|  | PASS | `Vlan102 address = 10.102.255.1` | `10.102.255.1` |
| Tenant SVIs up | PASS | `Vlan10 protocol = up` | `up` |
|  | PASS | `Vlan101 protocol = up` | `up` |
|  | PASS | `Vlan102 protocol = up` | `up` |
| DHCP helper on tenant SVIs | PASS | `Vlan10 helper = 198.18.5.102` | `198.18.5.102` |
|  | PASS | `Vlan101 helper = 198.18.5.102` | `198.18.5.102` |
|  | PASS | `Vlan102 helper = 198.18.5.102` | `198.18.5.102` |
| Underlay loopback address and state | PASS | `Loopback0 address = 172.30.255.2` | `172.30.255.2` |
|  | PASS | `Loopback0 protocol = up` | `up` |
| Client-facing ports present with the declared mode | PASS | `GigabitEthernet1/0/1 mode = access` | `access` |
|  | PASS | `GigabitEthernet1/0/2 mode = trunk` | `trunk` |
|  | PASS | `GigabitEthernet1/0/3 mode = access` | `access` |
| BGP autonomous system | PASS | `local ASN = 65535` | `65535` |
| EVPN sessions established | PASS | `peer 172.30.255.3 = established` | `established` |
| NVE peers up | PASS | `peer 172.30.255.1 = UP` | `UP` |
|  | PASS | `peer 172.30.255.3 = UP` | `UP` |
| L3OUT BGP neighbours on the border | SKIPPED | not applicable to this device | — |

### Site_105-Border-Spine.corp.pseudoco.com (172.30.255.3)

| Check | Result | Intended | Observed |
| --- | --- | --- | --- |
| VRFs defined | PASS | `VRF Main = Main` | `Main` |
|  | PASS | `VRF PROD = PROD` | `PROD` |
|  | PASS | `VRF IOT = IOT` | `IOT` |
| VRF route distinguishers | PASS | `Main RD = 172.30.255.3:10` | `172.30.255.3:10` |
|  | PASS | `PROD RD = 172.30.255.3:101` | `172.30.255.3:101` |
|  | PASS | `IOT RD = 172.30.255.3:102` | `172.30.255.3:102` |
| L3VNI bound to its transit VLAN | PASS | `VNI 110010 VLAN = 1010` | `1010` |
|  | PASS | `VNI 110101 VLAN = 1101` | `1101` |
|  | PASS | `VNI 110102 VLAN = 1102` | `1102` |
| L3VNI operationally up | PASS | `VNI 110010 (Main) state = Up` | `Up` |
|  | PASS | `VNI 110101 (PROD) state = Up` | `Up` |
|  | PASS | `VNI 110102 (IOT) state = Up` | `Up` |
| L3VNI bound to its VRF | PASS | `VNI 110010 VRF = Main` | `Main` |
|  | PASS | `VNI 110101 VRF = PROD` | `PROD` |
|  | PASS | `VNI 110102 VRF = IOT` | `IOT` |
| Tenant overlay VLANs active | SKIPPED | not applicable to this device | — |
| Tenant SVI addresses | SKIPPED | not applicable to this device | — |
| Tenant SVIs up | SKIPPED | not applicable to this device | — |
| DHCP helper on tenant SVIs | SKIPPED | not applicable to this device | — |
| Underlay loopback address and state | PASS | `Loopback0 address = 172.30.255.3` | `172.30.255.3` |
|  | PASS | `Loopback0 protocol = up` | `up` |
| Client-facing ports present with the declared mode | SKIPPED | not applicable to this device | — |
| BGP autonomous system | PASS | `local ASN = 65535` | `65535` |
| EVPN sessions established | PASS | `peer 172.30.255.1 = established` | `established` |
|  | PASS | `peer 172.30.255.2 = established` | `established` |
| NVE peers up | PASS | `peer 172.30.255.1 = UP` | `UP` |
|  | PASS | `peer 172.30.255.2 = UP` | `UP` |
| L3OUT BGP neighbours on the border | PASS | `Main neighbour 192.168.255.0 ASN = 65534` | `65534` |
|  | PASS | `PROD neighbour 192.168.255.2 ASN = 65534` | `65534` |
|  | PASS | `IOT neighbour 192.168.255.4 ASN = 65534` | `65534` |

### C9800.corp.pseudoco.com (198.18.5.103)

| Check | Result | Intended | Observed |
| --- | --- | --- | --- |
| SSID provisioned on the controller | PASS | `SSID PSEUDOCO-POD12 = PSEUDOCO-POD12` | `PSEUDOCO-POD12` |
| SSID administratively up | PASS | `PSEUDOCO-POD12 status = UP` | `UP` |
| Access points registered | PASS | `SITE-105-AP-1 state = Registered` | `Registered` |
| Access point Ethernet MAC matches settings.json | PASS | `SITE-105-AP-1 Ethernet MAC = 084fa950f028` | `084fa950f028` |
| Access point on Catalyst Center tags | PASS | `SITE-105-AP-1 tag source = Static` | `Static` |
| Access point site and policy tags are not the factory defaults | PASS | `SITE-105-AP-1 policy tag = Catalyst Center generated` | `Catalyst Center generated` |
|  | PASS | `SITE-105-AP-1 site tag = Catalyst Center generated` | `Catalyst Center generated` |


