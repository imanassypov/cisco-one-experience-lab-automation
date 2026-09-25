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

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/02_data_center/nac_vxlan/ansible
ansible-playbook playbooks/00_dc_deploy.yml
```

Run from the directory holding `ansible.cfg`, not from `playbooks/` — the same
convention as `01_campus/evpn`.

Read `nac_vxlan/ansible/README.md` first. Three things in particular. The
first run stops at stage 03 by design: stage 02 prints the switch serial
numbers and you transcribe them into the data model yourself, which is the
point of that stage. `00_dc_deploy.yml` erases the running configuration of
all five switches as it imports them, with no confirmation prompt and no way
to turn it off. And VRF-Lite to the IOS-XE edge router is still manual.

## Where the automation stops

The pipeline carries everything `cisco.nac_dc_vxlan` 0.9.0 can express, which
is all of guide sections 4, 5 and 6. External connectivity — sections 7 and 8
— is outside the data model and stays manual for now.

In this lab the External fabric and the IOS-XE edge router
`DC-SITE11-CEDGE8Kv` (`198.18.133.14`) are a **prerequisite**, built in Nexus
Dashboard before the pipeline runs: the fabric in Monitor Mode, the router
discovered into it as an Edge Router. `07_external_fabric.yml` can create the
fabric object if it is genuinely missing, but it cannot set Monitor Mode or
add a non-NX-OS device, so it refuses to touch a fabric that already exists.

Extending MAIN, PROD and IOT out of DC-Service-Leaf over VRF-Lite is also
manual. The collection README's TODO records what that would take, and why
the Nexus as Code model cannot express it today.
