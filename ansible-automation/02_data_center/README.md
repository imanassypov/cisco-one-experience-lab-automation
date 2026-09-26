# 02 — Data Center

Automation for the data center section of the lab.

## Tracks

- **`nac_vxlan/`** — the Pseudoco-DC1 VXLAN EVPN fabric on Nexus Dashboard
  4.2.1.10, built with [Cisco Nexus as Code](https://netascode.cisco.com/docs/data_models/vxlan/overview/)
  (`cisco.nac_dc_vxlan` over `cisco.dcnm`). Covers the guide's **NDFC - DC
  Fabric Deployment** section: fabric, five switches, vPC pair, server
  port-channels, and the MAIN / PROD / IOT VRFs and networks.
  See [`nac_vxlan/ansible/README.md`](nac_vxlan/ansible/README.md).

Nothing else in the data center is automated yet. The HQ services that live
there — Catalyst Center, ISE, AD, the WLC, Splunk — are driven from other
collections: the WLC and Catalyst Center from `01_campus/evpn`, Splunk from
`07_assurance/splunk_evpn`.

## Quick start

This track needs `cisco.nac_dc_vxlan`, `cisco.dcnm` and `cisco.nxos`, which
are newer than the campus collections. A `~/venv` built before the DC track
was added does
not have them, and the symptom is misleading — Ansible reports a missing
collection as `the role 'cisco.nac_dc_vxlan.validate' was not found`. Install
them once:

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/02_data_center/nac_vxlan/ansible
ansible-galaxy collection install -r collections/requirements.yml --force
ansible-galaxy collection list | grep -E 'nac_dc_vxlan|dcnm|nxos'
```

`--force` matters: without it `ansible-galaxy` silently skips a collection
already present at any version. Re-running
`00_scriptserver_bootstrap/playbooks/01_bootstrap_script_server.yml` does the
same thing and is the durable fix, since that is what installs on a fresh pod.

Then:

```bash
ansible-playbook playbooks/00_discover_dc_switch_serials.yml   # once, first
ansible-playbook playbooks/01_dc_deploy.yml
```

Run from the directory holding `ansible.cfg`, not from `playbooks/` — the same
convention as `01_campus/evpn`.

The numbers carry information. `01_dc_deploy.yml` imports stages 02 through
04 and nothing else, so a playbook numbered inside that range runs as part of
the orchestrated build, while `00_discover_dc_switch_serials.yml` below it and
`05_remove.yml` / `06_external_fabric.yml` above it are ones you run
deliberately, by name.

Read `nac_vxlan/ansible/README.md` first. Four things in particular. The
discovery stage is not part of the orchestrator: it SSHes to the switches,
reads a serial number off each one, and generates the switch half of the data
model from them, so you have to run it once yourself before anything else —
`01_dc_deploy.yml` stops at stage 02 until you have. What it generates is
build output rather than something you maintain, so every run overwrites
`topology_switches.nac.yaml` silently and changes belong in the tracked
`.example` beside it or in the switch table it reads — which also means a
`git pull` that changes either source does not reach Nexus Dashboard until
you re-run the discovery stage. `01_dc_deploy.yml` then erases the running
configuration of all five switches as it imports them, with no confirmation
prompt and no way to turn it off. That import is also the one
place the pipeline appears to hang: its inventory step sits with no output for
several minutes while Nexus Dashboard discovers the five switches behind a
blocking HTTP request, so let it run — on a checkout older than the
1000-second timeouts in `inventory/group_vars/nd/connection.yml` it fails there
instead, with `command timeout triggered, timeout value is 30 secs`. And
VRF-Lite to the IOS-XE edge router is still manual.

One further symptom is worth knowing by name, because the fix is not the
obvious one. If the build fails at step `interface_all` with an HTTP 500 on
`globalInterface` and the words `template execution` in the message, the
suspect is a non-ASCII character in a port-channel description — the em
dashes that were in the data model until 2026-09-25. They are plain hyphens
in the tracked files now, but pulling that change does not on its own fix a
script server: what Nexus Dashboard reads is the *generated*
`topology_switches.nac.yaml`, so re-run the discovery stage after the pull,
with the VPN up. The collection README carries the evidence, and the reasons
this is a suspicion rather than a proven cause.

A second symptom, further along the same run, is `Entered network VLAN id 2300
is already in use` at the `networks` step, reported inside an HTTP 200 body
rather than as an error. Every VRF and network in the data model now carries an
explicit `vlan_id` - VRFs 2000, 2001, 2002 and networks 2300, 2301, 2302 - and
that is the fix. The reason it is needed is that omitting the VLAN is only safe
in the GUI: the guide's "Propose VLAN" button allocates one object at a time
with a save in between, whereas `cisco.dcnm` asks the controller for the next
free VLAN once per object in a single loop, and reading a free VLAN does not
reserve it, so all three objects are handed the same number. Give any VRF or
network you add an explicit VLAN too. These two files are read straight by the
create role, so a plain `git pull` is enough here - no discovery re-run.

## Where the automation stops

The pipeline carries everything `cisco.nac_dc_vxlan` 0.9.0 can express, which
is all of guide sections 4, 5 and 6. External connectivity — sections 7 and 8
— is outside the data model and stays manual for now.

In this lab the External fabric and the IOS-XE edge router
`DC-SITE11-CEDGE8Kv` (`198.18.133.14`) are a **prerequisite**, built in Nexus
Dashboard before the pipeline runs: the fabric in Monitor Mode, the router
discovered into it as an Edge Router. `06_external_fabric.yml` can create the
fabric object if it is genuinely missing, but it cannot set Monitor Mode or
add a non-NX-OS device, so it refuses to touch a fabric that already exists.

Extending MAIN, PROD and IOT out of DC-Service-Leaf over VRF-Lite is also
manual. The collection README's TODO records what that would take, and why
the Nexus as Code model cannot express it today.
