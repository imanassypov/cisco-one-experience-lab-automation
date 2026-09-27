# PseudoCo DC fabric - Nexus as Code pipeline

This pipeline builds the VXLAN EVPN data center fabric `Pseudoco-DC1` on Cisco
Nexus Dashboard 4.2.1.10, from a declarative YAML model held in git.

It automates sections 4 through 8 of the student guide's **NDFC - DC Fabric
Deployment**. Everything the guide has you click through in the Nexus Dashboard
UI, this pipeline declares instead. The one thing it does not carry is the edge
router's own side of the VRF-Lite handoff, which Nexus Dashboard cannot write -
see [Scope](#scope).

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
| 7. Create an External Fabric | The `External` fabric, ASN 65531, in Fabric Monitor Mode, with the IOS-XE edge router `DC-SITE11-CEDGE8Kv` added to it as an Edge Router |
| 8. Create VRF-Lite Connections to External | The three VRF-Lite extensions out of DC-Service-Leaf on `Ethernet1/8`, one per VRF, each with its dot1q tag, sub-interface address and BGP neighbour. The router's side of those links is pre-built by the pod and stays outside the pipeline |

The resulting fabric:

| Object | Values |
|---|---|
| Switches | DC-Leaf1 `.101` and DC-Leaf2 `.102` (leaf), DC-SPINE-1 `.11` and DC-SPINE-2 `.12` (spine), DC-Service-Leaf `.13` (border), all on `198.18.128.0/24` |
| VRFs | MAIN 50000, PROD 50001, IOT 50002 |
| Networks | MainNetwork1 `10.10.252.1/24`, ProdNetwork1 `10.101.252.1/24`, IOTNetwork1 `10.102.252.1/24` |
| Endpoints | One Linux workload per segment, dual-homed to the leaf pair over its port-channel |

## How it works

[Cisco Nexus as Code](https://netascode.cisco.com/docs/data_models/vxlan/overview/)
(`cisco.nac_dc_vxlan`) is a **declarative layer over the `cisco.dcnm`
modules**. It holds no transport of its own. It reads a YAML data model off
disk, works out which `cisco.dcnm` module calls produce the fabric that model
describes, and drives those modules itself. You do not write API calls, and
you do not write per-device configuration.

The whole chain, and the only part of this README worth memorising:

```
playbooks/host_vars/Pseudoco-DC1/*.nac.yaml    the declarative data model
  -> cisco.nac_dc_vxlan.validate               reads the model off disk, checks it
  -> cisco.nac_dc_vxlan.dtc.create | dtc.deploy  renders module calls
  -> cisco.dcnm.dcnm_fabric | dcnm_inventory | dcnm_interface
     | dcnm_vrf | dcnm_network                 one module per controller object
  -> Nexus Dashboard REST over httpapi         ndfc.corp.pseudoco.com:443
  -> DC-Leaf1/2, DC-SPINE-1/2, DC-Service-Leaf  198.18.128.101-102, .11-.13
```

Two consequences of that shape matter more than any syntax:

- **The model is the source of truth.** Re-running the pipeline converges the
  controller onto whatever the YAML currently says, so the way to change the
  fabric is to change the model and run it again.
- **Only the last hop touches a switch.** Everything from the model down to
  Nexus Dashboard is *intent*. Stages 02 to 05 write intent; stage 06 is the
  one stage that changes running configuration.

### The three roles this pipeline uses

The collection ships more roles than this. A stage here only ever calls these
three, and the split between them is the pipeline's structure.

| Role | Called by | What it does |
|---|---|---|
| `cisco.nac_dc_vxlan.validate` | 02 and 06, as the first role of the play | Reads every `*.nac.yaml` out of `playbooks/host_vars/<fabric>/` and checks it against the collection's schema and rule set. Touches neither controller nor switch. A model error fails here instead of half way through a build |
| `cisco.nac_dc_vxlan.dtc.create` | 02 | Builds the whole intent on the controller in 21 steps: fabric object, switch import and roles, vPC pair, port-channels, VRFs, networks, attachments. Changes nothing on a switch, with one exception - importing a switch is itself a write, and the import is greenfield |
| `cisco.nac_dc_vxlan.dtc.deploy` | 06 | The UI's Recalculate and Deploy. The only thing in this pipeline that changes running configuration |

`validate` runs ahead of the other two in the same play rather than as a
separate stage, because they read the same files and neither notices a key
the schema would have rejected.

Stages 03, 04, 05 and 07 call **no** Nexus as Code role. They use `cisco.dcnm`
modules and raw REST, because what they declare has no key in the data model -
see [Settings Nexus as Code cannot
express](#settings-nexus-as-code-cannot-express) and [Scope](#scope).

### The collection pins, and why each one is there

`collections/requirements.yml` pins seven collections. Three are Cisco's, and
each is pinned for a different reason.

| Collection | Pin | Why |
|---|---|---|
| `cisco.nac_dc_vxlan` | 0.9.0 | The declarative layer. It renders `cisco.dcnm` module calls from the `host_vars` data model |
| `cisco.dcnm` | 3.13.0 | The modules underneath. **The floor matters**: Nexus Dashboard 4.2.1 support landed in `cisco.dcnm` 3.12.1 and 3.13.0 adds 4.3.1, and `cisco.nac_dc_vxlan` 0.9.0 declares `cisco.dcnm` >= 3.13.0 as a hard dependency. Do not pin it lower |
| `cisco.nxos` | 10.2.0 | Used by **one stage only** - `00_discover_dc_switch_serials.yml`, which SSHes to the switches to read their serial numbers. Every other stage talks to Nexus Dashboard over `httpapi` and needs none of it |

The four supporting collections - `ansible.netcommon` 7.1.0, `ansible.utils`
5.1.2, `ansible.posix` 2.0.0 and `community.general` 10.1.0 - match the
versions in the upstream `netascode/ansible-dc-vxlan-example` requirements and
are pinned alongside the Cisco three so the dependency resolver cannot
substitute its own choices. All four declare `requires_ansible ">=2.15.0"`, so
they are compatible with the `ansible-core` 2.17.14 pinned in
`ansible-automation/requirements.txt`.

Raising a pin here alone has no effect on a pod. See [Versions](#versions).

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

**2. The IOS-XE edge router must be reachable and its vault entry present.**
Stage 04 builds the External fabric *and* adds `DC-SITE11-CEDGE8Kv`
(`198.18.133.14`) to it, logging in with the `DC-SITE11-CEDGE8Kv` entry in
`Lab Topology/lab_access.yml`. Nothing else has to be done by hand, but the
router does have to answer SSH on the pod. See [Scope](#scope).

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
| `01_dc_deploy.yml` | Orchestrator. Imports 02 to 07 in order |
| `02_create_dc_fabric.yml` | Creates the whole intent on the controller: fabric, switch import, roles, vPC pair, port-channels, VRFs, networks |
| `03_fabric_advanced_settings.yml` | Applies the settings Nexus as Code cannot express. See [Settings Nexus as Code cannot express](#settings-nexus-as-code-cannot-express) |
| `04_external_fabric.yml` | Creates the External connectivity fabric in Monitor Mode and adds the IOS-XE edge router to it |
| `05_vrf_lite.yml` | Attaches the three VRF-Lite extensions on the border leaf, from `inventory/group_vars/all/dc_vrf_lite.yml`. Stages intent only; waits for the CDP correlation - see [The wait that replaced the second deploy](#the-wait-that-replaced-the-second-deploy) |
| `06_recalculate_and_deploy.yml` | The guide's "Recalculate and Deploy". Pushes everything stages 02 to 05 staged, and is the **only** stage that changes running configuration |
| `07_verify_fabric.yml` | Read-only check of the fabric against the declared model. Writes `evidence/stage07-verification.md` |
| `08_remove.yml` | Destructive prune. Needs `-e dc_remove_confirm=REMOVE_OK` |

The numbering tells you who runs a playbook. Stages 02 to 07 are contiguous
because they are exactly what `01_dc_deploy.yml` imports. Stage 00 sits below
that range because it is the prerequisite you run yourself, once per pod, and
08 sits above it because it is deliberately outside the orchestrated run.

Stages 03, 04 and 05 all sit ahead of the deploy, for the same reason. Stage
03 changes fabric parameters, which are inputs to the configuration the
controller generates; stage 04 creates the fabric on the far side of the
VRF-Lite handoff, which is what lets the controller resolve that handoff at
all; stage 05 attaches the extensions that ride it. Any of the three run after
stage 06 would leave the controller correct and the switches a deploy behind.

That ordering is what collapses the guide's deploy-edit-deploy sequence into
one push. Because the extensions are already staged when stage 06 runs, a
single Recalculate and Deploy carries the parent interface, the three dot1q
sub-interfaces and their BGP neighbours together.

Useful overrides:

- `--tags cr_manage_fabric` narrows stage 02 to the fabric object alone, which
  is the guide's "Create a VXLAN Fabric" step on its own
- `-e dc_vrf_lite_retries=12` doubles stage 05's wait for the CDP correlation
- `-e dc_verify_fail_on_mismatch=false` has stage 07 write its report without
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
| `inventory/group_vars/all/dc_external_settings.yml` | The whole External fabric: ASN and Monitor Mode, applied by stage 04 |
| `inventory/group_vars/all/dc_vrf_lite.yml` | The three VRF-Lite extensions out of the border leaf, applied by stage 05 |
| `inventory/group_vars/nd/nd.yml`, `nd/connection.yml` | The controller: `httpapi` transport, vault-sourced credentials, the two 1000s timeouts, and the remove-role delete flags |

**The definitions live in two distinct places, and the boundary is the single
most useful thing to understand here.**

```
playbooks/host_vars/Pseudoco-DC1/*.nac.yaml   (a) the Nexus as Code data model
inventory/group_vars/all/dc_*.yml             (b) everything the model cannot say
inventory/group_vars/nd/*.yml                     the controller connection
```

**(a) is the declarative model and the collection owns its schema.** The
validate role reads these six files off disk and checks them; `dtc.create` and
`dtc.deploy` turn what survives into `cisco.dcnm` module calls. No API name,
no module name and no controller field appears in any of them.

**(b) is plain Ansible variables and the playbooks own them.** Nothing inside
the collection reads them. They exist because `cisco.nac_dc_vxlan` 0.9.0 has
no key for what they declare, so stages 03, 04 and 05 read them and call
`dcnm_fabric`, `dcnm_rest` and `dcnm_vrf` directly. The values in (b) are
therefore spelled the way the **controller** spells them - `VRF_LITE_AUTOCONFIG`,
`IS_READ_ONLY`, `licenseTier` - because that is what goes on the wire.

One consequence worth stating plainly: a key in the wrong half is not a style
problem. A controller nvPair name put in (a) is rejected by the validator; a
data-model key put in (b) is read by nobody at all.

### What (a) looks like

Every file in (a) opens with `vxlan:` and nests under it. A VRF and the group
that attaches it, from `vrfs.nac.yaml`:

```yaml
vxlan:
  overlay:
    vrfs:
      - name: PROD
        vrf_id: 50001          # the L3VNI. From layer3_vni_range in global.nac.yaml
        vlan_id: 2001          # PINNED, and not optional - see the traps below
        vrf_vlan_name: PROD
        vrf_intf_desc: PROD
        vrf_description: PROD
        vrf_attach_group: dc_leaves   # names a group declared lower in the same file

    vrf_attach_groups:
      - name: dc_leaves
        switches:
          - hostname: DC-Leaf1   # DC-Service-Leaf is deliberately absent
          - hostname: DC-Leaf2
```

That attach group is the model's whole vocabulary for an attachment: a
hostname, and nothing else. It is the reason VRF-Lite needs a file in (b).

A network, from `networks.nac.yaml`, where an attach group can also name ports:

```yaml
vxlan:
  overlay:
    networks:
      - name: ProdNetwork1
        vrf_name: PROD         # binds the network to the VRF above
        net_id: 30001          # the L2VNI
        vlan_id: 2301          # pinned for the same reason as the VRF
        is_l2_only: false      # the model's spelling of "Network Mode: Layer 3"
        gw_ip_address: "10.101.252.1/24"   # the anycast gateway
        network_attach_group: prod_vpc4

    network_attach_groups:
      - name: prod_vpc4
        switches:
          - hostname: DC-Leaf1
            ports:
              - Port-channel4   # the same port-channel on BOTH leaves
          - hostname: DC-Leaf2
            ports:
              - Port-channel4
```

One stanza there is the network, its Layer 3 mode, its anycast gateway and its
attachment - the three separate UI screens of guide section 6.

### What (b) looks like

`dc_switches.yml` is the switch table, and it is the input to two different
things: stage 00 substitutes each `role` into the generated model, and stage 00
also turns the table into an SSH inventory group at run time with `add_host`.

```yaml
dc_fabric_name: Pseudoco-DC1

dc_switches:
  - name: DC-Leaf1                          # must match the .example exactly
    management_ipv4_address: 198.18.128.101
    role: leaf
    interfaces:
      - name: Port-channel4
        mode: access
        vpc_id: 4
        description: "PROD server - vPC4"   # ASCII only - an em dash here 500s
        members:
          - Ethernet1/4

  - name: DC-Service-Leaf
    management_ipv4_address: 198.18.128.13
    role: border                            # the only border switch in the fabric
    interfaces: []
```

`dc_advanced_settings.yml` is the other shape in (b): controller nvPairs,
written verbatim. These are the guide's Resources-tab settings, and without
them external connectivity cannot be built at all.

```yaml
dc_advanced_fabric_settings:             # nvPairs, applied with dcnm_fabric
  VRF_LITE_AUTOCONFIG: "Back2Back&ToExternal"   # default Manual creates no IFC
  AUTO_SYMMETRIC_VRF_LITE: true
  AUTO_UNIQUE_VRF_LITE_IP_PREFIX: true
  DCI_SUBNET_RANGE: 192.168.252.0/24
  DCI_SUBNET_TARGET_MASK: 30

dc_advanced_nd_fabric_settings:          # NOT nvPairs, applied with dcnm_rest
  licenseTier: premier
  telemetryCollection: false
  location:                              # both keys, or the other reads zero
    latitude: 37.3382
    longitude: -121.8863
```

And `dc_vrf_lite.yml` is what the data model has no keys for at all - the
extension itself:

```yaml
dc_vrf_lite_border_leaf: DC-Service-Leaf
dc_vrf_lite_interface: Ethernet1/8       # detected over CDP, declared for determinism

dc_vrf_lite_extensions:
  - vrf: PROD
    peer_vrf: PROD                       # the VRF name on the router side
    dot1q: "2"                           # a string: dcnm_vrf declares type: str
    ipv4_addr: 192.168.252.5/30          # the leaf's sub-interface
    neighbor_ipv4: 192.168.252.6         # the router's side, pre-built by the pod
```

`vrf_id` and `vlan_id` are deliberately **not** restated there. Stage 05 reads
them back out of `vrfs.nac.yaml` at run time, so the two files cannot disagree.

The External fabric has no Nexus as Code model either, which is why it appears
only in (b). The collection's create role cannot build it: the role
always runs a config-save after its inventory step, and on a fabric with no
switches the controller returns HTTP 500 `Fabric External cannot be deployed
without any switches`. The fabric also holds no VRFs, networks or interfaces,
so there is nothing for the collection to express. Stage 04 creates it with
`cisco.dcnm.dcnm_fabric` and adds the edge router over REST, both from
`dc_external_settings.yml`.

`topology_switches.nac.yaml` is build output and is gitignored. Stage 00
regenerates it from two tracked sources and overwrites it without asking, so
edits to it are lost. To change the fabric's shape, edit
`topology_switches.nac.yaml.example`; to change the switch table, edit
`dc_switches.yml`. Then re-run stage 00.

That also means a `git pull` which changes either source does not reach the
controller until you re-run stage 00.

### Four things in these files that are not obvious from reading them

Each of these is the kind of decision that looks arbitrary until it is
explained, and each is already commented in the file it belongs to.

- **`vlan_id` is pinned on every VRF and every network, and leaving it out
  breaks the run.** Omit it and `cisco.dcnm` asks the controller's resource
  manager for the next free VLAN - which answers honestly and reserves
  nothing. The module asks once per object inside the loop, with nothing
  committed in between, so all three VRFs are handed 2000, the first
  attachment wins, and the rest fail with `Entered VRF VLAN id 2000 is
  already in use`. The guide's Propose VLAN button is safe only because a
  person clicks Create between proposals.
- **Serial numbers are generated, not tracked.** Nexus as Code identifies a
  switch by serial and validates that every switch has one before anything
  reaches the controller, but the controller cannot tell you a serial until
  the switch is already in the fabric. Serials are also pod hardware, so
  committing them would make every other checkout wrong. Stage 00 reads them
  over SSH instead - see [Why serial discovery is a separate
  stage](#why-serial-discovery-is-a-separate-stage).
- **Every switch is erased on import, and no setting changes that.**
  `preserve_config: false` is hardcoded in the create role's inventory
  template - not exposed in the data model and not reachable by a flag. That
  matches the guide, which has you uncheck Preserve Config, but it means a
  first run wipes all five switches with no prompt.
- **`DC-Service-Leaf` is deliberately absent from `vrf_attach_groups`.** An
  entry there can name a switch and nothing else. Attaching the border leaf
  from the model would give it the three VRFs *without* the VRF-Lite
  extensions, which is worse than not attaching it - the VRFs would be
  present and unreachable from outside. So the model leaves it out and stage
  05 attaches it properly, with the extension, using `dcnm_vrf` directly.
  Note the consequence: stage 02 runs `dcnm_vrf` with `state: replaced`
  against that model, so **every create run detaches the extensions** and
  stage 05 has to run after it on every pass.

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
  group_vars/all/dc_external_settings.yml  the External fabric
  group_vars/all/dc_vrf_lite.yml  the VRF-Lite extensions
  group_vars/nd/               controller transport and credentials
  group_vars/dc_fabric_switches/  SSH to the switches; stage 00 only
playbooks/
  00_discover_dc_switch_serials.yml ... 08_remove.yml
  host_vars/Pseudoco-DC1/*.nac.yaml   the data model
  templates/stage07-verification.md.j2
evidence/                         written by stage 07, gitignored
```

`host_vars/` lives under `playbooks/`, not under `inventory/`, which is
unusual. The collection's validate role passes the model path as
`{{ playbook_dir }}/host_vars/{{ inventory_hostname }}` in a task-level
variable with no override, so the model has to sit beside the playbooks.
`group_vars/` is plain Ansible and lives where you would expect.

## How it comes together: PROD, end to end

Follow one object through every layer. `PROD` is the useful one, because it is
the only VRF that appears in both halves of the definition.

**1. Declared.** Seven lines in `playbooks/host_vars/Pseudoco-DC1/vrfs.nac.yaml`
plus one hostname in `vrf_attach_groups`, quoted above. Nothing else in the
repository restates `50001` or `2001`.

**2. Validated.** Stage 02's first role, `cisco.nac_dc_vxlan.validate`, reads
the file off disk - not through Ansible's templating, which is why no `{{ }}`
can appear in it - and checks `vrf_id` against `layer3_vni_range` from
`global.nac.yaml`, `vlan_id` against the collection's `layer3_vlan_range`, and
`vrf_attach_group` against the groups declared in the same file. Nothing has
been contacted yet.

**3. Rendered into a module call.** Stage 02's second role,
`cisco.nac_dc_vxlan.dtc.create`, reaches its `vrfs` step and calls
`cisco.dcnm.dcnm_vrf` with `state: replaced` and a config built from the
model: the VRF, its id, its VLAN, and one `attach` entry per hostname in
`dc_leaves`. `replaced` is what makes the model authoritative - and what
detaches anything the model does not list.

**4. On the controller.** `dcnm_vrf` POSTs to
`.../top-down/fabrics/Pseudoco-DC1/vrfs` and its attachments endpoint over the
`httpapi` connection from `group_vars/nd/connection.yml`. PROD now exists in
Nexus Dashboard, attached to DC-Leaf1 and DC-Leaf2 - and `PENDING`, because
nothing has been pushed.

**5. Extended.** Stage 05 reads `dc_vrf_lite.yml`, reads `vrf_id` and
`vlan_id` back out of `vrfs.nac.yaml` so it cannot contradict step 1, and
calls `dcnm_vrf` again - this time with `state: merged`, naming only
DC-Service-Leaf, and carrying the `attach[].vrf_lite[]` structure the data
model has no keys for: `Ethernet1/8`, dot1q `2`, `192.168.252.5/30`,
neighbour `192.168.252.6`. `merged` is what leaves the two leaf attachments
from step 4 alone. Still nothing on a switch.

**6. Deployed.** Stage 06 runs `cisco.nac_dc_vxlan.dtc.deploy`, which asks the
controller which switches have pending configuration and deploys them. PROD's
VRF and SVIs land on the leaves; on the border leaf the same push carries the
parent `Ethernet1/8`, the `.2` sub-interface and the eBGP neighbour, because
step 5 staged them before this ran. Every attachment flips `PENDING` ->
`DEPLOYED`.

**7. Verified.** Stage 07 reads `vrfs.nac.yaml` again - the same file, not a
copy - and compares it against the controller: PROD exists with VNI 50001, is
attached to both declared leaves, every attachment reads `DEPLOYED`, and the
border leaf's attachment carries the declared interface, dot1q tag and
neighbour address in its `extensionValues`. Three of the report's fourteen
checks are PROD - the VRF row, the `ProdNetwork1` row and the VRF-Lite row -
and all three land in `evidence/stage07-verification.md`.

Change `vrf_id` in step 1 and re-run: steps 2 through 7 all follow, and no
other file needs touching. That is the whole argument for writing the fabric
down.

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
  06, they would be correct on the controller and absent from the switches
  until the next deploy.
- **A second run is a no-op.** Both halves compare before they write, so
  re-running reports `changed=0`. `DEPLOY` is false throughout and nothing here
  touches a switch.

**"Add Switches without Reload" is deliberately not here.** It is the
`GRFIELD_DEBUG_FLAG` nvPair, and Nexus as Code does model it, as
`vxlan.global.ibgp.greenfield_cleanup` in `global.nac.yaml`. Two files setting
one nvPair is a drift bug waiting to happen; this stage carries only what the
model cannot express.

### The two VRF-Lite settings, as Cisco defines them

These two are the reason stage 03 exists, and the first of them is what stage
05 depends on and stage 06 pushes. Both are on the fabric's Resources tab.

**`VRF_LITE_AUTOCONFIG: "Back2Back&ToExternal"`** is the UI's **VRF Lite
Deployment** field. Cisco's Nexus Dashboard 4.2.1 fabric settings reference
defines it as: *"Specify the VRF Lite method for extending inter fabric
connections. The VRF Lite Subnet IP Range field specifies resources reserved
for IP address used for VRF Lite when VRF Lite IFCs are auto-created. If you
select Back2Back&ToExternal, then VRF Lite IFCs are auto-created."*
([Editing Data Center VXLAN Fabric Settings, Release 4.2.1](https://www.cisco.com/c/en/us/td/docs/dcn/nd/4x/articles-421/editing-fabric-settings-data-center-vxlan.html))
The VRF Lite article is more specific about what gets connected to what:
*"Use this option to automatically configure VRF Lite IFCs between a border
switch and the edge or core switches in external fabric or between
back-to-back border switches in VXLAN EVPN fabric."*
([NDFC - VRF Lite](https://www.cisco.com/c/en/us/td/docs/dcn/ndfc/1221/articles/ndfc-vrf-lite/vrf-lite.html))
The default is `Manual`, under which no IFC is ever auto-created and external
connectivity cannot be built at all.

The same article bounds which devices react to it: *"Autoconfiguration is
supported for the following cases: Border role in the VXLAN fabric and Edge
Router role in the connected external fabric device; Border Gateway role in
the VXLAN fabric and Edge Router role in the connected external fabric
device; Border role to another Border role directly."* In `Pseudoco-DC1`
exactly one switch holds the `border` role - `DC-Service-Leaf` - and after
stage 04 exactly one device holds `edgeRouter` - `DC-SITE11-CEDGE8Kv`. That
pairing is the whole scope of this setting here.

**`AUTO_SYMMETRIC_VRF_LITE: true`** is the UI's **Auto Deploy for Peer**
checkbox. Cisco: *"This check box is applicable for VRF Lite deployment. When
you select this checkbox, auto-created VRF Lite IFCs will have the Auto
Generate Configuration for Peer field in the VRF Lite tab set. ... This
configuration only affects the new auto-created IFCs and does not affect the
existing IFCs."* It therefore writes nothing itself - it is a default stamped
onto each IFC at the moment that IFC is created, and Cisco is explicit that
changing it afterwards does not reach an IFC that already exists. The field it
presets is defined as *"Specifies to auto generate a VRF-Lite configuration
for managed NX-OS neighbor devices. This knob autoconfigures the neighbor VRF
on the neighboring managed device."* The `cisco.dcnm` nvPair name maps to that
checkbox, which the CiscoDevNet
[NDFC Terraform provider](https://registry.terraform.io/providers/CiscoDevNet/ndfc/latest/docs/data-sources/fabric)
states directly: `auto_symmetric_vrf_lite` is *"Whether to auto generate VRF
LITE sub-interface and BGP peering configuration on managed neighbor devices.
If set, auto created VRF Lite IFC links will have Auto Deploy for Peer
enabled."*

**On this pod, `AUTO_SYMMETRIC_VRF_LITE` has no reachable effect.** It is
declared because the guide declares it and this file mirrors the guide's
fabric settings, but two independent constraints stop it at the border leaf:

- **The peer is not NX-OS.** `DC-SITE11-CEDGE8Kv` is an IOS-XE Catalyst
  8000V. Cisco's guidelines for automatic VRF Lite (IFC) configuration state
  *"Auto IFC is supported on Cisco Nexus devices only"* and *"If the device in
  the External fabric is non-Nexus, you must create IFC manually."* The
  student guide prints the same warning beside the checkbox: *"Nexus Dashboard
  can automate configuration on the external device if it is NXOS or ASR9k."*
- **The External fabric is in Monitor Mode.** Cisco: *"To deploy
  configurations in the external fabric, you must uncheck the Fabric Monitor
  Mode check box in the external fabric settings. When an external fabric is
  set to Fabric Monitor Mode Only, you cannot deploy configurations on the
  switches."* `dc_external_settings.yml` sets `IS_READ_ONLY: true` on purpose,
  because the lab's edge router is pre-configured and must not be overwritten.

So VRF-Lite automation in this lab stops at `DC-Service-Leaf`. The far side of
the handoff was configured by hand before the pod was handed over, which is
also why the guide tells you to force the addresses and encapsulation on the
border side rather than let the controller allocate both ends.

## The wait that replaced the second deploy

**The pipeline no longer deploys twice. It waits once, inside stage 05.** This
section is here because the reason for the old second run is still true, still
the thing that goes wrong if the wait is removed, and cost real time to find:
**Nexus Dashboard correlates the CDP adjacency between the border leaf and the
edge router asynchronously**, so anything that depends on that adjacency and
fires seconds after stage 04 is too early.

Before stage 05 existed, that showed up as a deploy. Running the old
`05_recalculate_and_deploy.yml` straight after `04_external_fabric.yml`
reported `0/5` switches to deploy, and a second run a minute later picked up
exactly one switch, `DC-Service-Leaf`, and deployed it in a few seconds.
Nothing drifted in between and nobody touched a switch - the controller had
simply learned something it did not know on the previous pass.

It now shows up as a pause. `05_vrf_lite.yml` cannot attach a VRF-Lite
extension until the inter-fabric link that `VRF_LITE_AUTOCONFIG` builds
exists, and the controller builds that only once it has the adjacency. So the
stage retries the `dcnm_vrf` call with `until`/`retries` - **6 attempts, 20
seconds apart, up to two minutes** - instead of failing, and raises with
`-e dc_vrf_lite_retries=12`. A stage 05 that sits with no output is normal.
Because the wait happens while intent is being *staged* rather than deployed,
stage 06 finds the work already there and one Recalculate and Deploy is
enough.

The rest of this section is the evidence and the Cisco framing, which have not
changed.

The original second deploy was not a workaround for a defect. It was the
guide's own first step of section 8, "Create VRF-Lite Connections to
External":

> To synchronize **Pseudoco-DC1** within Nexus Dashboard with the new External
> fabric, in the top fabric-level **Actions** drop down, click **Recalculate
> and Deploy**. This synchronization aids in performing some automatic
> configuration and deployment from the **Pseudoco-DC1** VXLAN EVPN fabric to
> the External fabric external router by staging the IP addresses for use on
> the sub-interfaces between your border leaf and external router.

Stage 06 *is* that click. Section 7 sets up the precondition it depends on -
the guide's note there says the External fabric exists *"so that ND can detect
the physical connection using CDP and can make the configuration in the border
switch"* - and section 8 opens by saying *"Your border leaf and external
router must detect each other so the provisioning of the sub-interface (with
IP address) and BGP configuration can occur."*

That detection is the part that takes time. Adding the router to the External
fabric returns HTTP 202 with an empty body; the controller then onboards it
and correlates its CDP adjacency with `DC-Service-Leaf` afterwards, on its own
schedule. Anything that asks "what needs deploying?" before the controller has
an answer gets an honest nothing and exits successfully.

Observed on this pod, 2026-09-27, before stage 05 existed, with nothing run in
between the two deploys:

```
run 1   DEPLOY [Pseudoco-DC1] get_deployable_switches -> ok (changed=0/5)
        DEPLOY [Pseudoco-DC1] all -> skipped (no switches need deployment)

run 2   DEPLOY [Pseudoco-DC1] get_deployable_switches -> ok (changed=1/5)
        DEPLOY [Pseudoco-DC1] switch_deploy (1 switches)
          POST .../fabrics/Pseudoco-DC1/config-deploy/955T6I5X2D4
          {'status': 'Configuration deployment completed for [955T6I5X2D4].'}
        DEPLOY [Pseudoco-DC1] check_sync -> ok (in_sync=True)
```

`955T6I5X2D4` is `DC-Service-Leaf`. That it is the border leaf and nothing
else is the expected outcome, not a coincidence: it is the only switch in this
fabric that `VRF_LITE_AUTOCONFIG` can act on, for the reason quoted above.

The habit worth keeping from all of this generalises past one stage:

- **"No changes" is a statement about one instant, not proof the fabric is
  finished.** An idempotent pipeline reporting nothing pending means only that
  the controller had nothing pending *when it was asked*. The authoritative
  signals here are `check_sync` reporting `in_sync=True` after a run that
  actually deployed something, and a clean `07_verify_fabric.yml`.
- **Something appearing on a re-run is not drift.** Nobody touched the switch.
  The controller learned something it did not know on the previous pass.
- **Wait for the precondition, do not re-run until it happens.** A retry loop
  around the call that needs the adjacency says in code what the old advice
  said in prose, and it is the difference between a pipeline that finishes and
  one with a manual step in the middle.

## What the verification stage proves

`07_verify_fabric.yml` compares the declared model against what the controller
actually holds, using the Nexus Dashboard API only. It is read-only and needs
no switch access, so it works with the VPN down and can be re-run freely. It
writes `evidence/stage07-verification.md` and fails on a mismatch.

Fourteen checks: five switches, three VRFs, three networks, three VRF-Lite
extensions.

- **Switch** - present in the fabric inventory at its declared management
  address, holding its declared role.
- **VRF** - exists with the declared VNI, attached to every switch in its
  `vrf_attach_group`, and every attachment `DEPLOYED`.
- **Network** - exists in the declared VRF with the declared anycast gateway,
  each declared port-channel attached on every switch it was declared on, and
  every attachment `DEPLOYED`.
- **VRF-Lite extension** - attached and `DEPLOYED` on the border leaf, with
  the declared interface, dot1q tag and neighbour address present in the
  attachment's `extensionValues`. This is the check that catches a stage 02
  re-run that silently detached what stage 05 attached: without it the VRF
  still exists, both leaves are still attached, and external connectivity is
  simply gone.

`extensionValues` is a JSON document encoded into a string field, and its
inner keys are an NDFC implementation detail rather than a documented
contract, so the three declared values are matched as substrings of the raw
field rather than by walking a parsed structure. A schema change then costs a
false failure that is obvious from the report, instead of a check that
silently passes because a renamed key read as absent on both sides.

Reading the report:

- **`DC-Service-Leaf` should now appear as a real `DEPLOYED` attachment, not
  under "Not attached".** It is still absent from `vrf_attach_groups`, so it is
  absent from the "Switches declared" column, but stage 05 attaches it - which
  is why the extension is checked on its own rows rather than through
  "Switches missing". If it is back under "Not attached", stage 05 did not run
  or was undone by a stage 02 re-run.
- A name under **"Switches missing"** or **"Attachments missing"** is a real
  fault: something declared did not attach.
- An attached switch in **`PENDING`** means the intent exists on the
  controller but was never pushed. Re-run `06_recalculate_and_deploy.yml`.
- The report is regenerated on each run that reaches the end. If a run fails
  early, the previous report is left in place, so check its `Generated`
  timestamp before trusting it.

## Scope

The pipeline carries all of the guide's sections 4, 5 and 6: everything
`cisco.nac_dc_vxlan` 0.9.0 can express, plus the fabric settings it cannot,
which stage 03 supplies. It also carries section 7 in full - the External
fabric *and* the edge router in it - and all of section 8 on the fabric side:
the Recalculate and Deploy that synchronises the two fabrics is stage 06, and
the three per-VRF extensions are stage 05.

**What stays manual is the edge router's side of the handoff**, and that is a
platform boundary rather than a gap in the automation. The External fabric is
created with `IS_READ_ONLY: true`, and Cisco is explicit that *"when an
external fabric is set to Fabric Monitor Mode Only, you cannot deploy
configurations on the switches"*. Nexus Dashboard therefore never writes the
matching sub-interfaces and BGP neighbours on `DC-SITE11-CEDGE8Kv`; in this
lab they are pre-built by the pod. That is also why the addresses in
`dc_vrf_lite.yml` are pinned instead of being allocated from
`DCI_SUBNET_RANGE` by `AUTO_UNIQUE_VRF_LITE_IP_PREFIX`: if the leaf picked its
own, they would not match the far end.

**The External fabric** is built by stage 04, in Monitor Mode, with ASN 65531.
Monitor Mode is not something the Nexus as Code model can express, and the
collection does not merely omit it: `dc_external_fabric_general.j2` ties
`IS_READ_ONLY` to the bootstrap setting instead, emitting `false` when
bootstrap is off and `""` when it is on. Neither can produce `true`, so
applying a Nexus as Code model to this fabric would take it *out* of Monitor
Mode. Stage 04 therefore builds the fabric with `cisco.dcnm.dcnm_fabric` and
sets Monitor Mode in the same call, so the fabric is never briefly writable.

**The edge router** `DC-SITE11-CEDGE8Kv` (`198.18.133.14`) is also added by
stage 04, but not with a `cisco.dcnm` module. Nexus Dashboard 4.x has two
switch APIs, and only one of them supports a non-NX-OS device.

The **legacy NDFC API** under `/appcenter/.../rest/control/` is what
`dcnm_inventory` drives, and therefore what Nexus as Code drives. It has no
IOS-XE support. The equivalent play would be:

```yaml
cisco.dcnm.dcnm_inventory:
  fabric: External
  state: merged
  config:
    - seed_ip: 198.18.133.14
      auth_proto: MD5
      role: edge_router
      preserve_config: true
```

Run against this fabric, it fails with `Switch with IP 198.18.133.14 is not
reachable or is not a valid IP`, although the router is reachable and the
credentials are correct. The sequence is:

1. `update_create_params()` builds a fixed payload - `seedIP`,
   `snmpV3AuthProtocol`, `username`, `password`, `maxHops`,
   `cdpSecondTimeout`, `role`, `preserveConfig`, `discoveryCredForLan`. There
   is no key for the device type.
2. That payload is POSTed to `inventory/test-reachability`, which returns
   HTTP 200 with `reachable: true`, `auth: true`, `statusReason: "SNMPv3
   Timeout"`, `valid: false`, `selectable: false`, and null `serialNumber`,
   `platform` and `version`. The SSH login succeeded, but without a device
   type the controller still required SNMPv3, so it read no device identity.
3. `get_diff_merge()` expects a `Name(SERIAL)` pattern in `deviceIndex` and
   finds the bare IP, which produces the reported error.

A newer collection release would not change this. `platformType`,
`device_type`, `ios-xe` and `iosxe` appear nowhere in `cisco.dcnm` 3.13.0,
which is also the tip of that collection's `main` branch, nor in
`cisco.nac_dc_vxlan`. Passing `platformType` to the legacy endpoint directly
has no effect either, because the endpoint ignores it.

The role is not the constraint: `edge_router` is a valid `dcnm_inventory`
choice and a recognised Nexus as Code role.

The **ND 4.x manage API** does support it. Stage 04 makes the same two calls
the UI makes behind its Discover Switches and Add Switches steps:

```
POST /api/v1/manage/fabrics/External/actions/shallowDiscovery
{"seedIpCollection":["198.18.133.14"],"platformType":"ios-xe",
 "snmpV3AuthProtocol":"md5","username":"...","password":"...",
 "maxHop":0,"discoveryCredForLan":false}

POST /api/v1/manage/fabrics/External/switches?ticketId=
{"platformType":"ios-xe","snmpV3AuthProtocol":"md5",
 "username":"...","password":"...","preserveConfig":true,
 "useCredentialForWrite":false,
 "switches":[{"ip":"198.18.133.14","hostname":"DC-SITE11-CEDGE8Kv",
              "model":"C8000V","softwareVersion":"17.18.4",
              "serialNumber":"...","vdcId":0,"vdcMac":""}]}
```

Discovery supplies `model`, `softwareVersion` and `serialNumber`. Those are
pod-specific, so the stage reads them rather than declaring them. Three
details matter in the second call: it returns **202 with an empty body**, so
the add is asynchronous and the stage polls `GET
/api/v1/manage/fabrics/<fabric>/switches` for the outcome; no role is sent,
because the controller assigns `edgeRouter` itself; and `preserveConfig` must
be `true`, since the fabric is in Monitor Mode and the router's running
configuration belongs to the lab.

`snmpV3AuthProtocol` is a string on the manage API. Sending that same string
to the legacy endpoint returns `HTTP 400: Cannot deserialize value of type int
from String "md5"`. The two APIs do not share a schema, so a payload captured
from the UI is not portable between them.

`platformType` is the API form of the UI's `Device type: IOS XE` dropdown and
its `CSR/CAT8K/ASR/CAT9K` sub-selector. It selects the discovery protocol
rather than labelling the device. Cisco's External Connectivity Network guide
states that *"Cisco CSR 1000v is discovered using SSH ... does not need SNMP
support"* and that *"Starting from NDFC release 12.1.3b, SNMP is not required
for IOS-XE devices."* Omitting it makes the controller use the NX-OS SNMPv3
path, which produces the timeout above.

Stage 04 is safe to re-run: the fabric converges with `state: merged`, and the
router is discovered and added only when the fabric's switch list does not
already contain it. Skip the router with `-e
dc_external_add_edge_router=false`.

**The VRF-Lite extensions themselves** - MAIN, PROD and IOT reaching out of
DC-Service-Leaf to the edge router - are stage 05, `05_vrf_lite.yml`. They are
the one part of the build that does not come from the Nexus as Code model,
because that model cannot express them: a `vrf_attach_group` entry names a
switch and nothing else, with no key for `EXTEND: VRF_LITE`, the
sub-interface, the dot1q tag or the neighbour address. Attaching
DC-Service-Leaf there would give the border leaf the VRFs *without* the
extensions, which is worse than not attaching it at all - so `vrfs.nac.yaml`
deliberately leaves it out and stage 05 drops to `cisco.dcnm`'s `dcnm_vrf`
directly, which does support `attach[].vrf_lite[]`.

The intent is still declared in git, in
`inventory/group_vars/all/dc_vrf_lite.yml`. It restates only what the model
cannot hold - the border leaf, the interface, and one row per VRF carrying the
dot1q tag, the sub-interface address and the neighbour address. `vrf_id` and
`vlan_id` are read back out of `vrfs.nac.yaml` at run time rather than copied,
so the two files cannot disagree.

| VRF | dot1q | Sub-interface | Neighbour |
|---|---|---|---|
| PROD | 2 | `192.168.252.5/30` | `192.168.252.6` |
| IOT | 3 | `192.168.252.9/30` | `192.168.252.10` |
| MAIN | 4 | `192.168.252.13/30` | `192.168.252.14` |

All three ride `Ethernet1/8`, which is not a choice - Nexus Dashboard detects
it over CDP, and the pending config it stages for the deploy names both ends:
`description connected-to-DC-SITE11-CEDGE8Kv-GigabitEthernet2`. The addresses
are pinned rather than left to `AUTO_UNIQUE_VRF_LITE_IP_PREFIX` for the reason
the guide gives beside the same fields: the router's side of these links is
pre-built by the pod and the External fabric is in Monitor Mode, so if the
leaf allocated its own addresses they would not match the far end.

**Stage 05 stages the extensions; it does not deploy them.** Attaching an
extension writes intent to the controller and touches no switch, which is
what stages 02, 03 and 04 do, so it belongs on that side of the line. Stage
06 is the only stage that changes running configuration, and because the
extensions are already staged when it runs, one Recalculate and Deploy pushes
the parent interface, the three sub-interfaces and their BGP neighbours
together. The guide reaches the same place by deploying, editing each VRF and
deploying again - an artefact of driving the controller through a UI one
dialog at a time, not something the pipeline has to copy. Use
`-e dc_vrf_lite_deploy=true` to make the stage push on its own, which is only
useful when re-attaching extensions to a fabric that is already deployed.

Two ordering constraints, both enforced by `01_dc_deploy.yml`:

- **Stage 05 runs after stage 02 on every pass, not once.** The create role
  runs `dcnm_vrf` with `state: replaced` against a model that omits
  DC-Service-Leaf, so every create run detaches these extensions. Stage 05
  puts them back, and is idempotent when they are already there.
- **Stage 05 runs after stage 04, and cannot run immediately after it.** The
  extension hangs off the inter-fabric link that `VRF_LITE_AUTOCONFIG`
  builds, and the controller only builds that once it has detected the CDP
  adjacency between the border leaf and the edge router - which it does
  asynchronously, after stage 04's add returns `HTTP 202` with an empty body.
  The stage waits that out with `until`/`retries` (6 x 20s by default, raise
  it with `-e dc_vrf_lite_retries=12`) rather than failing. See
  [The wait that replaced the second deploy](#the-wait-that-replaced-the-second-deploy).

Stage 05 uses `state: merged`, not `replaced`, so the DC-Leaf1 and DC-Leaf2
attachments made by stage 02 survive. Stage 07 re-checks every attachment, so
if that ever stopped being true the pipeline would fail rather than quietly
strip the server leaves.

**The edge router's side stays manual**, for the Monitor Mode reason given at
the top of this section. Automating it would mean either taking the External
fabric out of Monitor Mode, which hands the pre-built router's configuration
to the controller, or adding a `cisco.ios` play that reaches the router
directly. Neither is done here, and neither should be done on this pod.

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
