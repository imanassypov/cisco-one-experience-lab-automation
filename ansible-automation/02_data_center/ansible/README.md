# PseudoCo DC fabric - Nexus as Code pipeline

This pipeline builds the VXLAN EVPN data center fabric `Pseudoco-DC1` on Cisco
Nexus Dashboard 4.2.1.10, from a declarative YAML model held in git.

It automates sections 4 through 8 of the student guide's **Nexus Dashboard - DC Fabric
Deployment**. Everything the guide has you click through in the Nexus Dashboard
UI, this pipeline declares instead. The one thing it does not carry is the edge
router's own side of the VRF-Lite handoff, which Nexus Dashboard cannot write -
see [Scope](#scope).

## External connectivity: L3Outs

Each of the three VRFs (MAIN, PROD and IOT) leaves the fabric through one
**L3Out**. An L3Out is a Nexus Dashboard object that pairs a dot1q
sub-interface on the border leaf `DC-Service-Leaf` with an eBGP session to the
edge router, inside that VRF. Stage 04 builds the inter-fabric link the L3Outs
sit on, stage 05 creates and attaches the three L3Outs, and stage 06 deploys
them. In the UI they are under **Manage > Routing Policies > L3Outs**; the VRF
attachments themselves show Extend `NONE`, which is expected.

Stages 03, 04, 05, 07 and 08 use the `cisco.nd` collection, pinned to a
pre-release commit (`671e596`). The script-server bootstrap installs it into
this folder's `collections/`, which `ansible.cfg` searches first. On a server
bootstrapped before that, install it by hand from this `ansible/` folder:

```bash
ansible-galaxy collection install -r collections/requirements-cisco-nd.yml -p collections --no-deps --force
pip install -r ../../requirements.txt
```

Comments in the playbooks and data model are kept short for students.
Implementation detail for maintainers and coding agents is in
[`../AGENTS.md`](../AGENTS.md).

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
| 8. Create VRF-Lite Connections to External | Three L3Outs out of DC-Service-Leaf on `Ethernet1/8`, one per VRF, each with its dot1q tag, sub-interface address and BGP neighbour. The router's side of those links is pre-built by the pod and stays outside the pipeline |

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
  deploy stage that changes running configuration.

### Network as Code roles and their fabric outcomes

These three Network as Code roles turn the declared model into a checked,
staged, and deployed data center fabric. Each has a distinct part in that path:

| Role | Called by | What it does |
|---|---|---|
| `cisco.nac_dc_vxlan.validate` | 02 and 06, as the first role of the play | Reads every `*.nac.yaml` out of `playbooks/host_vars/<fabric>/` and checks it against the collection's schema and rule set. Touches neither controller nor switch. A model error fails here instead of half way through a build |
| `cisco.nac_dc_vxlan.dtc.create` | 02 | Builds the fabric intent on the controller; see the sequence below |
| `cisco.nac_dc_vxlan.dtc.deploy` | 06 | The UI's Recalculate and Deploy. The only thing in this pipeline that changes running configuration |

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

Stages 03, 04, 05, 07 and 08 call **no** Nexus as Code role. They use `cisco.nd`
modules, and `nd_rest` where no module covers the call, because what they
declare has no key in the data model -
see [Settings Nexus as Code cannot
express](#settings-nexus-as-code-cannot-express) and [Scope](#scope).

### The collection pins, and why each one is there

`collections/requirements.yml` pins seven collections. Three are Cisco's, and
each is pinned for a different reason.

| Collection | Pin | Why |
|---|---|---|
| `cisco.nac_dc_vxlan` | 0.9.0 | The declarative layer. It renders `cisco.dcnm` module calls from the `host_vars` data model |
| `cisco.dcnm` | 3.13.0 | The modules underneath. **The floor matters**: Nexus Dashboard 4.2.1 support landed in `cisco.dcnm` 3.12.1 and 3.13.0 adds 4.3.1, and `cisco.nac_dc_vxlan` 0.9.0 declares `cisco.dcnm` >= 3.13.0 as a hard dependency. Do not pin it lower |
| `cisco.nxos` | 10.2.0 | Used by **two stages only** - `00_discover_dc_switch_serials.yml`, which SSHes to the switches to read their serial numbers, and the BGP session check in `07_verify_fabric.yml`, which reads the border leaf. Every other stage talks to Nexus Dashboard over `httpapi` and needs none of it |

The four supporting collections - `ansible.netcommon` 7.1.0, `ansible.utils`
5.1.2, `ansible.posix` 2.0.0 and `community.general` 10.1.0 - match the
versions in the upstream `netascode/ansible-dc-vxlan-example` requirements and
are pinned alongside the Cisco three so the dependency resolver cannot
substitute its own choices. All four declare `requires_ansible ">=2.15.0"`, so
they are compatible with the `ansible-core` 2.17.14 pinned in
`ansible-automation/requirements.txt`.

Raising a pin here alone has no effect on a pod. See [Versions](#versions).

`cisco.nd` is not in that file. It is pinned separately, to git commit
`671e596`, in `collections/requirements-cisco-nd.yml`, and installed into this
track's `collections/` folder rather than the shared venv - see [External
connectivity: L3Outs](#external-connectivity-l3outs).

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
`cisco.nxos 10.2.0`. The same bootstrap run installs `cisco.nd` into
`collections/ansible_collections/cisco/nd/` under this folder (git-ignored);
if that directory is missing, use the manual install in [External
connectivity: L3Outs](#external-connectivity-l3outs).

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
| `01_dc_deploy.yml` | Orchestrator. Runs 02 to 07 in order, each as its own `ansible-playbook` process, and stops at the first failure. Logs every stage under `evidence/dc-deploy-<run>/` |
| `02_create_dc_fabric.yml` | Creates the whole intent on the controller: fabric, switch import, roles, vPC pair, port-channels, VRFs, networks |
| `03_fabric_advanced_settings.yml` | Applies the settings Nexus as Code cannot express, with `nd_manage_fabric_ibgp_vxlan`. See [Settings Nexus as Code cannot express](#settings-nexus-as-code-cannot-express) |
| `04_external_fabric.yml` | Creates the External connectivity fabric in Monitor Mode, adds the IOS-XE edge router to it, and builds the eBGP VRF-Lite inter-fabric link the L3Outs sit on |
| `05_l3out.yml` | Creates the three L3Outs declared in `inventory/group_vars/all/dc_vrf_lite.yml` and attaches them. Stages intent only |
| `06_recalculate_and_deploy.yml` | "Recalculate and Deploy". Pushes the fabric and the L3Outs, and is the **only** stage that changes running configuration |
| `07_verify_fabric.yml` | Read-only check against the declared model, over the Nexus Dashboard API and over SSH to the border leaf with pyATS/Genie. Writes timestamped Markdown and HTML reports and the raw L3Out collection in `evidence/` |
| `08_cleanup.yml` | Destructive teardown: L3Outs, overlays, inter-fabric link, switches, both fabrics, then the sub-interfaces on the border leaf. Needs `-e dc_cleanup_confirm=CLEANUP_OK` |

The numbering tells you who runs a playbook. Stages 02 to 07 are contiguous
because they are exactly what `01_dc_deploy.yml` runs. Stage 00 sits below
that range because it is the prerequisite you run yourself, once per pod, and
08 sits above it because it is deliberately outside the orchestrated run.

Stages 03 and 04 run first because their settings and the External fabric are
inputs to the inter-fabric link, and stage 04 is what creates that link.
Stage 05 builds the L3Outs on it. Stage 06 then deploys the fabric, the
three dot1q sub-interfaces and their BGP neighbours in one pass.

Each stage can still be run on its own. Extra variables for an orchestrated
run go in one dictionary that is forwarded to every stage:
`-e '{"dc_deploy_extra_vars": {"dc_verify_fail_on_mismatch": false}}'`.

Useful overrides:

- `--tags cr_manage_fabric` narrows stage 02 to the fabric object alone, which
  is the guide's "Create a VXLAN Fabric" step on its own
- `-e dc_verify_fail_on_mismatch=false` has stage 07 write its report without
  failing the run
- `-e dc_verify_bgp_sessions=false` has stage 07 skip the SSH read of the
  border leaf (BGP sessions and sub-interfaces), and compare only what the
  controller knows

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
| `inventory/group_vars/all/dc_advanced_settings.yml` | Non-VRF fabric properties: license tier, telemetry, and location. Applied by stage 03 |
| `inventory/group_vars/all/dc_external_settings.yml` | The whole External fabric: ASN and Monitor Mode, and the edge router added to it. Applied by stage 04 |
| `inventory/group_vars/all/dc_vrf_lite.yml` | All VRF-Lite intent: fabric mode and subnet pool, inter-fabric link, sub-interface MTU, and the three per-VRF L3Outs. Read by stages 03, 04, 05, 07 and 08 |
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
no key for what they declare, so stages 03, 04 and 05 read them and pass them
to `cisco.nd` modules. The keys in (b) are therefore spelled the way those
**module options** are spelled - `vrf_lite_auto_config`, `monitored_mode`,
`license_tier` - and are passed through unchanged, so a typo fails Ansible's
argument check.

One consequence worth stating plainly: a key in the wrong half is not a style
problem. A module option put in (a) is rejected by the validator; a
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
          - hostname: DC-Service-Leaf   # the border leaf, where the L3Outs leave the fabric
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

`dc_advanced_settings.yml` holds the non-VRF Nexus Dashboard fabric
properties. Stage 03 applies them with `cisco.nd.nd_manage_fabric_ibgp_vxlan`,
in the same call as the VRF-Lite fabric settings:

```yaml
dc_advanced_nd_fabric_settings:
  license_tier: premier
  telemetry_collection: false
  location:                              # both keys, or the other reads zero
    latitude: 37.3382
    longitude: -121.8863
```

`dc_vrf_lite.yml` is the single source for VRF-Lite intent. It contains the
fabric-wide settings (applied in stage 03), the explicitly addressed
inter-fabric link (stage 04), and one row per VRF that stage 05 turns into an
L3Out:

```yaml
dc_vrf_lite_fabric_settings:             # applied in stage 03
  vrf_lite_auto_config: manual
  vrf_lite_subnet_range: 192.168.252.0/24
  vrf_lite_subnet_target_mask: 30

dc_vrf_lite_border_leaf: DC-Service-Leaf
dc_vrf_lite_interface: Ethernet1/8       # detected over CDP, declared for determinism
dc_vrf_lite_peer_interface: GigabitEthernet2

dc_vrf_lite_ifc:                         # the inter-fabric link, stage 04
  src_ip_address_mask: 192.168.252.1/30
  dst_ip_address: 192.168.252.2
  link_mtu: 1500

dc_vrf_lite_mtu: 1500                    # the sub-interfaces; never above link_mtu

dc_vrf_lite_extensions:
  - name: PROD-External                  # the L3Out's name on the controller
    vrf: PROD
    peer_vrf: PROD
    dot1q: 2                             # becomes Ethernet1/8.2
    ipv4_addr: 192.168.252.5/30          # the leaf's sub-interface
    neighbor_ipv4: 192.168.252.6         # the router's side, pre-built by the pod
```

`vrf_id` and `vlan_id` are deliberately **not** restated there. Stage 05 reads
`vrfs.nac.yaml` at run time and refuses to run if a row names a VRF the model
does not declare or does not attach to the border leaf, so the two files
cannot disagree.

The External fabric has no Nexus as Code model either, which is why it appears
only in (b). The collection's create role cannot build it: the role
always runs a config-save after its inventory step, and on a fabric with no
switches the controller returns HTTP 500 `Fabric External cannot be deployed
without any switches`. The fabric also holds no VRFs, networks or interfaces,
so there is nothing for the collection to express. Stage 04 creates it with
`cisco.nd.nd_manage_fabric_external` and adds the edge router with
`cisco.nd.nd_manage_switches`, both from `dc_external_settings.yml`.

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
- **`DC-Service-Leaf` is in `vrf_attach_groups`, and the handoff still is
  not.** An entry there can name a switch and nothing else, so the model can
  attach the three VRFs to the border leaf but can never carry the
  sub-interface, dot1q tag and BGP neighbour that make them reachable from
  outside. That is a two-step job, which is how the guide does it too: section
  8 attaches the VRF and then adds the external connection. So the model owns
  the attachment and stage 05 adds an L3Out per VRF on top. Because an L3Out
  is a separate controller object rather than part of the VRF attachment,
  re-running stage 02 does not remove it, and there is no ordering dependency
  between stages 02 and 05.

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
collections/requirements.yml       the released collections
collections/requirements-cisco-nd.yml  pre-release cisco.nd; installed into
                                       collections/ansible_collections/ (gitignored)
inventory/
  static_inventory.yml            one host per fabric, plus the switch group
  group_vars/all/dc_switches.yml  the switch table
  group_vars/all/dc_advanced_settings.yml  non-VRF fabric-object properties
  group_vars/all/dc_external_settings.yml  the External fabric
  group_vars/all/dc_vrf_lite.yml  all VRF-Lite fabric, link and L3Out intent
  group_vars/nd/               controller transport and credentials
  group_vars/dc_fabric_switches/  SSH to the switches; stages 00, 07 and 08
playbooks/
  00_discover_dc_switch_serials.yml ... 08_cleanup.yml
  host_vars/Pseudoco-DC1/*.nac.yaml   the data model
  tasks/                            L3Out builder and stage runner
  templates/stage07-verification.{md,html}.j2
evidence/                         written by stage 07, gitignored
```

`host_vars/` lives under `playbooks/`, not under `inventory/`, which is
unusual. The collection's validate role passes the model path as
`{{ playbook_dir }}/host_vars/{{ inventory_hostname }}` in a task-level
variable with no override, so the model has to sit beside the playbooks.
`group_vars/` is plain Ansible and lives where you would expect.

## How it comes together: PROD, end to end

Follow one object through every layer. `PROD` will do: like each VRF, it
appears in both halves of the definition.

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

**5. Handed off.** Stage 05 turns the PROD row of `dc_vrf_lite.yml` into the
L3Out `PROD-External`: sub-interface `Ethernet1/8.2`, dot1q `2`,
`192.168.252.5/30`, eBGP neighbour `192.168.252.6` in AS 65531, MTU 1500,
and a default route advertised to the router. It creates the L3Out on the
inter-fabric link stage 04 built, then attaches it. Still nothing on a switch.

**6. Deployed.** Stage 06 performs the one "Recalculate and Deploy". PROD's
VRF and SVIs land on all three leaves; on the border leaf the same push carries
the parent `Ethernet1/8`, the `.2` sub-interface and the eBGP neighbour in VRF
PROD, because step 5 staged them before this ran.

**7. Verified.** Stage 07 reads `vrfs.nac.yaml` again - the same file, not a
copy - and compares it against the controller: PROD exists with VNI 50001, is
attached to all three declared leaves, and every attachment reads `DEPLOYED`.
It then checks that `PROD-External` exists, is attached and matches the
declared row. Those are three of the fourteen controller checks. When the
border leaf answers over SSH, it also reads `Ethernet1/8.2` and the PROD BGP
session off the switch - six device checks across the three VRFs, for twenty
checks total.

Change `vrf_id` in step 1 and re-run: steps 2 through 7 all follow, and no
other file needs touching. That is the whole argument for writing the fabric
down.

## Why serial discovery is a separate stage

Nexus as Code identifies a switch by serial number and validates that every
switch in the model has one before anything reaches the controller. The
controller cannot tell you a serial until the switch is already in the fabric,
so the serial has to come from somewhere else first.

Stage 00 gets it from the switches. It SSHes to each management address in
`dc_switches.yml` and reads the chassis serial from `show inventory`. This
is the serial the controller uses; `show version` reports a different number
on Nexus 9000v. Because it never asks the controller, it has no ordering
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

The guide's fabric settings include a Resources tab and a few fabric
properties that `cisco.nac_dc_vxlan` 0.9.0 has no data model key for. Stage 03
closes that gap by writing them straight to the controller with
`cisco.nd.nd_manage_fabric_ibgp_vxlan`.

The VRF-Lite settings are declared in
`inventory/group_vars/all/dc_vrf_lite.yml`; the remaining fabric properties are
in `inventory/group_vars/all/dc_advanced_settings.yml`. Stage 03 holds no
values of its own.

| Setting | Module option | Value | Source |
|---|---|---|---|
| VRF Lite Deployment | `vrf_lite_auto_config` | `manual` | `dc_vrf_lite.yml` |
| Auto Deploy for Peer | `auto_symmetric_vrf_lite` | Not sent under `manual` | Intentionally absent |
| Auto Allocation of Unique IP on VRF Extension | `auto_unique_vrf_lite_ip_prefix` | Not sent under `manual` | Intentionally absent |
| VRF Lite Subnet IP Range | `vrf_lite_subnet_range` | `192.168.252.0/24` | `dc_vrf_lite.yml` |
| VRF Lite Subnet Mask | `vrf_lite_subnet_target_mask` | `30` | `dc_vrf_lite.yml` |
| License Tier | `license_tier` | `premier` | `dc_advanced_settings.yml` |
| Telemetry | `telemetry_collection` | `false` | `dc_advanced_settings.yml` |
| Location | `location` | `37.3382, -121.8863` (San Jose, California, US) | `dc_advanced_settings.yml` |

The three VRF-Lite values go under the module's `management` option; the
other three are top-level fabric properties. Stage 03 sends all six in one
call. `auto_symmetric_vrf_lite` and `auto_unique_vrf_lite_ip_prefix` are
deliberately omitted: under `manual`, the controller rejects them. Every
address is pinned in the L3Outs, so the subnet pool is only a fallback.

**Location is coordinates, because Nexus Dashboard has no field for the place
name.** There is no city, country or address key on the fabric object, in its
`management` sub-object, or among the fabric's nvPairs. The UI's location
picker geocodes what you type and keeps only the two numbers, then drops a pin
on the fabric map. So "San Jose" survives only as a comment in the data model,
which is why that comment is there. Both coordinates have to be given
together: the stage combines non-recursively, so a partial `location` would
replace the whole object and leave the other coordinate at zero.

Three things worth knowing:

- **It cannot revert what stage 02 wrote.** `state: merged` sends only the
  declared keys, and the update starts from the controller's own copy of the
  fabric, so everything Nexus as Code set is carried through untouched.
- **It runs before deploy, not after.** These are fabric parameters, which are
  inputs to the configuration the controller generates. Applied after stage
  06, they would be correct on the controller and absent from the switches
  until the next deploy.
- **A second run is a no-op.** The module compares before it writes, so
  re-running reports `changed=0`. No save or deploy is requested, and nothing
  here touches a switch.

The stage reads the fabric with `state: gathered` first and stops with a clear
message if stage 02 has not created it, because `merged` against a missing
fabric would try to create it and fail on the absent BGP ASN.

**"Add Switches without Reload" is deliberately not here.** It is the
`GRFIELD_DEBUG_FLAG` nvPair, and Nexus as Code does model it, as
`vxlan.global.ibgp.greenfield_cleanup` in `global.nac.yaml`. Two files setting
one nvPair is a drift bug waiting to happen; this stage carries only what the
model cannot express.

### The two VRF-Lite settings, as Cisco defines them

Both are on the fabric's Resources tab.

**`vrf_lite_auto_config: manual`** (`VRF_LITE_AUTOCONFIG` on the controller)
is the UI's **VRF Lite Deployment** field.
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
fixed and cannot be moved to meet the controller. Measured on 2026-09-27, the
automation tagged PROD 2, MAIN 3 and IOT 4, where the router expects PROD 2,
IOT 3 and MAIN 4. Every value has to come from the data model instead, so
stage 04 creates the IFC itself with `cisco.nd.nd_manage_links` (policy
`ebgpVrfLite`), and each L3Out in stage 05 carries its own dot1q tag and
addresses. Under `manual` the controller creates nothing of its own.

Two companion settings went with it. `AUTO_SYMMETRIC_VRF_LITE` and
`AUTO_UNIQUE_VRF_LITE_IP_PREFIX` are not merely unnecessary under `Manual` -
the controller rejects them, so they are absent from
`dc_vrf_lite.yml` rather than set to `false`.
([Nexus Dashboard - VRF Lite](https://www.cisco.com/c/en/us/td/docs/dcn/ndfc/1221/articles/ndfc-vrf-lite/vrf-lite.html))
Under `manual` no IFC is ever auto-created, which is why stage 04 builds
the one this lab needs.

The same article bounds which devices react to it: *"Autoconfiguration is
supported for the following cases: Border role in the VXLAN fabric and Edge
Router role in the connected external fabric device; Border Gateway role in
the VXLAN fabric and Edge Router role in the connected external fabric
device; Border role to another Border role directly."* In `Pseudoco-DC1`
exactly one switch holds the `border` role - `DC-Service-Leaf` - and after
stage 04 exactly one device holds `edgeRouter` - `DC-SITE11-CEDGE8Kv`. That
pairing is the whole scope of this setting here.

**`AUTO_SYMMETRIC_VRF_LITE`** is the UI's **Auto Deploy for Peer**
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

**This repository deliberately does not send `AUTO_SYMMETRIC_VRF_LITE`.**
Under `manual`, the controller rejects this setting; even outside that
restriction, two independent constraints prevent peer-side configuration:

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
  switches."* `dc_external_settings.yml` sets `monitored_mode: true` on purpose,
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
`Gi2.3` in `102` (IOT). The `peer_vrf` values in `dc_vrf_lite.yml` become
each L3Out's far-side VRF name. Nexus Dashboard requires one even though it
configures only the fabric side, and accepts the DC names; it never writes
the far side, so nothing compares them with the router's.

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
nothing for the router to peer with. Stage 05 can report success while this
is true, because it only writes intent: the L3Outs reach the switch only on
the stage 06 deploy that follows. Stage 07's controller checks can pass too;
its sub-interface and BGP checks, read off the border leaf, are what catch it.

### Why the BGP check uses SSH

**Stage 07 checks the three VRF-Lite eBGP sessions, and the sub-interfaces
they run over, by reading the border leaf over SSH. These are the only checks
in the stage that do not come from the controller.** The evidence above is why it exists: every controller-side check
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

The command is `show bgp sessions vrf <vrf>`, one per declared L3Out, from
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

## The sub-interface MTU, and why it is declared

**A sub-interface may not have a larger MTU than its parent.** If it does, the
deploy fails with `Delivery failed with message: MTU of sub-interface greater
than parent interface detected`. Both numbers are set in
`inventory/group_vars/all/dc_vrf_lite.yml`:

| Value | Where it comes from |
|---|---|
| Parent `Ethernet1/8` MTU **1500** | `dc_vrf_lite_ifc.link_mtu`, the `Link MTU` on the inter-fabric link stage 04 builds. Omitted, the link policy defaults it to 9216, so it is always set |
| Sub-interface MTU **1500** | `dc_vrf_lite_mtu`, sent on each L3Out by stage 05. Stage 05 refuses to run if it exceeds `link_mtu` |
| Router IP MTU **1500** | What `DC-SITE11-CEDGE8Kv` carries on `GigabitEthernet2` and its three dot1q sub-interfaces. Measured on the pod |

**Why the value is 1500.** The parent only sets a ceiling. What chooses the
value is the router, because a routed link only works if both ends agree on
how large an IP packet may be, and the router is pre-built and in Monitor
Mode, so Nexus Dashboard can never raise it. Anything above 1500 on our side
would be a real mismatch.

A mismatch would not show up as a dead BGP session: TCP sizes its segments
from the MSS each end advertises, so the sessions would come up and exchange
routes. Transit packets above 1500 bytes would instead be dropped silently at
the router. Stage 07 reads each sub-interface's MTU off the border leaf for
that reason.

## What the verification stage proves

`07_verify_fabric.yml` compares the declared model against what the controller
actually holds, and then asks the border leaf what the controller cannot
answer. It is read-only throughout and can be re-run freely. It writes
`evidence/stage07-verification-<UTC timestamp>.md` and a matching `.html` report,
plus the raw L3Out collection as `stage07-l3outs-<UTC timestamp>.json`,
and fails on a mismatch. Each run uses a new timestamp with microsecond precision
(for example, `20261110T143025123456Z`), preserving evidence from previous runs.

Twenty checks: five switches, three VRFs, three networks, three L3Outs, three
VRF-Lite sub-interfaces and three VRF-Lite BGP sessions.

**Fourteen of those come from the Nexus Dashboard API and need no switch
access, so they work with the VPN to `198.18.128.x` down. The six sub-interface
and BGP session checks are read off `DC-Service-Leaf` over SSH and do not.**
When the border leaf cannot be reached those rows read `not determined`, drop
out of the total, and the stage says on screen that they were not made - so the
count is of checks actually performed, and a run with the VPN down reports 14
of 14 rather than claiming the handoff is down. `-e dc_verify_bgp_sessions=false`
skips the SSH read deliberately; `-e dc_verify_subinterfaces=false` skips only
the sub-interface read.

- **Switch** - present in the fabric inventory at its declared management
  address, holding its declared role.
- **VRF** - exists with the declared VNI, attached to every switch in its
  `vrf_attach_group`, and every attachment `DEPLOYED`.
- **Network** - exists in the declared VRF with the declared anycast gateway,
  each declared port-channel attached on every switch it was declared on, and
  every attachment `DEPLOYED`.
- **L3Out** - exists under its declared name, is attached, and matches the
  declared VRF, peer VRF, interface, dot1q tag, address, neighbour, MTU and
  peer ASN. The stage builds the declared L3Outs with the same task file stage
  05 uses and compares them with `nd_manage_l3out` in check mode; the attach
  state comes from the raw L3Out collection, the only place it is reported.
  Putting `DC-Service-Leaf` in `vrf_attach_groups` does not make this check
  redundant - an attach group can name a switch but never an L3Out, so the
  model-derived attachment comparison cannot see it.
- **VRF-Lite sub-interface** - `Ethernet1/8.2`, `.3` and `.4` read off the
  border leaf one `show interface` at a time and parsed with pyATS/Genie: up,
  with the declared dot1q tag, address and MTU. This is the check that catches
  the controller reading `DEPLOYED` while the switch disagrees.
- **VRF-Lite BGP session** - `Established` on the border leaf, per declared
  L3Out. Each session gets an initial read and up to three additional
  retries, five seconds apart, stopping as soon as the declared peer is
  `Established`. The report uses the final result; a session that remains down
  after retries still fails its intent check. This is the check that separates
  "the controller pushed the L3Out" from "external connectivity works".
  `absent` means the switch answered and has no session to that neighbour in
  that VRF at all, so the L3Out never reached the running configuration; any
  other state means it did and the far end is not answering. See "Why the BGP
  check uses SSH" above for how each of those reads.

Reading the report:

- **`DC-Service-Leaf` now appears in the "Switches declared" column of all
  three VRF rows, as a real `DEPLOYED` attachment.** It joined
  `vrf_attach_groups` on 2026-09-27, so stage 02 attaches it and a missing
  attachment on the border leaf is a genuine "Switches missing" failure rather
  than the tolerated `NA` it used to be. Before that it was absent from the
  declared column and showed up under "Not attached" on a fabric that was
  otherwise fine. The L3Outs keep their own three rows regardless.
- A name under **"Switches missing"** or **"Attachments missing"** is a real
  fault: something declared did not attach.
- An attached switch in **`PENDING`** means the intent exists on the
  controller but was never pushed. Re-run `06_recalculate_and_deploy.yml`.
- **`not determined` in the BGP session or sub-interface table is not a fault
  in the fabric.**
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
the three per-VRF L3Outs are stage 05.

**What stays manual is the edge router's side of the handoff**, and that is a
platform boundary rather than a gap in the automation. The External fabric is
created with `monitored_mode: true` (`IS_READ_ONLY` on the controller), and
Cisco is explicit that *"when an external fabric is set to Fabric Monitor
Mode Only, you cannot deploy configurations on the switches"*. Nexus Dashboard therefore never writes the
matching sub-interfaces and BGP neighbours on `DC-SITE11-CEDGE8Kv`; in this
lab they are pre-built by the pod. That is also why the addresses in
`dc_vrf_lite.yml` are pinned instead of being allocated from
`vrf_lite_subnet_range` by the controller: if the leaf picked its own, they
would not match the far end.

**The External fabric** is built by stage 04, in Monitor Mode, with ASN 65531.
Monitor Mode is not something the Nexus as Code model can express, and the
collection does not merely omit it: `dc_external_fabric_general.j2` ties
`IS_READ_ONLY` to the bootstrap setting instead, emitting `false` when
bootstrap is off and `""` when it is on. Neither can produce `true`, so
applying a Nexus as Code model to this fabric would take it *out* of Monitor
Mode. Stage 04 therefore builds the fabric with
`cisco.nd.nd_manage_fabric_external` and sets Monitor Mode in the same call,
so the fabric is never briefly writable.

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

The **ND 4.x manage API** does support it, and that is the API
`cisco.nd.nd_manage_switches` drives. It makes the same two calls the UI makes
behind its Discover Switches and Add Switches steps: a shallow discovery of
`198.18.133.14`, then an add of the device it found. Discovery supplies the
model, software version and serial number, which are pod-specific, so nothing
here declares them. Four details of how stage 04 calls it:

- **`platform_type: ios-xe`.** This is the API form of the UI's `Device type:
  IOS XE` dropdown and its `CSR/CAT8K/ASR/CAT9K` sub-selector. It selects the
  discovery protocol rather than labelling the device. Cisco's External
  Connectivity Network guide states that *"Cisco CSR 1000v is discovered using
  SSH ... does not need SNMP support"*; the 12.1.3b release also removed the
  SNMP requirement for IOS-XE devices. `nx-os` would take the SNMPv3 path,
  which produces the timeout above.
- **Save and deploy are off.** The module saves and deploys by default, so
  stage 04 sets both `config_actions` to false. Monitor Mode is the second
  guard.
- **`preserve_config: true`**, since the fabric is in Monitor Mode and the
  router's running configuration belongs to the lab. No role is sent: the
  controller assigns `edgeRouter` itself.
- **The serial is cross-checked.** The module's output carries no serial, so
  the stage reads the External fabric's switch list with `nd_rest` and asserts
  that the router there is the device stage 00 read.

Stage 04 is safe to re-run: the fabric, the router and the link all converge
with `state: merged`. Skip the router, and
with it the link, with `-e dc_external_add_edge_router=false`.

**The VRF-Lite handoffs themselves** - MAIN, PROD and IOT reaching out of
DC-Service-Leaf to the edge router - are stage 05, `05_l3out.yml`, built as
three Nexus Dashboard L3Outs with `cisco.nd.nd_manage_l3out`. They are the one
part of the build that does not come from the Nexus as Code model, because
that model cannot express them: a `vrf_attach_group` entry names a switch and
nothing else, with no key for the sub-interface, the dot1q tag or the
neighbour address. The model does the half it can - `DC-Service-Leaf` is in
the `dc_leaves` attach group, so stage 02 attaches the three VRFs to it - and
the L3Outs carry the other half. That split is the guide's own: section 8
attaches the VRF to the border leaf and then adds the external connection.

The intent is still declared in git, in
`inventory/group_vars/all/dc_vrf_lite.yml`. It restates only what the model
cannot hold - the interface, and one row per VRF carrying the L3Out name, the
dot1q tag, the sub-interface address and the neighbour address, plus which
switch is the border leaf. Stage 05 checks every row against `vrfs.nac.yaml`
at run time rather than copying VRF values, so the two files cannot disagree.

| VRF | L3Out | Sub-interface | dot1q | Leaf address | Neighbour (AS 65531) |
|---|---|---|---|---|---|
| PROD | `PROD-External` | `Ethernet1/8.2` | 2 | `192.168.252.5/30` | `192.168.252.6` |
| IOT | `IOT-External` | `Ethernet1/8.3` | 3 | `192.168.252.9/30` | `192.168.252.10` |
| MAIN | `MAIN-External` | `Ethernet1/8.4` | 4 | `192.168.252.13/30` | `192.168.252.14` |

Each L3Out uses MTU 1500, applies `route-map extcon-rmap-filter out` (from the
L3Out template), and advertises a default route, `network 0.0.0.0/0`, into its
VRF's BGP session (`advertise_default_route`).

All three ride `Ethernet1/8`, which is not a choice - Nexus Dashboard detects
it over CDP, and the pending config it stages for the deploy names both ends:
`description connected-to-DC-SITE11-CEDGE8Kv-GigabitEthernet2`. The addresses
are pinned rather than allocated by the controller for the reason the guide
gives beside the same fields: the router's side of these links is pre-built by
the pod and the External fabric is in Monitor Mode, so if the leaf allocated
its own addresses they would not match the far end.

**Stage 05 stages the L3Outs; it does not deploy them.** Creating and
attaching an L3Out writes intent to the controller and touches no switch,
which is what stages 02, 03 and 04 do, so it belongs on that side of the line.
Stage 05 attaches only the L3Outs that are not already attached, so a
converged run reports no change. Stage 06 is the only stage that changes
running configuration, and because the L3Outs are already staged when it runs,
one Recalculate and Deploy pushes the parent interface, the three
sub-interfaces and their BGP neighbours together. The guide reaches the same
place by deploying, editing each VRF and deploying again - an artefact of
driving the controller through a UI one dialog at a time, not something the
pipeline has to copy.

One ordering constraint, enforced by `01_dc_deploy.yml`: **stage 05 runs after
stage 04**, because each L3Out sits on the inter-fabric link between the
border leaf and the edge router, and stage 04 is what creates the External
fabric, adds the router and builds that link. Stage 05 reads the link first
and stops with a clear message if it is missing. There is no ordering
dependency on stage 02: an L3Out is its own controller object, so re-running
stage 02 leaves it in place.

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

`cisco.nd` is pinned on its own, to commit `671e596` of the `develop` branch
of `CiscoDevNet/ansible-nd`, in `collections/requirements-cisco-nd.yml`. It
has no Galaxy release at that level yet, so the bootstrap installs it from git
into this track's `collections/` folder (the `ansible_collections/` subfolder
is git-ignored), where `ansible.cfg` finds it before any other copy. Its
Python dependencies, `pydantic` and `jsonpath-ng`, are pinned in
`ansible-automation/requirements.txt`. Moving to a newer `cisco.nd` means
changing that one file and re-running the bootstrap, or the manual install in
[External connectivity: L3Outs](#external-connectivity-l3outs).
