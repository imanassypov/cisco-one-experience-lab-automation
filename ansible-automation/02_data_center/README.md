# 02 - Data Center

Automation for the data center section of the lab: the VXLAN EVPN fabric that
extends PseudoCo's MAIN / PROD / IOT segmentation from the campus and SD-WAN
domains into the data center, so a workload is governed by the same business
segment as the user reaching it.

## Tracks

**`nac_vxlan/`** builds the `Pseudoco-DC1` VXLAN EVPN fabric on Cisco Nexus
Dashboard 4.2.1.10 with [Cisco Nexus as Code](https://netascode.cisco.com/docs/data_models/vxlan/overview/)
(`cisco.nac_dc_vxlan` over `cisco.dcnm`). It reaches the same end state as
sections 4 to 8 of the student guide's **NDFC - DC Fabric Deployment - Manual
Provisioning**: the fabric and its five switches, the DC-Leaf1 / DC-Leaf2 vPC
pair and the three server port-channels, the MAIN / PROD / IOT VRFs and
networks with their attachments, the External fabric with its edge router, and
the three VRF-Lite extensions out of DC-Service-Leaf.

That is the DC fabric automated end to end. The pipeline does not configure
the external edge router itself, and that is by design rather than a gap: this
lab ships `DC-SITE11-CEDGE8Kv` pre-configured, so there is nothing on it for
the automation to write. See [Where the pipeline stops, by
design](#where-the-pipeline-stops-by-design).

The student guide documents this track in its own right, as the nine cards of
**NDFC - DC Fabric Deployment - Infrastructure as Code**. The two are
alternatives rather than a sequence: both build the same fabric on the same
pod, so run one or the other.

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

Two commands, and that is the whole build. This used to need a third - a
second run of the deploy stage - and it no longer does. The asynchronous wait
that made the second run necessary now happens inside stage 05, so one
Recalculate and Deploy is enough. See [The wait that replaced the second
deploy](#the-wait-that-replaced-the-second-deploy).

This track needs `cisco.nac_dc_vxlan`, `cisco.dcnm` and `cisco.nxos`, which
are newer than the campus collections. If your `~/venv` predates this track,
`git pull` and re-run
`00_scriptserver_bootstrap/playbooks/01_bootstrap_script_server.yml`, which is
what installs them.

Five things are worth knowing before that first run, and the collection README
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
- **Stage 05 can sit for up to two minutes with no output.** It is waiting for
  Nexus Dashboard to correlate the border leaf's CDP adjacency to the edge
  router, which the controller does asynchronously after stage 04 adds that
  router. The stage retries rather than failing, and that wait is what removed
  the old second deploy.

## What the pipeline covers

`01_dc_deploy.yml` imports stages 02 through 07 and nothing else: create the
intent on the controller, apply the fabric settings Nexus as Code has no key
for, create the External connectivity fabric, attach the VRF-Lite extensions,
deploy the lot to the switches, then verify the result against the declared
model. Stage 07 is read-only and writes `evidence/stage07-verification.md`.

The single most useful thing to know about that order is where the line falls
between intent and configuration. **Stages 02 to 05 all write intent to Nexus
Dashboard and change nothing on a switch. Stage 06 is the only stage that
changes running configuration.** That is why three stages can sit ahead of the
deploy without leaving the switches behind, and it is why the whole external
handoff lands in a single Recalculate and Deploy.

Three of those stages are not Nexus as Code, because what they declare has no
key in the `cisco.nac_dc_vxlan` 0.9.0 data model.

Stage 03 writes the guide's Resources-tab settings - VRF Lite Deployment, its
subnet pool, the two auto options - plus the License Tier, the Telemetry
toggle and the fabric's map location. Without it the fabric is left with VRF
Lite Deployment at `Manual`, and external connectivity cannot be built at all.
Its values live in
`nac_vxlan/ansible/inventory/group_vars/all/dc_advanced_settings.yml`.

Stage 04 is the only stage that builds a second fabric. It creates `External`,
ASN 65531, in Fabric Monitor Mode, from
`nac_vxlan/ansible/inventory/group_vars/all/dc_external_settings.yml`, and
adds the IOS-XE edge router to it. It runs before the deploy because this is
the fabric on the far side of the VRF-Lite handoff.

Stage 05 attaches the three VRF-Lite extensions on DC-Service-Leaf, one per
VRF, from `nac_vxlan/ansible/inventory/group_vars/all/dc_vrf_lite.yml`. The
data model cannot express these: a `vrf_attach_group` entry names a switch and
nothing else, with no key for `EXTEND: VRF_LITE`, the sub-interface, the dot1q
tag or the neighbour address. So the stage calls `cisco.dcnm.dcnm_vrf`
directly, which does support `attach[].vrf_lite[]`. Two things about it are
worth carrying: it uses `state: merged` so the leaf attachments stage 02 made
survive, and it has to run after stage 02 on **every** pass, because stage
02's create role runs `dcnm_vrf` with `state: replaced` against a model that
deliberately omits the border leaf - so every create run detaches the
extensions and stage 05 puts them back.

Playbooks numbered outside that range are ones you run deliberately, by name:
`00_discover_dc_switch_serials.yml` below it and `08_remove.yml` above it.

## The wait that replaced the second deploy

**The pipeline no longer deploys twice.** It used to: the deploy stage, fired
straight after `04_external_fabric.yml`, reported `0/5` switches to deploy
back then, and a second run a minute later picked up
exactly one switch, the border leaf, and deployed it in seconds. Nothing
drifted in between and nobody touched a switch.

The reason for that is still true, and it is why the wait exists. **Nexus
Dashboard correlates the CDP adjacency between the border leaf and the edge
router asynchronously.** Adding the router in stage 04 returns HTTP 202 with
an empty body; the controller onboards it and works out the adjacency
afterwards, on its own schedule. Anything that depends on that adjacency and
asks a question seconds later gets an honest nothing.

What changed is where the waiting happens. A VRF-Lite extension cannot be
attached until the inter-fabric link that `VRF_LITE_AUTOCONFIG` builds exists,
and the controller builds that only once it has the adjacency - so stage 05
retries its `dcnm_vrf` call with `until`/`retries`, six attempts twenty
seconds apart, instead of failing. Raise it with
`-e dc_vrf_lite_retries=12`. Because that wait happens while intent is being
*staged*, stage 06 finds the work already there and one Recalculate and Deploy
carries the parent interface, the three sub-interfaces and their BGP
neighbours together.

Only the border leaf ever reacts, because Cisco scopes VRF-Lite
autoconfiguration to *"Border role in the VXLAN fabric and Edge Router role in
the connected external fabric device"*
([NDFC - VRF Lite](https://www.cisco.com/c/en/us/td/docs/dcn/ndfc/1221/articles/ndfc-vrf-lite/vrf-lite.html)).
`DC-Service-Leaf` is the fabric's only `border` switch and `DC-SITE11-CEDGE8Kv`
its only `edgeRouter`. The two leaves and two spines are outside that scope.

The habit worth keeping generalises past this stage: **"no changes" is a
statement about one instant, not proof the fabric is finished.** Trust
`check_sync -> in_sync=True` after a run that deployed something, or a clean
`07_verify_fabric.yml`. And prefer waiting for a precondition in code over
telling somebody to run a playbook twice.

The two fabric settings behind all of this - `VRF_LITE_AUTOCONFIG` set to
`Back2Back&ToExternal` and `AUTO_SYMMETRIC_VRF_LITE` set to `true`, both
written by stage 03 - are documented against the Cisco Nexus Dashboard 4.2.1
references in
[`nac_vxlan/ansible/README.md`](nac_vxlan/ansible/README.md#the-two-vrf-lite-settings-as-cisco-defines-them)
and in the comments of `dc_advanced_settings.yml`. The short version is that
the first one is what makes the handoff possible at all, and the second one
has nothing to act on here, because it only ever configures a *managed NX-OS
neighbour* and this pod's neighbour is a pre-configured IOS-XE router the
controller deliberately does not manage.

## Where the pipeline stops, by design

The pipeline carries the whole DC fabric: everything `cisco.nac_dc_vxlan`
0.9.0 can express for this guide, the fabric settings it cannot, all of guide
section 7 - the External fabric and the IOS-XE edge router in it - and all of
section 8 on the fabric side, both the Recalculate and Deploy that
synchronises the two fabrics and the three per-VRF extensions themselves.

**What it does not configure is the edge router, and that is deliberate.**
This lab ships `DC-SITE11-CEDGE8Kv` (`198.18.133.14`) already configured: its
sub-interfaces and BGP neighbours for MAIN, PROD and IOT are built into the
pod before you get it. There is nothing there for the automation to write.

Three consequences follow from that, and each is a decision rather than a
limitation:

- **`IS_READ_ONLY: true` on the External fabric is the correct setting.**
  Fabric Monitor Mode is what stops Nexus Dashboard writing to a device whose
  configuration it does not own. Cisco: *"When an external fabric is set to
  Fabric Monitor Mode Only, you cannot deploy configurations on the
  switches."* Here that is the protection, not the obstacle - the router is
  added to the fabric so the controller can *see* it over CDP and resolve the
  handoff, not so it can reconfigure it.
- **The VRF-Lite addresses in `dc_vrf_lite.yml` are pinned, not
  auto-allocated.** `AUTO_UNIQUE_VRF_LITE_IP_PREFIX` is on and the controller
  could cut its own /30s out of `DCI_SUBNET_RANGE`, which is the right thing
  in a greenfield build. Here the far end already exists at fixed addresses,
  so the fabric has to meet it exactly. Pinning is a requirement of the lab
  design, not a shortcut.
- **`AUTO_SYMMETRIC_VRF_LITE` has nothing to reach.** It only configures a
  managed NX-OS neighbour, and this neighbour is neither NX-OS nor managed.

Stage 04's route to adding that router is worth knowing anyway, because it is
not the obvious one. Neither of its steps uses Nexus as Code, and the router
is not added with `dcnm_inventory`. The legacy NDFC API that `dcnm_inventory`
and Nexus as Code both drive has no IOS-XE support: it ignores a device-type
field and uses NX-OS SNMPv3 discovery, which returns HTTP 200 with a
`SNMPv3 Timeout` status and no device identity. The ND 4.x manage API does
support it, as `platformType: "ios-xe"`, so stage 04 calls that API directly -
`actions/shallowDiscovery` to read the router's model, version and serial
number, then `switches?ticketId=` to add it. The collection README has the
detail.

The verification report draws the same boundary rather than hiding it. Stage
07's fourteen checks include one per VRF-Lite extension on the border leaf,
and its closing section lists what it deliberately does not cover: the edge
router's own side of the links, BGP adjacency state, and the data plane.
