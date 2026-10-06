# PseudoCo DC fabric - Nexus as Code pipeline

This pipeline builds the VXLAN EVPN data center fabric `Pseudoco-DC1` on Cisco
Nexus Dashboard 4.2.1.10, from a declarative YAML model held in git.

It automates sections 4 through 8 of the student guide's **Nexus Dashboard - DC Fabric
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
  Nexus Dashboard is *intent*. Stages 02 to 06 write intent; stages 05 and 07
  are the deploy stages that change running configuration.

### Network as Code roles and their fabric outcomes

These three Network as Code roles turn the declared model into a checked,
staged, and deployed data center fabric. Each has a distinct part in that path:

| Role | Called by | What it does |
|---|---|---|
| `cisco.nac_dc_vxlan.validate` | 02, 05, 07, and 08, as the first role of the play | Reads every `*.nac.yaml` out of `playbooks/host_vars/<fabric>/` and checks it against the collection's schema and rule set. Touches neither controller nor switch. A model error fails here instead of half way through a build |
| `cisco.nac_dc_vxlan.dtc.create` | 02 | Builds the fabric intent on the controller; see the sequence below |
| `cisco.nac_dc_vxlan.dtc.deploy` | 05 and 07 | The UI's Recalculate and Deploy. The only thing in this pipeline that changes running configuration |

Stage 02 builds:

- Fabric object
- Switch import and roles
- vPC pair
- Port-channels
- VRFs
- Networks
- Attachments

Switch import is the exception to the controller-only changes: it is a greenfield write that erases the switch's existing running configuration.

`validate` runs ahead of the other two in the same play rather than as a
separate stage, because they read the same files and neither notices a key
the schema would have rejected.

Stages 03, 04, 06 and 08 call **no** Nexus as Code role. They use `cisco.dcnm`
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
| `cisco.nxos` | 10.2.0 | Used by **two stages only** - `00_discover_dc_switch_serials.yml`, which SSHes to the switches to read their serial numbers, and the BGP session check in `08_verify_fabric.yml`, which reads the border leaf. Every other stage talks to Nexus Dashboard over `httpapi` and needs none of it |

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
cd ~/cisco-one-experience-lab-automation/ansible-automation/02_data_center/ansible
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
| `01_dc_deploy.yml` | Orchestrator. Imports 02 to 08 in order |
| `02_create_dc_fabric.yml` | Creates the whole intent on the controller: fabric, switch import, roles, vPC pair, port-channels, VRFs, networks |
| `03_fabric_advanced_settings.yml` | Applies the settings Nexus as Code cannot express. See [Settings Nexus as Code cannot express](#settings-nexus-as-code-cannot-express) |
| `04_external_fabric.yml` | Creates the External connectivity fabric in Monitor Mode, adds the IOS-XE edge router to it, and builds the VRF-Lite inter-fabric link that stage 06 needs |
| `05_recalculate_and_deploy.yml` | First "Recalculate and Deploy". Pushes the fabric, which configures the parent interface of that link - the point at which the controller starts offering stage 06 a prototype |
| `06_vrf_lite.yml` | Reserves the declared dot1q tags out of `TOP_DOWN_L3_DOT1Q`, then adds the three VRF-Lite extensions to the border leaf's VRF attachments, from `inventory/group_vars/all/dc_vrf_lite.yml`. Stages intent only |
| `07_recalculate_and_deploy.yml` | Second "Recalculate and Deploy". Pushes the extensions staged by stage 06 and is the **only** stage that changes running configuration |
| `08_verify_fabric.yml` | Read-only check against the declared model, over the Nexus Dashboard API and over SSH to the border leaf with pyATS/Genie. Writes `evidence/stage08-verification.md` |
| `09_cleanup.yml` | Destructive teardown: overlays, inter-fabric link, switches, both fabrics, then the sub-interfaces on the border leaf. Needs `-e dc_cleanup_confirm=CLEANUP_OK` |

The numbering tells you who runs a playbook. Stages 02 to 08 are contiguous
because they are exactly what `01_dc_deploy.yml` imports. Stage 00 sits below
that range because it is the prerequisite you run yourself, once per pod, and
09 sits above it because it is deliberately outside the orchestrated run.

Stages 03 and 04 run before the first deploy because their settings and
External fabric are inputs to the inter-fabric link, and stage 04 is what
creates that link. Stage 06 runs after stage 05 because the controller will not
offer it a prototype until the link's parent interface has been configured on
the switch. Stage 07 then carries the three dot1q sub-interfaces and their BGP
neighbours to the border leaf. The execution order is `02, 03, 04, 05, 06, 07,
08`.

Useful overrides:

- `--tags cr_manage_fabric` narrows stage 02 to the fabric object alone, which
  is the guide's "Create a VXLAN Fabric" step on its own
- `-e dc_verify_fail_on_mismatch=false` has stage 07 write its report without
  failing the run
- `-e dc_verify_bgp_sessions=false` has stage 07 skip the one check that needs
  SSH to a switch, and compare only what the controller knows

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
| `inventory/group_vars/all/dc_vrf_lite.yml` | The three VRF-Lite extensions out of the border leaf, and the addressing of the inter-fabric link they sit on. Applied by stages 04 and 06 |
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
          - hostname: DC-Leaf1
          - hostname: DC-Leaf2
          - hostname: DC-Service-Leaf   # the border leaf, extended by stage 05
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
  VRF_LITE_AUTOCONFIG: "Manual"          # we build the IFC ourselves, in stage 04
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
    dot1q: "2"                           # a string: the controller stores it as one
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
- **`DC-Service-Leaf` is in `vrf_attach_groups`, and the extension still is
  not.** An entry there can name a switch and nothing else, so the model can
  attach the three VRFs to the border leaf but can never carry the
  `EXTEND: VRF_LITE` that makes them reachable from outside. That is a
  two-step job, which is exactly how the guide does it: section 8 has two
  Detach/Attach sliders per VRF, one for the attachment and one, inside Edit
  Extension Details, for the extension. So the model owns the attachment and
  stage 06 adds the extension on top with a direct `POST`. Until
  2026-09-27 the border leaf was left out here on the view that an attachment
  without its extension was worse than none; it is not, it is the first half
  of the job, and leaving it out made the attachment something stage 06 had
  to keep re-creating. Note what did **not** change: stage 02 runs `dcnm_vrf`
  with `state: replaced`, and `replaced` against an attachment whose
  extension the model cannot describe resets that extension, so **stage 06
  still has to run after stage 02 on every pass**. It just no longer has to
  put the attachment back as well.

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
  00_discover_dc_switch_serials.yml ... 09_remove.yml
  host_vars/Pseudoco-DC1/*.nac.yaml   the data model
  templates/stage08-verification.md.j2
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
Nexus Dashboard, attached to DC-Leaf1, DC-Leaf2 and DC-Service-Leaf - and
`PENDING`, because nothing has been pushed.

**5. Extended.** Stage 06 reads `dc_vrf_lite.yml`, reads the prototype the
controller offers on `Ethernet1/8` for the neighbour ASN and the peer's Jython
template, and reads the attachment stage 02 made for its VLAN and instance
values. It merges the declared values over the prototype - `Ethernet1/8`,
dot1q `2`, `192.168.252.5/30`, neighbour `192.168.252.6`, plus the
sub-interface MTU - and posts all three VRFs to the attachments endpoint in a
single payload, naming only DC-Service-Leaf. The other two attachments from
step 4 are untouched because they are not in the payload, and a re-run sends
nothing because each declared field is compared against the controller first.
Still nothing on a switch.

**6. Deployed.** Stage 06 runs `cisco.nac_dc_vxlan.dtc.deploy`, which asks the
controller which switches have pending configuration and deploys them. PROD's
VRF and SVIs land on all three leaves; on the border leaf the same push carries the
parent `Ethernet1/8`, the `.2` sub-interface and the eBGP neighbour, because
step 5 staged them before this ran. Every attachment flips `PENDING` ->
`DEPLOYED`.

**7. Verified.** Stage 07 reads `vrfs.nac.yaml` again - the same file, not a
copy - and compares it against the controller: PROD exists with VNI 50001, is
attached to all three declared leaves, every attachment reads `DEPLOYED`, and
the border leaf's attachment carries the declared interface, dot1q tag and
neighbour address in its `extensionValues`. The VRF, `ProdNetwork1`, and
VRF-Lite rows are three of the fourteen controller checks. When SSH BGP
verification is enabled and the border leaf answers, the report also evaluates
three BGP session checks, for seventeen checks total.

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

Two mechanical details of that substitution are worth knowing before editing
it. The backreferences in the `replace` task are written `\g<1>` and `\g<2>`
rather than `\1` and `\2`, because a Nexus serial can start with a digit and
`\1` followed by a digit reads as a two-digit group number. And an anchored
regex that matches nothing is not an error to the `replace` module - it leaves
the file alone and reports no change - which is why the stage slurps the
finished file back and asserts on its contents instead of trusting the task
results.

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
| VRF Lite Deployment | `VRF_LITE_AUTOCONFIG` | `Manual` |
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

Two details of the second half, the read-modify-write on the fabric object. The
`GET` has to run *after* the `dcnm_fabric` task rather than before it: the
fabric object carries a camelCase mirror of the nvPairs, so a copy read first
would put the old VRF-Lite values straight back when it is `PUT`. And the stage
asserts that every declared property already exists on the object, because
Nexus Dashboard would otherwise accept a `PUT` carrying a mistyped property name
and ignore it, leaving a stage that reports success and changed nothing. On the
nvPair half the controller does that work itself: a key the fabric template does
not have fails the task with `Key <name> not found in fabric configuration`.

**"Add Switches without Reload" is deliberately not here.** It is the
`GRFIELD_DEBUG_FLAG` nvPair, and Nexus as Code does model it, as
`vxlan.global.ibgp.greenfield_cleanup` in `global.nac.yaml`. Two files setting
one nvPair is a drift bug waiting to happen; this stage carries only what the
model cannot express.

### The two VRF-Lite settings, as Cisco defines them

These two are the reason stage 03 exists. Both are on the fabric's Resources
tab.

**`VRF_LITE_AUTOCONFIG: "Manual"`** is the UI's **VRF Lite Deployment** field.
Cisco's Nexus Dashboard 4.2.1 fabric settings reference defines it as:
*"Specify the VRF Lite method for extending inter fabric connections. The VRF
Lite Subnet IP Range field specifies resources reserved for IP address used for
VRF Lite when VRF Lite IFCs are auto-created. If you select
Back2Back&ToExternal, then VRF Lite IFCs are auto-created."*
([Editing Data Center VXLAN Fabric Settings, Release 4.2.1](https://www.cisco.com/c/en/us/td/docs/dcn/nd/4x/articles-421/editing-fabric-settings-data-center-vxlan.html))
The VRF Lite article is more specific about what gets connected to what:
*"Use this option to automatically configure VRF Lite IFCs between a border
switch and the edge or core switches in external fabric or between
back-to-back border switches in VXLAN EVPN fabric."*

**This collection deliberately does not use that automation.** It was set to
`Back2Back&ToExternal` until 2026-09-27, and the reason for changing it is the
whole point of the setting: auto-created IFCs get controller-chosen addresses
and controller-chosen dot1q tags. The edge router on this pod is pre-built and
in Monitor Mode, so its `GigabitEthernet2.2/.3/.4` addresses and tags are
fixed and cannot be moved to meet the controller. Every value has to come from
the data model instead, so stage 04 creates the IFC itself with `dcnm_links`
and the `ext_fabric_setup` template, and stage 06 reserves the dot1q tags before
attaching. Under `Manual` the controller creates nothing of its own.

Two companion settings went with it. `AUTO_SYMMETRIC_VRF_LITE` and
`AUTO_UNIQUE_VRF_LITE_IP_PREFIX` are not merely unnecessary under `Manual` -
the controller rejects them, so they are absent from
`dc_advanced_settings.yml` rather than set to `false`.
([Nexus Dashboard - VRF Lite](https://www.cisco.com/c/en/us/td/docs/dcn/ndfc/1221/articles/ndfc-vrf-lite/vrf-lite.html))
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
[Nexus Dashboard Terraform provider](https://registry.terraform.io/providers/CiscoDevNet/ndfc/latest/docs/data-sources/fabric)
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

There is a third reason not to write to that router, and it is the strongest
of the three: **`DC-SITE11-CEDGE8Kv` is an SD-WAN edge managed by vManage.**
Its interface list carries `Sdwan-system-intf`, `vmanage_system` and
`Tunnel3`, so its configuration belongs to the Catalyst SD-WAN controller.
Two controllers writing the same device is a worse outcome than a handoff
half-automated.

## The router's side of the handoff, verified

**It is fully built, and it matches the declared intent exactly.** This is
worth stating plainly because the controller's view of the device suggests
otherwise, and that view is misleading.

```
DC-SITE11-CEDGE8Kv# show ip interface brief
Interface              IP-Address      OK? Method Status   Protocol
GigabitEthernet2       unassigned      YES unset  up       up
GigabitEthernet2.2     192.168.252.6   YES other  up       up
GigabitEthernet2.3     192.168.252.10  YES other  up       up
GigabitEthernet2.4     192.168.252.14  YES other  up       up
```

Those three addresses are exactly the `neighbor_ipv4` values in
`dc_vrf_lite.yml`, on exactly the declared dot1q tags, and the router has an
eBGP neighbour configured for each of `192.168.252.5`, `.9` and `.13` in
AS 65000 - our fabric's ASN, peered from its own 65531.

**Reading `SUBIFS=[]` from the controller is not evidence that the router is
unconfigured.** Nexus Dashboard reports an empty sub-interface list, no VRF
definitions and no `192.168.252.x` addresses for this device, and that is
Monitor Mode behaving as designed: the controller does not manage the router,
so it holds no policy for it and has nothing to report. Ask the router, not
the controller.

One mismatch is real but harmless. The router's own VRFs are named `10`, `101`
and `102` rather than `MAIN`, `PROD` and `IOT` - vManage names a VRF by its
SD-WAN VPN id. `Gi2.4` is in VRF `10` (MAIN), `Gi2.2` in `101` (PROD) and
`Gi2.3` in `102` (IOT). The `peer_vrf` values in `dc_vrf_lite.yml` are the
name Nexus Dashboard would give the far-side VRF if it configured the far
side, which it never does, so nothing compares the two.

### What the router shows when the fabric side is not deployed

The router is the only place in this lab that can tell you whether the handoff
actually works, and on a pod where stage 06 has not pushed the sub-interfaces
it says so clearly:

```
DC-SITE11-CEDGE8Kv# show bgp vpnv4 unicast all summary
Neighbor        V           AS MsgRcvd MsgSent  Up/Down  State/PfxRcd
192.168.252.5   4        65000       0       0  1d18h    Active
192.168.252.9   4        65000       0       0  1d18h    Active
192.168.252.13  4        65000       0       0  1d18h    Idle
```

`Active` and `Idle` with zero messages in either direction means the TCP
session is not being answered. The matching read on the border leaf explains
why:

```
DC-Service-Leaf# show running-config interface Ethernet1/8
interface Ethernet1/8
  description connected-to-DC-SITE11-CEDGE8Kv-GigabitEthernet2
  no switchport
  mtu 1500
  no shutdown

DC-Service-Leaf# show ip interface brief vrf all | include 192.168.252
DC-Service-Leaf#
```

The parent is up and the three sub-interfaces do not exist, so there is
nothing for the router to peer with. Stage 05 can report success and stage 07
can pass while this is true, because both are intent-versus-controller
comparisons. The extensions are staged; they reach the switch only on the
stage 06 deploy that follows.

### Why the BGP check uses SSH

**Stage 07 checks the three VRF-Lite eBGP sessions by reading the border leaf
over SSH, and it is the only check in the stage that does not come from the
controller.** The evidence above is why it exists: every controller-side check
can be green while all three sessions sit in `Active`. Without this check a
student following the guide gets a clean run and no external connectivity,
with nothing in the output pointing at the cause.

**Nexus Dashboard has no API that answers the question.** Its LAN API is an
intent and provisioning surface plus config compliance - fabrics, switches,
VRFs, networks, attachments, links and the deploy and compliance state of
each. None of those report routing protocol state, so an attachment reading
`DEPLOYED` means the controller pushed a sub-interface and a neighbour
statement, and nothing more. Whether the neighbour answered is only visible on
a device, and the two come apart routinely here, because the far end of these
three links is pre-built by the pod and the controller never writes to it: an
address or dot1q tag that does not match the router leaves the leaf configured
exactly as declared, with a session that never leaves `Idle`.

Three properties of how the check is built, each of which is the reason it can
be added without weakening the rest of the stage:

- **It reads the border leaf, not the router.** `DC-Service-Leaf` reports the
  same session state, and reading it keeps the check inside the fabric the
  pipeline owns. It needs no second credential and no exception to the rule
  that nothing touches `DC-SITE11-CEDGE8Kv`. The SSH settings and the vault
  credentials are the ones stage 00 already uses, in
  `inventory/group_vars/dc_fabric_switches/connection.yml`, so the play adds
  the border leaf to that group with `add_host` rather than repeating them.
- **It is optional, and non-fatal when the switch is unreachable.** Every
  other check in stage 07 talks to the controller and works with the VPN to
  the `198.18.128.x` management range down, so "could not determine" is a
  distinct outcome from "down". An unreachable border leaf costs one check
  rather than the whole report: those rows read `not determined`, are left out
  of both the failure list and the total, and never fail the run.
  `-e dc_verify_bgp_sessions=false` skips the SSH read entirely.
- **It is reported apart from the intent tables.** It answers a different
  question - not "did the controller accept what we declared" but "did the
  neighbour answer" - so it has its own table in the report, and a run that
  could not make it says so on screen rather than leaving a green "all checks
  match" to be read as a fabric that works.

The command is `show bgp sessions vrf <vrf>`, one per declared extension, from
the "Monitor BGP Statistics" table of the [Cisco Nexus 9000 Series NX-OS
Unicast Routing Configuration Guide, Release
10.6(x)](https://www.cisco.com/c/en/us/td/docs/dcn/nx-os/nexus9000/106x/configuration/unicast-routing-configuration/cisco-nexus-9000-series-nx-os-unicast-routing-configuration-guide/configuring-bgp.html).
The VRF name has to be on the command: a VRF-Lite peering lives inside its
VRF, not in the default VRF and not in the EVPN address family, so without it
the neighbour is not in the output at all. `output: json` asks NX-OS for the
structured form, so nothing downstream matches against screen text.

Two shapes in that output are worth knowing, because both are silent when
mishandled. NX-OS returns `ROW_vrf` and `ROW_neighbor` as a bare object when
there is one and as a list when there are several, so each is wrapped into a
list before it is searched. And `vrf-name-out` may come back lower case where
the data model declares `PROD`, so the VRF names are compared
case-insensitively. Either mistake produces `absent` on a healthy fabric
rather than an error.

## What stage 06 needs from the controller

**Stage 06 needs a VRF-Lite inter-fabric link to already exist on
`Ethernet1/8`, and it needs that link's parent interface to have been
configured on the switch.** Stage 04 creates the link; stage 05 deploys it.
That is why `01_dc_deploy.yml` puts a deploy between them.

The symptom when the precondition is missing is
`Prototype extensionType(s) returned: []` from stage 06's precheck; once
stage 05 has run it reports `Controller offers 1 VRF_LITE extension
prototype(s)` and attaches all three VRFs.

**This used to be the controller's job, and no longer is.** Until 2026-09-27
`VRF_LITE_AUTOCONFIG` was `Back2Back&ToExternal` and Nexus Dashboard built the
link itself during a Recalculate and Deploy. The link it produced carried its
own provenance:

```
templateName        ext_fabric_setup
SOURCE              Pseudoco-DC1_AUTO_CONFIG_IFC_VRFLITE_955T6I5X2D4
AUTO_VRF_LITE_FLAG  true
MTU                 9000
NEIGHBOR_ASN        65531
```

That worked, but it chose its own addresses out of `DCI_SUBNET_RANGE` and its
own dot1q tags, and neither can be negotiated with a pre-built edge router in
Monitor Mode. So the setting is `Manual` now and stage 04 builds the link from
`dc_vrf_lite_ifc`. A link created that way carries no `SOURCE` and has
`AUTO_VRF_LITE_FLAG` unset - that pair is how you tell which kind you are
looking at.

Historical note, because the failure text is distinctive. Stage 06 used to use
`dcnm_vrf`, which refuses to build an extension without a prototype and says
so like this:

```
DcnmVrf.update_vrf_attach_vrf_lite_extensions: caller: push_diff_attach.
No VRF LITE capable interfaces found on this switch.
ip: 198.18.128.13, serial_number: 955T6I5X2D4
```

Stage 06 posts to the attachments endpoint directly now, for the reasons in
[dc_vrf_lite.yml](inventory/group_vars/all/dc_vrf_lite.yml), so that message no
longer appears - but the precondition it was complaining about is unchanged.

**Every `dcnm_vrf.py` line number in this README is against `cisco.dcnm`
3.13.0**, which is what `collections/requirements.yml` pins and what the
script server installs. Read that source without installing it with:

```bash
ansible-galaxy collection download cisco.dcnm:3.13.0 -p /tmp/x
tar xzf /tmp/x/cisco-dcnm-3.13.0.tar.gz plugins/modules/dcnm_vrf.py
```

That message comes from `dcnm_vrf.py` line 4721, and the path to it is worth
knowing because it rules so much out. `push_diff_attach` reads

```
lite_objects["DATA"][0]["switchDetailsList"][0]["extensionPrototypeValues"]
```

at lines 5126-5128, from

```
GET /appcenter/cisco/ndfc/api/v1/lan-fabric/rest/top-down/fabrics/
      Pseudoco-DC1/vrfs/switches?vrf-names=PROD&serial-numbers=955T6I5X2D4
```

(`GET_VRF_SWITCH`, line 1047, called from `get_vrf_lite_objects` at line
2442), keeps only the elements whose `extensionType` is `VRF_LITE` - the one
and only filter, line 4598 - and fails when nothing survives. Three things
follow:

- **It is not an interface-name mismatch.** A prototype whose interface does
  not match `Ethernet1/8` produces a *different* message, "No matching
  interfaces with vrf_lite extensions found on switch", at line 4758. Getting
  4721 means the list had no `VRF_LITE` element at all.
- **It is not a role problem.** `is_border_switch` (line 4557) regex-matches
  `\bborder\b` against the controller's `switchRole` and is checked earlier,
  at line 5103. The run got past it, so the controller does report
  `DC-Service-Leaf` as a border switch.
- **It is not a missing VRF attachment.** `push_to_remote` (line 5495) runs
  `push_diff_create` (5547) before `push_diff_attach` (5548), so at the
  instant this GET is made the VRF exists and the attachment does not. The
  module's own integration test makes the same point deliberately:
  `tests/integration/targets/dcnm_vrf/tests/dcnm/standalone/merged.yaml`
  TEST.4 deletes every VRF and then, in one `state: merged` call, creates a
  VRF and attaches it *with* a `vrf_lite` block to a switch that has no
  attachment - asserting `changed == true` and three HTTP 200s.
  `extensionPrototypeValues` is a property of the switch and its inter-fabric
  connection, not of an attachment.

When that prototype is missing there is no neighbour ASN and no peer template
to build the payload from, so stage 06 stops and says so, naming the ordering
problem it actually is: run stage 05 first.

The prototype is derived from the VRF-Lite inter-fabric link. A pending parent
interface with `no switchport`, an MTU and a CDP description does not prove
that the link is VRF-Lite; the controller must offer a `VRF_LITE` prototype on
`Ethernet1/8`, and stage 04 is what creates that link.

**What Cisco's non-Nexus guidance does and does not mean here.** The
guidelines quoted in the previous section - *"Auto IFC is supported on Cisco
Nexus devices only"* and *"If the device in the External fabric is non-Nexus,
you must create IFC manually"* - did **not** hold on this pod. The peer is an
IOS-XE Catalyst 8000V, and Nexus Dashboard auto-created the IFC anyway, using
an IOS-XE specific peer template, `ios_xe_Ext_VRF_Lite_Jython`. Treat the
observed behaviour on ND 4.2.1 as authoritative over that guideline.

What those quotes still govern is the **far side**. Cisco's non-Nexus
walkthrough is about IOS-XR edge routers in *managed* mode and tells you to
uncheck Fabric Monitor Mode so the controller can push configuration to the
router. This lab does the opposite on purpose: `IS_READ_ONLY: true`, because
the edge router is pre-built by the pod. So the controller will build and
deploy the border-leaf half of the handoff and will never touch
`DC-SITE11-CEDGE8Kv`.

**One explanation that was wrong, and one that was half right.**

*Half right: a CDP-correlation race.* Stage 05 used to retry the `dcnm_vrf`
call, on the theory that the prototype would appear if it waited. The retry was
removed on the strength of one run in which a successful deploy was followed by
a failing stage 05 - which looked decisive and was not. The prototype does
appear once a deploy has run, so the dependency on the deploy was real; what
was wrong was the idea that *waiting alone*, without a deploy in between, would
produce it. `01_dc_deploy.yml` settles this by ordering the stages
`05, 06, 07`, so the deploy that builds the link always runs before stage 06
asks for the extension.

*Wrong: a missing plain attachment.* The guide's section 8 has two
Detach/Attach sliders per VRF and for a while only the second was accounted
for, so the plain attachment looked like the missing precondition. It is a
genuine gap in the data model and it has been closed - `DC-Service-Leaf` is
now in `vrf_attach_groups` - but it was never the cause of this error. The
controller proves it directly: DC-Leaf1 and DC-Leaf2 carry all three VRFs,
attached and `DEPLOYED`, and both return an **empty** prototype list, while
DC-Service-Leaf - the one switch the IFC terminates on - returns
`['VRF_LITE']`. The prototype tracks the link, not the attachment.

## The sub-interface MTU, and why it is declared

**A deploy straight after stage 05 fails with `Delivery failed with message:
MTU of sub-interface greater than parent interface detected`.** Four numbers
explain it, and only one of them is ours to set.

| Value | Where it comes from |
|---|---|
| Parent `Ethernet1/8` MTU **1500** | The `Link MTU` field on the IFC, set from `dc_vrf_lite_ifc.mtu`. Cisco labels it *"Interface MTU on both ends of VRF Lite IFC"*, but it is a controller-side number and, despite the field's name, it is not a reading of the router. It is declared as 1500 here so the parent matches `GigabitEthernet2`; left to the controller it derives 9000. |
| Sub-interface MTU **9216** | The **fallback in the controller's own VRF extension template**. `Default_VRF_Extension_Universal` carries a per-extension `Subinterface MTU` field and renders `if (@ITEM.MTU != "") { mtu @ITEM.MTU } else { mtu 9216 }`. |
| Router IP MTU **1500** | What `DC-SITE11-CEDGE8Kv` actually carries on `GigabitEthernet2` and on all three of its dot1q sub-interfaces. Measured on the pod, not inferred. |
| `dc_vrf_lite_mtu` **1500** | Declared by this repository, in `inventory/group_vars/all/dc_vrf_lite.yml`, to match the router. |

The 9216 is not a `cisco.dcnm` default and not a fabric setting. It is the
template's `else` branch, taken because **`dcnm_vrf` never populates that
field**. Its `vrf_lite` suboptions are exactly `peer_vrf`, `interface`,
`ipv4_addr`, `neighbor_ipv4`, `ipv6_addr`, `neighbor_ipv6` and `dot1q`, and
the list of properties it writes into `VRF_LITE_CONN` is `DOT1Q_ID`,
`IF_NAME`, `IP_MASK`, `IPV6_MASK`, `IPV6_NEIGHBOR`, `NEIGHBOR_IP`,
`PEER_VRF_NAME`. There is no MTU in either. That gap is the reason stage 06
posts the attachment itself instead of calling the module. The controller's own UI does not
have this problem, because the prototype it offers carries the link's own MTU
and the UI writes it through.

**Why the value is 1500.** The parent rules 9216 out, but a parent on its own
does not choose a value: anything from 576 up to the parent's MTU is accepted
by the switch. What chooses it is the router, because a routed link
only works if both ends agree on how large an IP packet may be, and the
router is the end this repository cannot change.

`DC-SITE11-CEDGE8Kv` carries **1500**, measured on the pod:

```
DC-SITE11-CEDGE8Kv# show interfaces GigabitEthernet2
GigabitEthernet2 is up, line protocol is up
  MTU 1500 bytes, BW 1000000 Kbit/sec, DLY 10 usec,

DC-SITE11-CEDGE8Kv# show ip interface GigabitEthernet2.2
  Internet address is 192.168.252.6/30
  MTU is 1500 bytes
```

`GigabitEthernet2.3` and `.4` report the same, and none of the three carries
an `mtu` or `ip mtu` line of its own - `show running-config interface
GigabitEthernet2.2` is four lines long, `encapsulation dot1Q 2`, `vrf
forwarding 101`, the address and `no ip redirects`. They inherit 1500 from
the parent. Cisco's [IP Application Services Command
Reference](https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/ipapp/command/iap-cr-book/iap-i1.html)
gives the default IP MTU for an Ethernet interface as 1500 and states that
*"changing the MTU value (by using the `mtu` interface configuration command)
can affect the IP MTU value. If the current IP MTU value is the same as the
MTU value and you change the MTU value, then the IP MTU value is modified
automatically to match the new MTU value. However, the reverse is not true."*
So on this router the interface MTU and the IP MTU are both 1500, and only an
explicit `ip mtu` - which the [Cisco IOS XE Catalyst SD-WAN Qualified Command
Reference
Guide](https://www.cisco.com/c/en/us/td/docs/routers/sdwan/command/iosxe/qualified-cli-command-reference-guide/m-ip-commands.html)
confirms is valid in `config-subif` on this platform - could separate them.

It is the **IP MTU** that matters on a routed handoff, which is why
`show ip interface` is the command to settle this rather than
`show interfaces`. The [Cisco IOS IP Addressing Services Command
Reference](https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/ipaddr/command/ipaddr-cr-book/ipaddr-r1.html)
documents `show ip interface [type number] [brief]` in privileged EXEC mode
and defines its `MTU is` field as *"MTU value set on the interface, in
bytes"*.

Monitor Mode means Nexus Dashboard can never raise the router to meet a
larger value, so anything above 1500 on our side would be a real mismatch
rather than a conservative choice. Note that the controller's `Link MTU` on
the inter-fabric link and the router's interface MTU are different things, and
the field name *"Interface MTU on both ends of VRF Lite IFC"* makes them easy
to confuse. `dc_vrf_lite_ifc.mtu` sets the first; only the router can tell you
the second.

**How a 1500-versus-9000 mismatch would have presented, had it shipped.** Not
as a failed deploy, and not as a dead BGP session either.

- **The eBGP sessions would still come up.** BGP runs over TCP, and TCP sizes
  its own segments from the interface MTU at each end. Cisco's [Resolve IPv4
  Fragmentation, MTU, MSS, and PMTUD Issues with GRE and
  IPsec](https://www.cisco.com/c/en/us/support/docs/ip/generic-routing-encapsulation-gre/25885-pmtud-ipfrag.html)
  describes the mechanism: the MSS a host advertises is *"the minimum buffer
  size and the MTU of the outgoing interface (- 40)"*, and *"the hosts then
  compare the MSS size received against their own interface MTU and again
  choose the lower of the two values."* The router would advertise an MSS
  derived from 1500, the leaf would honour it, and the session would
  establish and exchange routes normally. A mismatch here is invisible to the
  thing a student is most likely to check.
- **Transit traffic above 1500 bytes would be dropped, not fragmented.** The
  leaf would be willing to put a 9000-byte IP packet on the wire; the router
  would receive a frame larger than its interface can accept and discard it.
  Nothing on the leaf would report an error, because from its point of view
  the packet was sent successfully.
- **There is no OSPF or IS-IS here to catch it.** Those protocols exchange
  MTU in their database-description packets and refuse to form an adjacency
  on a mismatch, which turns the fault into an immediate, obvious failure.
  This handoff is eBGP per VRF over dot1q sub-interfaces, so that safety net
  does not exist.

A note on where the parent constraint is written down: the public [Cisco
Nexus 9000 Series NX-OS Interfaces Configuration
Guide](https://www.cisco.com/c/en/us/td/docs/dcn/nx-os/nexus9000/106x/configuration/interfaces/cisco-nexus-9000-series-nx-os-interfaces-configuration-guide-release-106x/m_configuring_layer_3_interfaces_9x.html)
documents sub-interfaces and gives the configurable MTU range for a Layer 3
interface or sub-interface as 576-9216, but it does not state that a
sub-interface may not exceed its parent. The authority for that here is the
switch itself, which rejected the configuration, and the controller repeated
the rejection verbatim. Treat the error string as the evidence. 1500 is
comfortably inside that range, so the switch accepts it.

`06_vrf_lite.yml` sends it in the same payload as the rest of the extension,
with a single `POST` to `top-down/fabrics/<fabric>/vrfs/attachments`. It starts
from the prototype the controller offers rather than building a connection from
nothing, because the controller enriches the prototype from the IFC -
`NEIGHBOR_ASN` and `AUTO_VRF_LITE_FLAG` are server-side, and a hand-built
replacement would drop them. The
VLAN and `instanceValues` come from the attachments endpoint, not from
`vrfs/switches`, which reports the VLAN as `-1` and returns no instance
values. The task only posts for a VRF whose MTU is not already the declared
value, so a second run sends nothing.

**The `lanAttachList` in that POST holds only `DC-Service-Leaf`, and that is
safe.** MAIN, PROD and IOT are attached to DC-Leaf1 and DC-Leaf2 as well, by
stage 02, so it matters whether the controller reads the list as the whole
truth for the VRF, which would silently detach both server leaves, or as a
per-switch upsert. It is a per-switch upsert: detaching is something a caller
has to ask for explicitly, and omission is inert.

Cisco documents `deployment` as the attach/detach selector on each object in
the list. The [vrfAttachmentsPostPayload
schema](https://developer.cisco.com/docs/nexus-dashboard/latest/vrfattachmentspostpayload/)
(Nexus Dashboard API v1, Release 4.2 and later) describes that boolean as
*"When deployment value is true it means it is to attach and when the value is
false it means it is detach"*, and the [Nexus Dashboard API changelog for 12.1.2
changelog](https://developer.cisco.com/docs/nexus-dashboard-fabric-controller/12-1-2/api-changelog/)
says the same of this exact path, under the heading *"Attach/Detach
VRFs/VRF-Lite"*: *"List of LAN Attach objects. When in Lan Attach object
deployment:true it's attach and when deployment:false it's detach."* Neither
page states a merge rule for the list in so many words, so the confirmation
that a short list is harmless comes from the module.

`dcnm_vrf` posts partial lists as its ordinary mode of operation. Under
`state: merged`, `diff_merge_attach` (line 3379) sets the outgoing list to the
output of `diff_for_attach_deploy` (lines 3403-3411), and that function
appends only the switches whose state actually differs: its two
`attach_list.append(want)` calls, at lines 1583 and 1625, are both reached
only after a comparison has failed. A switch that is
attached and unchanged never reaches the payload. Stage 05 already depends on
this: it runs `merged` naming only the border leaf, and the DC-Leaf1 and
DC-Leaf2 attachments survive it.

The settling evidence is what the module does when it *does* want a detach.
Every detach path builds an explicit entry carrying `deployment: False` and
puts it in the same `lanAttachList`: `get_diff_delete` (line 2871, at lines
2912 and 2936), `get_diff_override` (line 2969, at line 2998) and
`get_diff_replace` (line 3033, at lines 3065 and 3079). `get_diff_replace`
walks the controller's current attachments, finds each switch the playbook did
not name, and re-posts it with `deployment: False` (lines 3058-3066). If
leaving a switch out of the list were enough to detach it, that loop would be
dead code and `replaced` could simply post the wanted list.

One helper named in earlier versions of this section is gone. `get_diff_delete`
used to delegate to a `get_items_to_detach` method; in 3.13.0 there is no such
method and the delete path builds its `detach_items` list inline, in the two
blocks cited above. The behaviour is unchanged - an explicit
`item.update({"deployment": False})` per switch - only the structure moved.

The integration tests show the same shape from the outside.
`tests/integration/targets/dcnm_vrf/tests/dcnm/standalone/replaced.yaml`
attaches one VRF to two switches under `merged` (SETUP.4, lines 67-82), then
runs `state: replaced` with no `attach` key at all (TEST.1, lines 118-128).
The asserted result is two diff entries, both `deploy == false` (lines
152-153): the module manufactured two explicit detach records rather than
posting an empty list. TEST.4 (lines 288-302) is the same in miniature, with
only `switch_1` named on the replace and the one diff entry being the dropped
switch at `deploy == false`.

**No `cisco.dcnm` release exposes the sub-interface MTU, checked up to the
current one.** The seven `vrf_lite` suboptions and the seven `VRF_LITE_CONN`
properties listed above are unchanged in 3.13.0, the newest release on Galaxy,
where `vrf_lite_properties` sits at line 1240. The module's `vrf_int_mtu` key
is a different field: it maps to `mtu` in `Default_VRF_Universal`, the VRF's
own L3 interface MTU, not the extension's `Subinterface MTU`. The field is not
missing from the product, since Nexus Dashboard's newer model exposes it as
`extensionValues[].mtu` defaulting to 9216 in
[vrfAttachmentDetail](https://developer.cisco.com/docs/nexus-dashboard/latest/one-manage-one-manage-model-vrfattachmentdetail/),
but no module reaches it, so the hand-built POST stays.

**What the POST echoes back, and why each field is safe to echo.**
`freeformConfig` is *"any configuration not included in overlay templates
which is needed as part of this VRF attachment"* in the payload schema above,
so dropping it would erase per-attachment config. The module treats it the
same way and says so in a comment: *"copy freeformConfig from have as module
is not managing it"* (lines 1436-1437). Stage 05 reads it from
`switchDetailsList` on `vrfs/switches`, which is where the module reads it too
(lines 2600 and 2714). `instanceValues` carries the controller-owned
`loopbackId`, `loopbackIpAddress` and `loopbackIpV6Address`, which the module
also copies forward from the controller rather than rebuilding (lines
1451-1470).
`MULTISITE_CONN` defaulting to the literal `{"MULTISITE_CONN":[]}` cannot wipe
real multi-site state here: the stage echoes the controller's value whenever
the key is present and falls back only when it is absent, and the module
hard-codes that same literal unconditionally in both directions anyway, when
building a VRF-Lite extension to write (lines 1703-1705) and when reading one
back (lines 2707-2709). Any `merged` run of stage 05 has already set it.
`vlan` is the one field where the stage and the module differ: the module
zeroes it before sending (`push_diff_attach` at line 5039, with
`vrf_attach.update(vlan=0)` at line 5070) while the stage sends
the VLAN it has just read from the attachments endpoint. Both are no-ops
against an already-attached switch, and sending the current value is the
narrower change of the two.

The rest of this section is the evidence for the asynchronous correlation and
the Cisco framing around it, which still stand on their own.

The pipeline's old second deploy was not a workaround for a defect. It was the
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

Note the tension this leaves unresolved, because pretending otherwise would be
worse than admitting it. Cisco's guidance says auto IFC is Nexus-only, and the
prototype list is empty - both point at no IFC existing. But that second
deploy picking up the border leaf alone, and the guide's own claim that the
extension dialog arrives pre-populated with addresses from the VRF Lite subnet
pool and the External fabric's ASN, both suggest something IFC-shaped did once
materialise for this non-Nexus peer. The controller's offered prototype and
the deployed interface state are what settle it.

The habits worth keeping from all of this generalise past one stage:

- **"No changes" is a statement about one instant, not proof the fabric is
  finished.** An idempotent pipeline reporting nothing pending means only that
  the controller had nothing pending *when it was asked*. The authoritative
  signals here are `check_sync` reporting `in_sync=True` after a run that
  actually deployed something, and a clean `08_verify_fabric.yml`.
- **Something appearing on a re-run is not drift.** Nobody touched the switch.
  The controller learned something it did not know on the previous pass.
- **Not every precondition is eventual, and a retry loop cannot tell you
  which kind you have.** The retry in stage 05 was plausible, cheap and
  wrong, and because it was there the real failure arrived two minutes late
  and looked like a timeout. Read the precondition directly and assert on it:
  a stage that says which API field is empty is worth more than one that
  waits politely for a field that is never going to fill.

## What the verification stage proves

`08_verify_fabric.yml` compares the declared model against what the controller
actually holds, and then asks the border leaf one question the controller
cannot answer. It is read-only throughout and can be re-run freely. It writes
`evidence/stage08-verification.md` and fails on a mismatch.

Seventeen checks: five switches, three VRFs, three networks, three VRF-Lite
extensions and three VRF-Lite BGP sessions.

**Fourteen of those come from the Nexus Dashboard API and need no switch
access, so they work with the VPN to `198.18.128.x` down. The three BGP
session checks are read off `DC-Service-Leaf` over SSH and do not.** When the
border leaf cannot be reached those three read `not determined`, drop out of
the total, and the stage says on screen that they were not made - so the count
is of checks actually performed, and a run with the VPN down reports 14 of 14
rather than claiming three sessions are down. `-e dc_verify_bgp_sessions=false`
skips them deliberately and reports them as skipped.

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
  re-run that silently reset what stage 05 attached: without it the VRF still
  exists, all three leaves are still attached and `DEPLOYED`, and external
  connectivity is simply gone. Putting `DC-Service-Leaf` in
  `vrf_attach_groups` did not make this check redundant - an attach group can
  name a switch but never an extension, so the model-derived attachment
  comparison cannot see it.
- **VRF-Lite BGP session** - `Established` on the border leaf, per declared
  extension. Each session gets an initial read and up to three additional
  retries, five seconds apart, stopping as soon as the declared peer is
  `Established`. The report uses the final result; a session that remains down
  after retries still fails its intent check. This is the check that separates "the controller pushed the
  extension" from "external connectivity works", and it is the only one read
  from a device rather than from the controller. `absent` means the switch
  answered and has no session to that neighbour in that VRF at all, so the
  extension never reached the running configuration; any other state means it
  did and the far end is not answering. See "Why the BGP check uses SSH" above
  for how each of those reads.

`extensionValues` is a JSON document encoded into a string field, and its
inner keys are a Nexus Dashboard implementation detail rather than a documented
contract, so the three declared values are matched as substrings of the raw
field rather than by walking a parsed structure. A schema change then costs a
false failure that is obvious from the report, instead of a check that
silently passes because a renamed key read as absent on both sides.

Reading the report:

- **`DC-Service-Leaf` now appears in the "Switches declared" column of all
  three VRF rows, as a real `DEPLOYED` attachment.** It joined
  `vrf_attach_groups` on 2026-09-27, so stage 02 attaches it and a missing
  attachment on the border leaf is a genuine "Switches missing" failure rather
  than the tolerated `NA` it used to be. Before that it was absent from the
  declared column and showed up under "Not attached" on a fabric that was
  otherwise fine. The extension keeps its own three rows regardless.
- A name under **"Switches missing"** or **"Attachments missing"** is a real
  fault: something declared did not attach.
- An attached switch in **`PENDING`** means the intent exists on the
  controller but was never pushed. Re-run `07_recalculate_and_deploy.yml`.
- **`not determined` in the BGP session table is not a fault in the fabric.**
  It means this run could not read the border leaf, and the reason the
  transport gave is printed beside it. Those rows are excluded from the count
  at the top of the report, because a check that was not made is not a check
  that passed.
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

The **legacy fabric controller API** under `/appcenter/.../rest/control/` is what
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
support"*; the 12.1.3b release also removed the SNMP requirement for IOS-XE
devices. Omitting it makes the controller use the NX-OS SNMPv3
path, which produces the timeout above.

Two further details shape how stage 04 checks its own work. The controller
returns HTTP 200 even for a candidate it cannot use, so the discovery status has
to be read rather than inferred from the response code: a successful IOS-XE
discovery reports `manageable` and carries a serial number, while the SNMPv3
fallback reports `SNMPv3 Timeout` and no serial. And the switch entry in the
second call is rebuilt key by key rather than passed through from the discovery
response, which also carries `status` and `statusReason` - outputs rather than
inputs - and omits `vdcMac`, which the add requires.

Whether the fabric already exists is read from the fabric *list* rather than
from a `GET` of the fabric itself. A `GET` of a fabric that does not exist
returns 4xx, and `dcnm_rest` turns that into a module failure with no usable
body, leaving no way to tell an absent fabric from a failed call; the list
endpoint answers 200 either way.

Stage 04 is safe to re-run: the fabric converges with `state: merged`, and the
router is discovered and added only when the fabric's switch list does not
already contain it. Skip the router with `-e
dc_external_add_edge_router=false`.

**The VRF-Lite extensions themselves** - MAIN, PROD and IOT reaching out of
DC-Service-Leaf to the edge router - are stage 05, `06_vrf_lite.yml`. They are
the one part of the build that does not come from the Nexus as Code model,
because that model cannot express them: a `vrf_attach_group` entry names a
switch and nothing else, with no key for `EXTEND: VRF_LITE`, the
sub-interface, the dot1q tag or the neighbour address. The model does the half
it can - `DC-Service-Leaf` is in the `dc_leaves` attach group, so stage 02
attaches the three VRFs to it - and stage 06 posts the extension to the
controller's attachments endpoint for the other half. `dcnm_vrf` does support
`attach[].vrf_lite[]`, but it writes only seven extension fields and so cannot
carry the sub-interface MTU or the neighbour ASN, and it hardcodes the Nexus
Jython template where this pod's IOS-XE peer needs its own. That split is the
guide's own: section 8 has two Detach/Attach sliders per VRF, one for the
attachment and one for the extension.

The intent is still declared in git, in
`inventory/group_vars/all/dc_vrf_lite.yml`. It restates only what the model
cannot hold - the interface, and one row per VRF carrying the dot1q tag, the
sub-interface address and the neighbour address, plus which switch is the
border leaf. `vrf_id` and `vlan_id` are read back out of `vrfs.nac.yaml` at
run time rather than copied, so the two files cannot disagree.

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
  runs `dcnm_vrf` with `state: replaced`, and a `replaced` want that carries
  no `vrf_lite` block against an attachment that has one takes the branch at
  `dcnm_vrf.py` lines 1544-1549 and pushes the change, clearing
  `extensionValues`. Under `merged` the same comparison returns at line 1551
  and leaves it alone. So every create run resets these extensions and stage
  05 puts them back, idempotently. Adding `DC-Service-Leaf` to
  `vrf_attach_groups` narrowed this - stage 02 now maintains the attachment
  and only clears the extension - but did not remove it.
- **Stage 05 runs after stage 04**, because the extension hangs off an
  inter-fabric connection between the border leaf and a device in the
  External fabric, and stage 04 is what creates that fabric and adds the
  router to it. It does *not* need to run after stage 06: the module's own
  TEST.4 adds an extension to a switch with no attachment and nothing
  deployed. What it does need is for the IFC to exist, which is a controller
  precondition rather than an ordering one - see [What stage 06 needs from
  the controller](#what-stage-06-needs-from-the-controller).

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
