# 02 - Data Center

Automation for the data center section of the lab: the VXLAN EVPN fabric that
extends PseudoCo's MAIN / PROD / IOT segmentation from the campus and SD-WAN
domains into the data center, so a workload is governed by the same business
segment as the user reaching it.

## Tracks

**`nac_vxlan/`** builds the `Pseudoco-DC1` VXLAN EVPN fabric on Cisco Nexus
Dashboard 4.2.1.10 with [Cisco Nexus as Code](https://netascode.cisco.com/docs/data_models/vxlan/overview/)
(`cisco.nac_dc_vxlan` over `cisco.dcnm`). It covers sections 4, 5 and 6 of the
student guide's **NDFC - DC Fabric Deployment**: the fabric and its five
switches, the DC-Leaf1 / DC-Leaf2 vPC pair and the three server port-channels,
and the MAIN / PROD / IOT VRFs and networks with their attachments.

See [`nac_vxlan/ansible/README.md`](nac_vxlan/ansible/README.md) for how to
run it and how the data model is put together.

Nothing else in the data center is automated from here. The HQ services hosted
there - Catalyst Center, ISE, Active Directory, the WLC and Splunk - are
driven from other collections: the WLC and Catalyst Center from
`01_campus/evpn`, Splunk from `07_assurance/splunk_evpn`.

## Quick start

Run on the Kali script server, from the directory holding `ansible.cfg`:

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/02_data_center/nac_vxlan/ansible
ansible-playbook playbooks/00_discover_dc_switch_serials.yml   # once, first
ansible-playbook playbooks/01_dc_deploy.yml
```

This track needs `cisco.nac_dc_vxlan`, `cisco.dcnm` and `cisco.nxos`, which
are newer than the campus collections. If your `~/venv` predates this track,
`git pull` and re-run
`00_scriptserver_bootstrap/playbooks/01_bootstrap_script_server.yml`, which is
what installs them.

Four things are worth knowing before that first run, and the collection README
covers each in full:

- **Stage 00 comes first and is not part of the orchestrator.** It reads a
  serial number off each switch over SSH and generates the switch half of the
  data model, so it needs the client VPN up. `01_dc_deploy.yml` will not get
  past stage 02 until it has run once.
- **What stage 00 generates is build output.** Every run overwrites
  `topology_switches.nac.yaml`, so changes belong in the tracked sources
  beside it. A `git pull` that touches either source does not reach Nexus
  Dashboard until you re-run stage 00.
- **Stage 02 erases the running configuration of all five switches** as it
  imports them, with no prompt and no way to disable it.
- **Stage 02's import step runs for several minutes with no output.** The
  controller holds the request open while it discovers the switches. That is
  expected, not a hang.

## What the pipeline covers

`01_dc_deploy.yml` imports stages 02 through 05 and nothing else: create the
intent on the controller, apply the fabric settings Nexus as Code has no key
for, deploy the lot to the switches, then verify the result against the
declared model. Stage 05 is read-only and writes
`evidence/stage05-verification.md`.

Stage 03 is the one that is not Nexus as Code. It writes the guide's
Resources-tab settings - VRF Lite Deployment, its subnet pool, the two auto
options - plus the License Tier, the Telemetry toggle and the fabric's map
location, none of which exist in the `cisco.nac_dc_vxlan` 0.9.0 data model.
Without it the fabric is left with VRF Lite Deployment at `Manual`, and
external connectivity cannot be built. Its values live in
`nac_vxlan/ansible/inventory/group_vars/all/dc_advanced_settings.yml`.

Playbooks numbered outside that range are ones you run deliberately, by name:
`00_discover_dc_switch_serials.yml` below it, `06_remove.yml` and
`07_external_fabric.yml` above it.

## Where the automation stops

The pipeline carries everything `cisco.nac_dc_vxlan` 0.9.0 can express for
this guide, and the fabric settings it cannot. External connectivity, guide
sections 7 and 8, stays manual.

The External fabric and the IOS-XE edge router `DC-SITE11-CEDGE8Kv`
(`198.18.133.14`) are a **prerequisite**, built in Nexus Dashboard before the
pipeline runs: the fabric in Monitor Mode, the router discovered into it as an
Edge Router. Neither Monitor Mode nor a non-NX-OS device can be declared in
the model.

Extending MAIN, PROD and IOT out of DC-Service-Leaf over VRF-Lite is still
manual, though stage 03 now puts the fabric-level settings it depends on in
place. The verification report makes that boundary visible rather than hiding
it: DC-Service-Leaf appears under "Not attached" on every VRF row, which is
expected. The collection README records what closing the gap would take.
