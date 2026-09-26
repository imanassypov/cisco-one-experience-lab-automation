# PseudoCo DC fabric - Nexus as Code pipeline

This pipeline builds the VXLAN EVPN data center fabric `Pseudoco-DC1` on Cisco
Nexus Dashboard 4.2.1.10, from a declarative YAML model held in git.

It automates sections 4, 5 and 6 of the student guide's **NDFC - DC Fabric
Deployment**. Everything the guide has you click through in the Nexus Dashboard
UI, this pipeline declares instead.

## What this builds

PseudoCo's campus and SD-WAN domains already segment traffic into MAIN, PROD
and IOT. The point of this fabric is to carry that same segmentation into the
data center, so a workload is governed by the same business segment as the user
reaching it.

| Guide section | What the pipeline creates |
|---|---|
| 4. Deploy DC VXLAN EVPN Fabric | The `Pseudoco-DC1` fabric object, BGP ASN 65000, two route reflectors, a /31 underlay, and the Resources-tab settings that prepare it for external connectivity. Imports all five switches and sets their roles |
| 5. Configure Interfaces for Endpoints | The DC-Leaf1 / DC-Leaf2 vPC pair, and Port-channel3/4/5 as vPCs 3, 4 and 5 for the MAIN, PROD and IOT servers |
| 6. Configure Overlay - VRFs and Networks | VRFs MAIN, PROD and IOT, their overlay networks with anycast gateways, and the attachment of each port-channel on both leaves |

The resulting fabric:

| Object | Values |
|---|---|
| Switches | DC-Leaf1 `.101` and DC-Leaf2 `.102` (leaf), DC-SPINE-1 `.11` and DC-SPINE-2 `.12` (spine), DC-Service-Leaf `.13` (border), all on `198.18.128.0/24` |
| VRFs | MAIN 50000, PROD 50001, IOT 50002 |
| Networks | MainNetwork1 `10.10.252.1/24`, ProdNetwork1 `10.101.252.1/24`, IOTNetwork1 `10.102.252.1/24` |
| Endpoints | One Linux workload per segment, dual-homed to the leaf pair over its port-channel |

## How it works

[Cisco Nexus as Code](https://netascode.cisco.com/docs/data_models/vxlan/overview/)
(`cisco.nac_dc_vxlan`) is a declarative layer over the `cisco.dcnm` modules.
You describe the fabric you want in YAML under `playbooks/host_vars/`, and the
collection works out which controller API calls produce it. You do not write
API calls, and you do not write per-device configuration.

The model is the source of truth. Re-running the pipeline converges the
controller onto whatever the YAML currently says, so the way to change the
fabric is to change the model and run it again.

## Before you run

Everything runs on the Kali script server, inside the `~/venv` that
`00_scriptserver_bootstrap` builds.

**1. The collections.** This track needs `cisco.nac_dc_vxlan`, `cisco.dcnm`
and `cisco.nxos`, which are newer than the campus track's. A `~/venv` built
before this track existed will not have them. Bring the checkout forward and
re-run the bootstrap, which is what installs them:

```bash
cd ~/cisco-one-experience-lab-automation
git pull
cd ansible-automation/00_scriptserver_bootstrap
ansible-playbook playbooks/01_bootstrap_script_server.yml
```

Confirm you have them before going further:

```bash
ansible-galaxy collection list | grep -E 'nac_dc_vxlan|dcnm|nxos'
```

You want `cisco.nac_dc_vxlan 0.9.0`, `cisco.dcnm 3.13.0` and
`cisco.nxos 10.2.0`.

**2. The External fabric.** In this lab the External fabric and its IOS-XE
edge router are a manual prerequisite, built in Nexus Dashboard before this
pipeline runs. See [Scope](#scope).

**3. The client VPN**, for stage 00 only. That stage is the one thing here
that reaches the switches directly.

## Running it

Run from **this directory**, the one holding `ansible.cfg`. The paths in
`ansible.cfg` that reach the vault and the vars plugin are relative to the
working directory, so running from `playbooks/` breaks authentication.

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/02_data_center/nac_vxlan/ansible
ansible-playbook playbooks/00_discover_dc_switch_serials.yml   # once, first
ansible-playbook playbooks/01_dc_deploy.yml
```

Stage 00 runs first, on its own. It reads a serial number off each switch and
writes the switch half of the data model, so nothing else here has a model to
work with until it has run once.

Two things to expect from a first run, both normal:

- **Stage 02 wipes the running configuration of all five switches** as it
  imports them. This is the guide's "uncheck Preserve Config" step. There is
  no prompt and no flag to disable it. Run this against a pod you are willing
  to rebuild.
- **Stage 02's `inventory` step sits for several minutes with no output.**
  Nexus Dashboard holds one HTTP request open per switch role while it
  discovers and imports the switches behind it. Let it run; interrupting
  leaves the import half done.

### The pipeline

| Playbook | What it does |
|---|---|
| `00_discover_dc_switch_serials.yml` | Reads each switch's serial over SSH and generates the switch model. Read-only against the switches. **Run first.** Not in the orchestrator |
| `01_dc_deploy.yml` | Orchestrator. Imports 02 to 05 in order |
| `02_create.yml` | Creates the whole intent on the controller: fabric, switch import, roles, vPC pair, port-channels, VRFs, networks |
| `03_advanced_settings.yml` | Applies the fabric settings Nexus as Code cannot express. See [Settings Nexus as Code cannot express](#settings-nexus-as-code-cannot-express) |
| `04_recalculate_and_deploy.yml` | The guide's "Recalculate and Deploy". Pushes that intent to the switches, and is the first stage that changes running configuration |
| `05_verify_fabric.yml` | Read-only check of the fabric against the declared model. Writes `evidence/stage05-verification.md` |
| `06_remove.yml` | Destructive prune. Needs `-e dc_remove_confirm=REMOVE_OK` |
| `07_external_fabric.yml` | Creates the External fabric only if it is absent |

The numbering tells you who runs a playbook. Stages 02 to 05 are contiguous
because they are exactly what `01_dc_deploy.yml` imports. Stage 00 sits below
that range because it is the prerequisite you run yourself, once per pod, and
06 and 07 sit above it because they are deliberately outside the orchestrated
run.

Useful overrides:

- `--tags cr_manage_fabric` narrows stage 02 to the fabric object alone, which
  is the guide's "Create a VXLAN Fabric" step on its own
- `-e dc_verify_fail_on_mismatch=false` has stage 05 write its report without
  failing the run

## The data model

| File | Declares |
|---|---|
| `playbooks/host_vars/Pseudoco-DC1/global.nac.yaml` | Fabric name and type, BGP ASN, route reflectors, VNI ranges |
| `underlay.nac.yaml` | Underlay addressing |
| `topology_vpc.nac.yaml` | The vPC peer relationship |
| `topology_switches.nac.yaml` | Switches, roles, serials, port-channels. **Generated by stage 00** |
| `vrfs.nac.yaml` | The three VRFs and the switches they attach to |
| `networks.nac.yaml` | The three networks, their gateways, and the port-channels they attach to |
| `inventory/group_vars/all/dc_switches.yml` | The switch table: names, management addresses, roles, endpoint port-channels |
| `inventory/group_vars/all/dc_advanced_settings.yml` | The fabric settings Nexus as Code has no key for, applied by stage 03 |

The first six files are the Nexus as Code model and follow its schema. The
last two are this repository's own, in plain Ansible `group_vars`, and are read
directly by the playbooks that consume them.

`topology_switches.nac.yaml` is build output and is gitignored. Stage 00
regenerates it from two tracked sources and overwrites it without asking, so
edits to it are lost. To change the fabric's shape, edit
`topology_switches.nac.yaml.example`; to change the switch table, edit
`dc_switches.yml`. Then re-run stage 00.

That also means a `git pull` which changes either source does not reach the
controller until you re-run stage 00.

### Rules for editing the model

- **Give every VRF and network an explicit `vlan_id`.** VRF VLANs come from
  `layer3_vlan_range` 2000-2299 and network VLANs from `layer2_vlan_range`
  2300-2999. The guide's "Propose VLAN" button is safe because it allocates
  one object at a time with a save in between; a batched run asks the
  controller for all of them before committing any, and gets the same answer
  each time. Current assignments are VRFs 2000-2002 and networks 2300-2302.
- **Keep it ASCII.** These values are rendered into device configuration by
  controller-side templates. Plain hyphens, not dashes.
- **No Jinja.** The validate role reads these files off disk, bypassing
  Ansible templating, so `{{ ... }}` arrives at the validator as literal text.
- **Check a key exists before inventing one.** There is no JSON schema in
  play, so a misspelled key is dropped silently rather than rejected. The
  authoritative lists are `roles/validate/files/defaults.yml` and
  `plugins/plugin_utils/data_model_keys.py` inside the collection. The
  collection's own `tests/integration/host_vars/examples/` are on an older
  flat shape and will mislead you.
- **Do not leave a file containing only `vxlan:` behind** when commenting a
  section out; the collection reads that as an instruction to delete it.
- **vPC pairs cannot be edited**, only provisioned and decommissioned.
  Changing the peers means delete and recreate.

Credentials come from the vault-encrypted `Lab Topology/lab_access.yml`
through the repo's vars plugin. Nothing in this tree holds a password.

### Layout

```
ansible.cfg
collections/requirements.yml
inventory/
  static_inventory.yml            one host per fabric, plus the switch group
  group_vars/all/dc_switches.yml  the switch table
  group_vars/all/dc_advanced_settings.yml  the non-model fabric settings
  group_vars/nd/               controller transport and credentials
  group_vars/dc_fabric_switches/  SSH to the switches; stage 00 only
playbooks/
  00_discover_dc_switch_serials.yml ... 07_external_fabric.yml
  host_vars/Pseudoco-DC1/*.nac.yaml   the data model
  templates/
evidence/                         written by stage 05, gitignored
```

`host_vars/` lives under `playbooks/`, not under `inventory/`, which is
unusual. The collection's validate role passes the model path as
`{{ playbook_dir }}/host_vars/{{ inventory_hostname }}` in a task-level
variable with no override, so the model has to sit beside the playbooks.
`group_vars/` is plain Ansible and lives where you would expect.

## Why serial discovery is a separate stage

Nexus as Code identifies a switch by serial number and validates that every
switch in the model has one before anything reaches the controller. The
controller cannot tell you a serial until the switch is already in the fabric,
so the serial has to come from somewhere else first.

Stage 00 gets it from the switches. It SSHes to each management address in
`dc_switches.yml`, runs `nxos_facts`, and reads the serial from
`show version`. Because it never asks the controller, it has no ordering
dependency: nothing has to exist in Nexus Dashboard before it runs.

It then generates `topology_switches.nac.yaml` by copying the `.example` and
substituting, per switch, the serial it just read and the role declared in
`dc_switches.yml`. Everything else in the example is copied verbatim.

The substitution is anchored on each switch's `- name:` line, so the two
source files must spell every switch name the same way. Reordering either file
is harmless; a name that does not match is not. The stage guards against that:
it refuses to write anything unless every switch answered, then reads the file
back and asserts that every serial landed on the right switch and no
placeholder survived. Stage 02 repeats the placeholder check independently,
because the file is on disk and could be edited afterwards.

This is also the only stage that needs the client VPN, since every other stage
here talks solely to the controller API.

## Settings Nexus as Code cannot express

The guide's fabric settings include a Resources tab that `cisco.nac_dc_vxlan`
0.9.0 has no data model key for. Left at their defaults, VRF Lite Deployment
stays `Manual`, which means the controller will never auto-create a VRF-Lite
inter-fabric link - so external connectivity cannot be built at all. Stage 03
closes that gap by writing the settings straight to the controller.

The declared values are in
`inventory/group_vars/all/dc_advanced_settings.yml`. The playbook holds none of
its own, so changing the fabric means editing that file.

| Setting | Declared as | Value |
|---|---|---|
| VRF Lite Deployment | `VRF_LITE_AUTOCONFIG` | `Back2Back&ToExternal` |
| Auto Deploy for Peer | `AUTO_SYMMETRIC_VRF_LITE` | `true` |
| Auto Allocation of Unique IP on VRF Extension | `AUTO_UNIQUE_VRF_LITE_IP_PREFIX` | `true` |
| VRF Lite Subnet IP Range | `DCI_SUBNET_RANGE` | `192.168.252.0/24` |
| VRF Lite Subnet Mask | `DCI_SUBNET_TARGET_MASK` | `30` |
| License Tier | `licenseTier` | `premier` |
| Telemetry | `telemetryCollection` | `false` |
| Location | `location` | `37.3382, -121.8863` (San Jose, California, US) |

Two dictionaries, because Nexus Dashboard keeps these in two places. The first
five are fabric **nvPairs** - the same store Nexus as Code writes the rest of
the fabric into - and are applied with `cisco.dcnm.dcnm_fabric`. The last three
are not nvPairs at all; they are properties of the Nexus Dashboard fabric
object at `/api/v1/manage/fabrics/Pseudoco-DC1`, which `dcnm_fabric` cannot
reach, so stage 03 does a read-modify-write on that object instead. A setting
in the wrong dictionary fails the stage by name rather than being silently
ignored.

**Location is coordinates, because Nexus Dashboard has no field for the place
name.** There is no city, country or address key on the fabric object, in its
`management` sub-object, or among the fabric's nvPairs. The UI's location
picker geocodes what you type and keeps only the two numbers, then drops a pin
on the fabric map. So "San Jose" survives only as a comment in the data model,
which is why that comment is there. Both coordinates have to be given
together: the stage combines non-recursively, so a partial `location` would
replace the whole object and leave the other coordinate at zero.

Three things worth knowing:

- **It cannot revert what stage 02 wrote.** On Nexus Dashboard 4.x,
  `dcnm_fabric` rebuilds the update payload from the controller's own nvPairs
  before overlaying the declared changes, because a partial fabric update is
  rejected. Everything Nexus as Code set is carried through untouched.
- **It runs before deploy, not after.** These are fabric parameters, which are
  inputs to the configuration the controller generates. Applied after stage
  04, they would be correct on the controller and absent from the switches
  until the next deploy.
- **A second run is a no-op.** Both halves compare before they write, so
  re-running reports `changed=0`. `DEPLOY` is false throughout and nothing here
  touches a switch.

**"Add Switches without Reload" is deliberately not here.** It is the
`GRFIELD_DEBUG_FLAG` nvPair, and Nexus as Code does model it, as
`vxlan.global.ibgp.greenfield_cleanup` in `global.nac.yaml`. Two files setting
one nvPair is a drift bug waiting to happen; this stage carries only what the
model cannot express.

## What the verification stage proves

`05_verify_fabric.yml` compares the declared model against what the controller
actually holds, using the Nexus Dashboard API only. It is read-only and needs
no switch access, so it works with the VPN down and can be re-run freely. It
writes `evidence/stage05-verification.md` and fails on a mismatch.

Eleven checks: five switches, three VRFs, three networks.

- **Switch** - present in the fabric inventory at its declared management
  address, holding its declared role.
- **VRF** - exists with the declared VNI, attached to every switch in its
  `vrf_attach_group`, and every attachment `DEPLOYED`.
- **Network** - exists in the declared VRF with the declared anycast gateway,
  each declared port-channel attached on every switch it was declared on, and
  every attachment `DEPLOYED`.

Reading the report:

- **`DC-Service-Leaf` under "Not attached" is expected.** The controller lists
  every switch that could carry a VRF or network and marks the ones it has not
  attached. The border leaf is deliberately outside the attach groups, because
  attaching it is the VRF-Lite step in [Scope](#scope). Those rows are
  reported, not judged.
- A name under **"Switches missing"** or **"Attachments missing"** is a real
  fault: something declared did not attach.
- An attached switch in **`PENDING`** means the intent exists on the
  controller but was never pushed. Re-run `04_recalculate_and_deploy.yml`.
- The report is regenerated on each run that reaches the end. If a run fails
  early, the previous report is left in place, so check its `Generated`
  timestamp before trusting it.

## Scope

The pipeline carries all of the guide's sections 4, 5 and 6: everything
`cisco.nac_dc_vxlan` 0.9.0 can express, plus the fabric settings it cannot,
which stage 03 supplies. External connectivity, sections 7 and 8, stays
manual.

**The External fabric and the edge router** `DC-SITE11-CEDGE8Kv`
(`198.18.133.14`) are built by hand in Nexus Dashboard before the pipeline
runs: the fabric in Monitor Mode, the router discovered into it as an Edge
Router. The model has no key for Monitor Mode, and `dcnm_inventory` has no
concept of a non-NX-OS device, so neither can be declared.
`07_external_fabric.yml` will create the fabric object if it is genuinely
missing, but it refuses to touch one that already exists.

**The VRF-Lite extensions themselves** - MAIN, PROD and IOT reaching out of
DC-Service-Leaf to the edge router - are still manual. The fabric-level
settings they need are automated, by stage 03; the per-VRF attachments are
not. The VRF templates emit one key per attachment, an IP address, with no
`vrf_lite` key anywhere, so the extension, its sub-interface and its dot1q tag
cannot be declared in the model.

`cisco.dcnm` underneath does support them, via `attach[].vrf_lite[]`. One
thing to design around when this is written: the create role runs `dcnm_vrf`
with `state: replaced`, so a create run will detach whatever a VRF-Lite stage
attached, meaning that stage has to run after create on every pass.

When VRF-Lite lands, extend stage 05 to assert the extension on
DC-Service-Leaf, so a create-without-VRF-Lite run is caught rather than
silently reverting external connectivity.

## Versions

All seven pins in `collections/requirements.yml` must also appear, at the same
versions, in the bootstrap's
`roles/script_server_bootstrap/files/requirements.yml`, which additionally
carries the campus collections. The bootstrap file is the one that actually
gets installed on a fresh pod, so raising a pin here alone has no effect. The
four supporting collections are pinned alongside the three Cisco ones so the
dependency resolver cannot substitute its own choices.

Nexus Dashboard 4.2.1 support landed in `cisco.dcnm` 3.12.1, and
`cisco.nac_dc_vxlan` 0.9.0 requires `cisco.dcnm` 3.13.0 or newer. The
collection reads and validates the model in Python, so its Python
dependencies in `ansible-automation/requirements.txt` are hard runtime
requirements, not conveniences.
