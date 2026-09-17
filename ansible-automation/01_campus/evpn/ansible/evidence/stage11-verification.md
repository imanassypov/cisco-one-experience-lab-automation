# Stage 11 — Intent verification

Generated 2026-09-17 11:28:45 UTC by `11_verify_intent.yml`.

Declared intent is compared against live device state collected through
Catalyst Center Command Runner. Intent comes from `settings.json` and from the
`DEFN-*.j2` templates **as stored in Catalyst Center**, so this report reflects
what was actually deployed rather than what the repo currently says.

## Result

| Outcome | Count |
| --- | --- |
| Pass | 45 |
| Fail | 0 |
| Not verified | 0 |
| Not applicable | 7 |

**PASSED** —
52 check(s) across
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
| `DEFN-BORDER-DMZ-TUNNELS.j2` | Site-105 | `a1fc4c69-015f-42d9-ab39-7f21efd4abd3` | 2026-09-16 19:12 |
| `DEFN-CLIENT-PORTS.j2` | Site-105 | `3d290b65-95d3-4920-8ffb-65218d672f4b` | 2026-09-16 19:12 |
| `DEFN-L3OUT.j2` | Site-105 | `190226ca-3af6-460b-8ee1-15340a2cee10` | 2026-09-16 19:12 |
| `DEFN-LOOPBACKS.j2` | Site-105 | `613fe72a-fa25-4934-8fae-a9261e6c3112` | 2026-09-16 19:12 |
| `DEFN-MCAST.j2` | Site-105 | `d3b22354-f24a-43f7-b7b8-10a477f4ee7f` | 2026-09-16 19:12 |
| `DEFN-NAC.j2` | Site-105 | `46b613ed-0cd5-4680-bb89-a4fa7a71c619` | 2026-09-16 19:12 |
| `DEFN-OVERLAY.j2` | Site-105 | `a02e46bd-ae64-4510-91f8-193f90cb729f` | 2026-09-16 19:12 |
| `DEFN-ROLES.j2` | Site-105 | `c9755fe0-ef1f-4a24-8d61-cfe7a9aa5b80` | 2026-09-16 19:12 |
| `DEFN-TELEMETRY-SPLUNK.j2` | Site-105 | `b59453d7-1fac-4faf-ab8d-f97c9029122f` | 2026-09-16 19:12 |
| `DEFN-VNIOFFSETS.j2` | Site-105 | `48879331-bbce-44ce-85e1-e40ee1faa87a` | 2026-09-16 19:12 |
| `DEFN-VRF.j2` | Site-105 | `15b72b9a-4a62-4b11-b3e7-645952bf0f27` | 2026-09-17 11:20 |

From `settings.json`: SSID `PSEUDOCO-POD05`,
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
| SSID provisioned on the controller | PASS | `SSID PSEUDOCO-POD05 = PSEUDOCO-POD05` | `PSEUDOCO-POD05` |
| SSID administratively up | PASS | `PSEUDOCO-POD05 status = UP` | `UP` |
| Access point count matches settings.json | PASS | `access points joined = 1` | `1` |
| Access points registered | PASS | `SITE-105-AP-1 state = Registered` | `Registered` |
| Access point Ethernet MAC matches settings.json | PASS | `SITE-105-AP-1 Ethernet MAC = 084fa950f028` | `084fa950f028` |
| Access point on Catalyst Center tags | PASS | `SITE-105-AP-1 tag source = Static` | `Static` |
| Access point site and policy tags are not the factory defaults | PASS | `SITE-105-AP-1 policy tag = Catalyst Center generated` | `Catalyst Center generated` |
|  | PASS | `SITE-105-AP-1 site tag = Catalyst Center generated` | `Catalyst Center generated` |


