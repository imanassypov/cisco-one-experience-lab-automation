# 02 - Data Center

This directory contains the Infrastructure as Code track for the data center fabric in the lab. It builds a VXLAN EVPN fabric on Cisco Nexus Dashboard and extends the MAIN, PROD, and IOT segments used by the campus and SD-WAN tracks.

The automation is an alternative to the manual Nexus Dashboard deployment in the student guide. Run one track or the other. Both tracks build the same `Pseudoco-DC1` fabric on the same pod.

Each VRF leaves the fabric to the edge router through one Nexus Dashboard **L3Out**: a routed sub-interface on the border leaf plus an eBGP session. In the Nexus Dashboard UI they appear under **Manage > Routing Policies > L3Outs**; the VRF attachments themselves show Extend `NONE`.

## What the automation builds

The `ansible/` track uses Cisco Nexus as Code (`cisco.nac_dc_vxlan`) with the `cisco.dcnm` collection for stage 02, and `cisco.nd` for the stages after it. It automates the fabric-side work covered by sections 4 through 8 of the guide:

- The `Pseudoco-DC1` VXLAN EVPN fabric and its five switches.
- The DC-Leaf1/DC-Leaf2 vPC pair and three server port-channels.
- The MAIN, PROD, and IOT VRFs and networks.
- The External fabric and its IOS-XE edge router as a monitored device.
- Three VRF-Lite handoffs from DC-Service-Leaf, built as L3Outs.

The edge router is already configured by the pod. The pipeline discovers it and adds it to the External fabric, but does not change its configuration. This is intentional: the External fabric is in Monitor Mode and the router's sub-interfaces and BGP peers are pre-built.

Other services in the data center, including Catalyst Center, ISE, WLC, and Splunk, are automated by the campus and assurance tracks.

See [`ansible/README.md`](ansible/README.md) for the complete data-model walkthrough.

## Prerequisites

Run the commands below on the Kali script server, not on the laptop. The script server must have:

- The client VPN connected when running serial discovery.
- A current checkout of this repository.
- The repo-root `.vault` file and pod values created by stage 00 bootstrap.
- The pinned Ansible collections installed in `~/venv`.

If the script server was staged before this data-center track was added, pull the repository and run stage 00 bootstrap again:

```bash
cd ~/cisco-one-experience-lab-automation
git pull
cd ansible-automation/00_scriptserver_bootstrap
ansible-playbook playbooks/01_bootstrap_script_server.yml
```

The bootstrap installs and verifies these collections:

| Collection | Version | Purpose |
|---|---:|---|
| `cisco.nac_dc_vxlan` | 0.9.0 | Validates and applies the Nexus as Code model |
| `cisco.dcnm` | 3.13.0 | Communicates with Nexus Dashboard |
| `cisco.nxos` | 10.2.0 | Reads switch serials and BGP state over SSH |
| `ansible.netcommon` | 7.1.0 | Network connection support |
| `ansible.utils` | 5.1.2 | Ansible utility filters and helpers |
| `ansible.posix` | 2.0.0 | POSIX modules used by the automation |
| `community.general` | 10.1.0 | Supporting modules and filters |

The Python environment uses `ansible-core 2.17.14`. Stage 00 verifies the collection versions and runs `pip check` before it reports success.

## Run the track

Run from the directory that contains `ansible.cfg`:

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/02_data_center/ansible
ansible-playbook playbooks/00_discover_dc_switch_serials.yml
ansible-playbook playbooks/01_dc_deploy.yml
```

The first command is a prerequisite, not part of the orchestrator. It reads each switch serial over SSH and generates `playbooks/host_vars/Pseudoco-DC1/topology_switches.nac.yaml`. That file is build output and is overwritten on every run. Change the tracked `dc_switches.yml` or `topology_switches.nac.yaml.example` instead.

Stages 03 to 05, 07 and 08 use `cisco.nd`, a pre-release collection taken from git at a tested commit. The script-server bootstrap installs it into this track's own `ansible/collections/` folder, which only this track's `ansible.cfg` searches. On a server bootstrapped before this change, install it once by hand:

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/02_data_center/ansible
ansible-galaxy collection install -r collections/requirements-cisco-nd.yml -p collections --no-deps --force
pip install -r ../../requirements.txt
```

The orchestrator runs each stage as its own `ansible-playbook` process, in this order, and stops at the first failure:

```text
02_create_dc_fabric.yml          cisco.nac_dc_vxlan / cisco.dcnm
03_fabric_advanced_settings.yml  cisco.nd
04_external_fabric.yml           cisco.nd
05_l3out.yml                     cisco.nd
06_recalculate_and_deploy.yml    cisco.nac_dc_vxlan / cisco.dcnm
07_verify_fabric.yml             cisco.nd, plus SSH to the border leaf
```

Separate processes keep the `cisco.dcnm` and `cisco.nd` connections to Nexus Dashboard apart. Each stage's output appears when the stage finishes and is also saved under `ansible/evidence/dc-deploy-<run>/`. Stage 04 creates the External fabric, adds the edge router and builds the eBGP VRF-Lite inter-fabric link. Stage 05 creates and attaches the three L3Outs. Stage 06 deploys everything once.

## Intent and configuration

The `*.nac.yaml` files under `ansible/playbooks/host_vars/Pseudoco-DC1/` are the Nexus as Code model. They describe the fabric, switches, vPC, VRFs, networks, and endpoint attachments.

The files under `ansible/inventory/group_vars/all/` hold values that the current Nexus as Code model cannot express:

- `dc_switches.yml`: switch addresses, roles, and endpoint interfaces.
- `dc_advanced_settings.yml`: non-VRF fabric-object properties such as license tier, telemetry, and location.
- `dc_external_settings.yml`: the External fabric and monitored edge router.
- `dc_vrf_lite.yml`: all VRF-Lite intent, including fabric mode and subnet pool, inter-fabric link settings, and the three L3Outs with dot1q tags, addresses, and BGP neighbors. Keys match the `cisco.nd` module options.

The model is the source of truth for the objects it describes. To change those objects, edit the model, run the pipeline, and review the verification report. Do not make an undocumented UI change and expect the repository to record it.

## Important behavior

- Stage 02 imports all five switches with `preserve_config: false`. This erases their existing running configuration without prompting. Use a pod that is safe to rebuild.
- Stage 02 can remain silent for several minutes while Nexus Dashboard discovers the switches. Do not interrupt that request unless it has clearly exceeded the expected time.
- Stage 05 requires the inter-fabric link from stage 04 and stops with a message naming stage 04 if it is missing. Its attach step reports `changed` on every run, because the module cannot read whether an L3Out is already attached.
- Two values are still open and can be switched per run while the pod settles them: how `interface_name` is written (`-e dc_vrf_lite_interface_form=subinterface`), and which `peer_vrf` names Nexus Dashboard accepts for the External fabric.
- The External edge router is not configured by this repository. Its side of the VRF-Lite links must remain consistent with the fixed values in `dc_vrf_lite.yml`.

## Verification

Stage 07 is read-only and writes `ansible/evidence/stage07-verification-<run>.md` together with a matching `.html`, the same findings laid out as a formal report, and the raw L3Out collection as `stage07-l3outs-<run>.json`. It compares the controller state with the declared model for switches, VRFs, networks, and the three L3Outs (VRF, interface, dot1q tag, addresses, MTU and peer ASN). No module reports whether an L3Out is attached, so that is proven on the switch instead: the three sub-interfaces are parsed from `show interface` on DC-Service-Leaf with pyATS/Genie and compared on dot1q tag, address and MTU.

It also reads BGP session state from DC-Service-Leaf over SSH when `dc_verify_bgp_sessions` is enabled. A reachable switch adds three BGP checks; an unreachable switch produces `not determined` rows rather than claiming that the sessions are down. The BGP check can be skipped with:

```bash
ansible-playbook playbooks/07_verify_fabric.yml -e dc_verify_bgp_sessions=false
```

The report does not verify the edge router's configuration or data-plane traffic. Those remain outside the pipeline's ownership.

## Other playbooks

- `08_cleanup.yml` is a destructive teardown and is not called by the orchestrator. It requires `-e dc_cleanup_confirm=CLEANUP_OK`. It detaches and deletes the L3Outs, then removes the overlays, the inter-fabric link, the switches and both fabrics, in that order, and then defaults `Ethernet1/8` on the border leaf so the sub-interfaces it built do not survive into the next run.

For implementation details, see [`ansible/README.md`](ansible/README.md).
