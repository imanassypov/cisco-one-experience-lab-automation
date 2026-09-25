# PseudoCo DC fabric — Nexus as Code pipeline

Automates the **NDFC - DC Fabric Deployment** section of the student guide: the
VXLAN EVPN fabric `Pseudoco-DC1` on Nexus Dashboard 4.2.1.10, its five
switches, the vPC pair, the server port-channels, and the MAIN / PROD / IOT
VRFs and networks.

Built on [Cisco Nexus as Code](https://netascode.cisco.com/docs/data_models/vxlan/overview/)
(`cisco.nac_dc_vxlan`), which is a declarative layer over `cisco.dcnm`. You
describe the fabric you want in YAML under `playbooks/host_vars/`; the collection works
out the API calls.

## Before you run anything

Everything runs on the Kali script server, inside the `~/venv` that
`00_scriptserver_bootstrap` builds. Two things have to be in place first.

**1. The collections.** This pipeline needs `cisco.nac_dc_vxlan`, `cisco.dcnm`
and `cisco.nxos`, which are newer than the campus ones — if your `~/venv` was
built before the DC track was added, they are not there. Bring the checkout
forward and re-run the bootstrap, which is what installs them:

```bash
cd ~/cisco-one-experience-lab-automation
git pull
cd ansible-automation/00_scriptserver_bootstrap
ansible-playbook playbooks/01_bootstrap_script_server.yml
```

If you only want the collections, without the apt and venv work the bootstrap
also does:

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/02_data_center/nac_vxlan/ansible
ansible-galaxy collection install -r collections/requirements.yml --force
```

`--force` is not optional. Without it `ansible-galaxy` silently skips any
collection already present at any version, so an upgrade appears to succeed
and never happens — that is how the campus `cisco.catalystcenter` bump went
unapplied for weeks. Expect the install to be slow or to need a retry; the
path to `galaxy.ansible.com` over the dCloud VPN drops intermittently.

Confirm before moving on:

```bash
ansible-galaxy collection list | grep -E 'nac_dc_vxlan|dcnm|nxos'
```

You want `cisco.dcnm 3.13.0`, `cisco.nac_dc_vxlan 0.9.0` and
`cisco.nxos 10.2.0`.

**2. The External fabric.** In this lab it is a manual prerequisite, built in
Nexus Dashboard with Monitor Mode on and the IOS-XE edge router discovered
into it, before this pipeline runs. See
[Coverage, and what is left to do](#coverage-and-what-is-left-to-do) for why
the pipeline cannot do it.

## Running it

Run from **this directory** — the one holding `ansible.cfg`, not from
`playbooks/`. The relative paths in `ansible.cfg` that reach the vault and the
vars plugin are resolved against the working directory, so running from
anywhere else breaks authentication:

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/02_data_center/nac_vxlan/ansible
ansible-playbook playbooks/00_discover_dc_switch_serials.yml   # once, first
ansible-playbook playbooks/01_dc_deploy.yml
```

**Run the discovery stage first.** It reads a serial number off each switch and
writes the switch half of the data model from them, so nothing else here has a
model to work with until it has run once. It is not part of the orchestrator,
because it reaches the switches over SSH rather than driving Nexus Dashboard,
and because it only needs running again when the pod hardware or the switch
table changes. Stage 03 refuses to start until the serials are in the data
model — see "Why serial discovery is its own stage" below.

| Playbook | What it does |
|---|---|
| `playbooks/00_discover_dc_switch_serials.yml` | SSHes to each switch, reads its serial, and generates `playbooks/host_vars/Pseudoco-DC1/topology_switches.nac.yaml` from the tracked `.example`. Read-only against the switches. **Run this first.** Not in the orchestrator |
| `playbooks/01_dc_deploy.yml` | Orchestrator. Imports 02, 03, 04 and 05, in that order |
| `playbooks/02_fabric.yml` | Ensures the fabric object exists. It runs the same create role as 03, so once stage 00 has generated the switch model this stage imports the switches too — its inventory step sits with no output for several minutes while Nexus Dashboard discovers them. `--tags cr_manage_fabric` holds it to the fabric object |
| `playbooks/03_create.yml` | Creates the full intent on the controller. Converges whatever 02 left, and does the switch import itself if you run it on its own |
| `playbooks/04_deploy.yml` | Pushes that intent to the switches |
| `playbooks/05_verify_fabric.yml` | Nexus Dashboard API verification, writes `evidence/` |
| `playbooks/06_remove.yml` | Destructive prune. Not in `01`. Needs `-e dc_remove_confirm=REMOVE_OK` |
| `playbooks/07_external_fabric.yml` | Creates the External fabric **only if it is absent**. Not in `01` — different inventory host, and in this lab the fabric is a manual prerequisite |

The numbers are not just an ordering, they tell you who runs the playbook.
Stages 02 to 05 are contiguous because they are exactly what
`01_dc_deploy.yml` imports, in the order it imports them; 06 and 07 sit above
that range because they are deliberately outside the orchestrated run, and 00
sits below it because it is the prerequisite you run yourself, once per pod,
before the pipeline. So a plain `ansible-playbook playbooks/01_dc_deploy.yml` touches
everything numbered 02 to 05 and nothing else.

Useful overrides:

- `-e dc_verify_fail_on_mismatch=false` — stage 05 reports without failing
- `--tags cr_manage_fabric` — narrows a create run to the fabric object only

## Layout

```
ansible.cfg
collections/requirements.yml
inventory/
  static_inventory.yml            one host per FABRIC, plus the switch group
  group_vars/all/dc_switches.yml  switches, IPs, roles, port-channels
  group_vars/nd/connection.yml    httpapi transport, vault-sourced credentials,
                                  and the 1000s persistent-connection timeouts
  group_vars/nd/nd.yml            remove-role delete-mode flags, all false
  group_vars/dc_fabric_switches/connection.yml
                                  SSH to the switches; stage 00 only
playbooks/
  00_discover_dc_switch_serials.yml … 07_external_fabric.yml
  host_vars/Pseudoco-DC1/*.nac.yaml   the Nexus as Code data model
  host_vars/External/global.nac.yaml
  templates/
evidence/                         written by stage 05, gitignored
```

This mirrors `01_campus/evpn/ansible` with one forced exception: **`host_vars/`
lives under `playbooks/`, not under `inventory/`.** That is not a style choice.
`roles/validate/tasks/sub_main.yml` in `cisco.nac_dc_vxlan` passes the data
model path as a task-level variable:

```yaml
data_path: "{{ playbook_dir }}/host_vars/{{ inventory_hostname }}"
```

There is no override for it — task-level vars beat everything except `-e`, so
the data model has to sit beside the playbooks. `group_vars/` is plain Ansible
and the collection has no say in it, so that does live under `inventory/`
where it belongs.

`playbooks/host_vars/Pseudoco-DC1/topology_switches.nac.yaml` is **generated by
stage 00 and gitignored**. `topology_switches.nac.yaml.example` is the tracked
shape reference it is generated from: stage 00 copies that file and substitutes
each switch's discovered serial number and its declared role. Do not edit the
generated copy — every stage 00 run overwrites it without asking.

Credentials come from the vault-encrypted `Lab Topology/lab_access.yml` via the
repo's `plugins/vars/lab_access.py` vars plugin, exactly as the campus EVPN
collection does. Nothing in this tree contains a password, and nothing here
should ever acquire one.

## Why serial discovery is its own stage, and why it generates the model

Nexus as Code identifies a switch by `serial_number`, not by hostname or
management IP, and it is strict about it. Rule 301 in the validate role walks
every entry in `vxlan.topology.switches` and fails the run if any of them
lacks a serial, before anything reaches Nexus Dashboard.

There is an awkwardness underneath that. The import itself does not use the
serial — `fabric_inventory.j2` imports each switch by `seed_ip` with
`max_hops: 0`, and `serial_number` appears there only in the POAP blocks. So
the collection insists on a value it does not need for the one operation that
could discover it, and Nexus Dashboard cannot tell you a serial until the
switch is already in the fabric.

`playbooks/00_discover_dc_switch_serials.yml` sidesteps that by not asking
Nexus Dashboard at all. It SSHes to each management address in the
`dc_switches` table and runs `cisco.nxos.nxos_facts`, whose default
`gather_subset: min` reads `show version` and parses the Processor Board ID
into `ansible_net_serialnum`.

Two things follow from that, and they are the reason this is stage 00:

- **No ordering constraint.** Nothing has to exist in Nexus Dashboard first.
  An earlier version of this stage used the controller's CDP crawl
  (`.../inventory/test-reachability`), which is fabric-scoped, and that is
  the only reason `02_fabric.yml` had to run before it.
- **It needs the switch path up.** Every other stage here reaches only the
  Nexus Dashboard API, so this is the one that will fail when SSH to
  `198.18.128.x` is unavailable.

The switch list is not repeated in `static_inventory.yml`. The group
`dc_fabric_switches` is declared there empty and populated at run time with
`add_host` from `dc_switches`, so there is one source of truth for names and
addresses. Its connection settings live in
`inventory/group_vars/dc_fabric_switches/connection.yml`.

**It writes the data model, not just a table.** Once every declared switch has
answered, the stage copies `topology_switches.nac.yaml.example` over
`topology_switches.nac.yaml` and substitutes, for each switch, the serial it
has just read and the role declared in
`inventory/group_vars/all/dc_switches.yml`. Everything else in the example
survives verbatim, because the substitution rewrites only those two values:
the comments, the vPC IDs and the port-channel members are copied across
exactly as they are written. The stage still prints the switch, management IP,
role and serial table as well, so you can see what it found on each box.

That generated file is pure build output, and the stage treats it as such.
Every run overwrites it silently — no backup, no confirmation, no refusal if
it is already there — so anything you type into it is lost the next time you
run stage 00, and its leading comment block is swapped for a generated-file
header that says exactly that. To change the model, edit one of its two
sources and run the stage again: the `.example` for the *shape* of the fabric,
meaning which switches exist and what port-channels they carry, and
`dc_switches.yml` for the switch *table*, meaning names, management addresses
and roles. The role is taken from the table rather than from the example
because that table is the single source of truth for the switch list, and
substituting it is what stops the generated model quietly drifting away from
it.

The two sources have to agree on the switch names. The substitution is
anchored on each `- name: <switch>` line rather than on list position, so
reordering either file is harmless, but a switch spelled differently in the
two files never receives its serial.

**A name mismatch is the failure this stage has to guard against, and guarding
against it is what makes the generator worth trusting.** Rule 301 only tests that `serial_number` is
non-empty. A leftover placeholder, or a real serial attached to the wrong
switch, therefore passes validation cleanly and fails much later inside the
create role, with a message that points at neither the serial nor the file.
Generating the model is only an improvement if its output is right every time,
so the stage proves its own work before letting you move on:

- It refuses to write anything at all unless every declared switch returned a
  serial. If one comes back `UNREACHABLE` the run fails with nothing on disk,
  so a partial model can never reach stage 03.
- Having written the file, it reads it back and asserts that no `REPLACE_ME`
  survived, that every serial it read is present, and that each switch carries
  its own serial and its declared role. That check is not belt-and-braces: an
  anchored regex that matches nothing is not an error to
  `ansible.builtin.replace`, which simply leaves the file alone and reports no
  change, so inspecting the written file is the only way a name mismatch gets
  caught.

Stage 03 still makes the placeholder check independently, because the file is
on disk and nothing stops somebody editing it after the fact. It refuses to
start if the model is missing or if any `REPLACE_ME` is still in it, and tells
you to re-run stage 00.

The stage is read-only *with respect to the switches*. `nxos_facts` issues show
commands and nothing else, and the generated model is the only thing it writes
anywhere. The first thing that writes to a switch is the import in stage 03.

## Things that will bite you

**The upstream integration examples are stale.** `tests/integration/host_vars/examples/`
inside `cisco.nac_dc_vxlan` 0.9.0 still uses the old flat shape
(`vxlan.global.name`, `vxlan.global.bgp_asn`, `vxlan.underlay.general.subnet_mask`).
The current model is `vxlan.fabric.name` / `vxlan.fabric.type`,
`vxlan.global.ibgp.bgp_asn` and `vxlan.underlay.ipv4.subnet_mask`. The
authoritative references inside the collection are
`roles/validate/files/defaults.yml` and `plugins/plugin_utils/data_model_keys.py`,
not the examples.

**Jinja in a `.nac.yaml` file is never rendered.** The validate role reads
those files off disk through the `nac_dc_validate` action plugin, bypassing
Ansible templating. An expression written into the model reaches the validator
as literal text. That is the whole reason the serials go into the model as
literal strings instead of the model looking them up.

**There is no JSON schema by default.** `schema_path` defaults to empty, and
the plugin falls back to `nac_validate`'s default path, which does not exist
here — you get a warning, not an error. Only the collection's Python rules
run. A misspelled or misplaced key is therefore *dropped silently* rather than
rejected. Check `data_model_keys.py` before inventing a key.

**A file containing only the top-level `vxlan:` key can delete model sections.**
The collection warns about this in `prep_001_fabric.py`. Don't leave an empty
stanza behind when commenting something out.

**vPC pairs cannot be edited.** The data model treats them as
provision-and-decommission only: changing the peers or scaling the peer-link
means delete and recreate. Get `playbooks/host_vars/Pseudoco-DC1/topology_vpc.nac.yaml` right before stage 04.

**The import erases switches, and you cannot turn that off.** Stage 03 wipes
the running configuration of each switch as it joins the fabric, which is what
the guide does when it has you uncheck Preserve Config. What is worth knowing
is that this is not a setting here: `preserve_config: false` is hardcoded in
`roles/dtc/common/templates/ndfc_inventory/common/fabric_inventory.j2`, so no
data model value and no `-e` flag changes it. There is no confirmation prompt
either. Run this against a pod you are willing to lose.

Do not confuse that with `greenfield_cleanup` in `global.nac.yaml`. That one
renders `GRFIELD_DEBUG_FLAG`, the fabric's Greenfield Cleanup Option, and only
decides whether the cleanup needs a switch reload. It is set to `Enable`
because the guide's Advanced tab says to, and because Cisco recommends it for
Nexus 9000v fabrics like this pod.

**The import runs for minutes with no output, and a 30-second connection
timeout used to kill it. It happens in stage 02, not stage 03.** Stage 02 runs
the same `dtc.create` role as stage 03 and filters nothing, so as soon as
stage 00 has generated `topology_switches.nac.yaml` — which it must have
before either stage can build anything — the switch import lands in stage 02.
Stage 03 only does the import itself if you run it on its own, or if you held
02 to the fabric object with `--tags cr_manage_fabric`.

The import is a blocking HTTP call: `dcnm_inventory` POSTs to
`fabrics/{fabric}/inventory/discover?setAndUseDiscoveryCredForLan=true` and
Nexus Dashboard holds that request open while it SSHes to the switches in it,
discovers them and imports them. There is one such POST per switch **role**,
because `group_diff_create_by_role()` collapses the switches into one payload
per role with a comma-joined `seedIP` — three for this pod, one each for the
leaves, the spines and the border. Each one is minutes of work behind a single
response, so **the step looks frozen and is not. Do not interrupt it.**

The httpapi connection defaults to a 30-second `persistent_command_timeout`,
which tore the call down mid-discovery and produced a `MODULE FAILURE` ending
in `command timeout triggered, timeout value is 30 secs`. What made that hard
to place is the text wrapped around it — "Please verify your login
credentials, access permissions and fabric details" — so a timeout reads as a
credential or fabric problem, which it is not. That sentence is appended by
`cisco.dcnm`'s httpapi connection plugin (`plugins/httpapi/dcnm.py`) to every
exception the transport raises, so it says nothing about what actually failed.

`inventory/group_vars/nd/connection.yml` now sets `ansible_command_timeout:
1000` and `ansible_connect_timeout: 1000` for the whole `nd` group, so it
covers both `Pseudoco-DC1` and `External`. 1000 is not padding: `cisco.dcnm`'s
own `plugins/action/dcnm_inventory.py` refuses to run unless both timeouts are
at least 1000, and its README sets exactly these two keys.

That guard never fires here, which is why the raw 30-second error was all you
got. `cisco.nac_dc_vxlan` drives the dcnm modules itself from
`dtc.manage_resources` through `plugins/plugin_utils/ndfc_executor.py`, and
only `dcnm_vrf` and `dcnm_network` are routed via their own action plugins —
everything else, `dcnm_inventory` included, goes straight to `_execute_module`
and never sees its own timeout check. Treat those two lines as load-bearing:
nothing upstream will tell the next reader they are.

If you are on a checkout that predates them, you can set them for one run
without editing anything. The same two flags work on any single stage:

```bash
ansible-playbook playbooks/01_dc_deploy.yml \
  -e ansible_command_timeout=1000 -e ansible_connect_timeout=1000
```

A run that died this way is safe to repeat. It will have created the fabric
object before it failed, and `dcnm_inventory` runs `state: merged`, so a
re-run converges whether or not Nexus Dashboard finished the discovery on its
own after Ansible walked away.

**Keep the data model ASCII-only. A non-ASCII character in a port-channel
description is the prime suspect for an HTTP 500 during interface creation.**
Once the timeout above let the switch import through, the next run died at
step 13 of 21, `interface_all` (`dcnm_interface`), with `RETURN_CODE: 500` on
`POST .../lan-fabric/rest/globalInterface` and one entry per interface reading
`An unexpected error occurred during template execution. Please retry after
some time.` against `DC-Leaf2:DC-Leaf1:vPC3`, `vPC4` and `vPC5`.

The outgoing `nvPairs` were compared field by field against the collection's
own `roles/validate/files/defaults.yml`. **Every one of them was the upstream
default** — `MTU: jumbo`, `SPEED: Auto`, `PC_MODE: active`,
`LACP_PORT_PRIO: 32768` and `PEER1_ACCESS_VLAN: '1'`. That last one looks
wrong beside this fabric's 2300–2999 network VLANs and is not: it is
upstream's `access_vlan: 1`, and it is not the fault. The only fields in the
request that were ours rather than upstream's were the three descriptions,
which read `MAIN server — vPC3` and so on, and the em dash in them was the
**only non-ASCII byte in the entire HTTP request** — in a field NDFC feeds to
a Velocity template to render CLI, in a call that failed with a *template
execution* exception.

**That is a strong suspect, not a proven root cause, and worth stating as
such.** Cisco documents no character restriction on an interface description.
The article for this controller's release —
[Working with Connectivity in Your Nexus Dashboard LAN Fabrics, Release 4.2.1](https://www.cisco.com/c/en/us/td/docs/dcn/nd/4x/articles-421/working-with-connectivity-for-lan-fabrics.html)
— raises only a 64-character truncation caveat on the Description field, and
so does the older NDFC
[Add Interfaces for LAN Operational Mode, Release 12.2.2](https://www.cisco.com/c/en/us/td/docs/dcn/ndfc/1222/articles/ndfc-add-interfaces-lan/add-interfaces-for-lan-operational-mode.html).
The message is a generic catch-all that also appears in unrelated netascode
issues [#505](https://github.com/netascode/ansible-dc-vxlan/issues/505) and
[#345](https://github.com/netascode/ansible-dc-vxlan/issues/345), and in a
[Cisco Community thread on ND 4.1.1g](https://community.cisco.com/t5/nexus-dashboard/ndfc-4-1-1g-issues-with-building-multisite-vxlan-evpn-fabric/td-p/5324694)
about setting switch roles. The em dash is simply the one variable we control,
and removing it costs nothing. There is a confound to keep in mind as well:
those three port-channels are also the only vPC interfaces in the model, so a
run that now succeeds does not on its own separate an em-dash problem from
anything else on the vPC path.

Both copies of the descriptions were changed to a plain hyphen, and they have
to stay in step: `playbooks/host_vars/Pseudoco-DC1/topology_switches.nac.yaml.example`
and `inventory/group_vars/all/dc_switches.yml`.

**Pulling that change is only half the fix.** The descriptions that reach
Nexus Dashboard come from the `.example` by way of stage 00, which copies it
over `playbooks/host_vars/Pseudoco-DC1/topology_switches.nac.yaml` and
substitutes only `serial_number` and `role`. That generated file is gitignored
build output, so a pull updates the example and leaves the old em dashes
sitting in the file the pipeline actually reads. Re-run stage 00 after
pulling. It is the one stage here that SSHes to the switches, so the **client
VPN has to be up** for it:

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/02_data_center/nac_vxlan/ansible
git pull
ansible-playbook playbooks/00_discover_dc_switch_serials.yml
ansible-playbook playbooks/01_dc_deploy.yml
```

If you want NDFC's own account of a failure like this rather than the response
Ansible printed, it records one: the controller raises an alarm under the
`lan_fabric_errors` policy naming the template that failed. Nexus Dashboard →
**Events/Alarms**, filtered to the time of the run.

## Coverage, and what is left to do

**This pipeline already carries everything `cisco.nac_dc_vxlan` 0.9.0 can
express for this guide.** That is a deliberate boundary, not a stopping point
chosen at random. Guide sections 4, 5 and 6 are covered end to end: the
fabric, the switch import and roles, the vPC pair, the three vPC interfaces,
and the VRFs and networks with their names, descriptions, gateways and
attachments. Everything below is outside the model, verified by reading the
collection rather than inferred.

The way to re-check any of this on a new release is to dump the settings the
fabric templates can emit and look for the nvPair you want:

```bash
ansible-galaxy collection download cisco.nac_dc_vxlan:<ver> -p /tmp/x
tar xzf /tmp/x/cisco-nac_dc_vxlan-<ver>.tar.gz -C /tmp/nac
cd /tmp/nac/roles/dtc/common/templates/ndfc_fabric
cat dc_vxlan_fabric/*/*.j2 | grep -oE "^\s+[A-Z][A-Z0-9_]+:" | sort -u
```

On 0.9.0 that is 134 nvPairs for a VXLAN EVPN fabric and 30 for an External
one. What follows is what is *not* in those lists.

### 1. VRF-Lite to the edge router — the one that matters

Guide section 8 extends MAIN, PROD and IOT out of DC-Service-Leaf to
DC-SITE11-CEDGE8Kv: `EXTEND: VRF_LITE` on the VRF attachment, with
Ethernet1/8, dot1q 2/3/4 and `192.168.252.5|9|13/30` against neighbours
`.6/.10/.14`.

The data model cannot say that. `dc_vxlan_fabric_vrfs.j2` emits exactly one
key per attachment, `- ip_address: <ip>`, and there is no `vrf_lite` key
anywhere in the VRF templates. `overlay_extensions.vrf_lites` is a different
feature despite the name: it renders `ndfc_vrf_lite_ebgp.j2`, which is
`router bgp` / `neighbor` CLI pushed as a switch policy. It creates no
sub-interface and no attachment, so on its own it would configure a BGP
neighbour that has no interface to reach.

`cisco.dcnm` underneath can do it — `dcnm_vrf` supports `attach[].vrf_lite[]`
with `interface`, `dot1q`, `ipv4_addr`, `neighbor_ipv4` and `peer_vrf`. Two
things to design around when this gets written:

- The create role runs `dcnm_vrf` with `state: replaced`, and DC-Service-Leaf
  is not in `vrf_attach_groups`. A create run will therefore detach whatever a
  VRF-Lite stage attached, so that stage has to run after create on every
  pass, not once.
- The fabric settings below have to be in place first.

### 2. The fabric's VRF-Lite Resources settings

`VRF_LITE_AUTOCONFIG` (the UI's **VRF Lite Deployment**, value
`Back2Back&ToExternal`), `DCI_SUBNET_RANGE` (`192.168.252.0/24`),
`AUTO_SYMMETRIC_VRF_LITE` (**Auto Deploy for Peer**) and
`AUTO_UNIQUE_VRF_LITE_IP_PREFIX` are none of them in the 134. Without them
the fabric sits at the NDFC default of `Manual` and the address staging
section 8 depends on never happens.

These are reachable with a supplementary `dcnm_fabric` call, and safely so:
the create role applies the fabric with `state: merged`, so extra nvPairs set
alongside it survive its re-runs. Set them in stage 02, before stage 04
deploys, not afterwards.

### 3. Fabric Monitor Mode on the External fabric

No key, and it does not fail safe. `dc_external_fabric_general.j2` emits
`IS_READ_ONLY: false`, the opposite of the guide. Stage 07 guards against
this by refusing to run when the fabric already exists — see its header.

### 4. Importing the IOS-XE edge router

The External inventory template has no device-type concept, and
`dcnm_inventory` has no `device_type` parameter at all, only
`role: edge_router`. Neither layer can ask Nexus Dashboard to discover a
CSR/CAT8K. This would need a raw REST call against the discovery API.

### 5. Fabric cosmetics

Location, License Tier and the Telemetry feature checkbox have no nvPairs in
the templates. They do not affect the EVPN fabric, and are noted only so the
next person does not go looking.

### 6. Verification of the above

Stage 05 checks switches, roles, VRFs, networks and attachments. When items 1
and 2 land, extend it to assert the `VRF_LITE` extension on DC-Service-Leaf,
so that a create-without-VRF-Lite run is caught rather than silently
reverting external connectivity.

## Version pinning

`collections/requirements.yml` here and
`00_scriptserver_bootstrap/roles/script_server_bootstrap/files/requirements.yml`
must stay identical — the bootstrap file is the one that actually gets
installed, so a higher pin here alone is never applied. Same trap the campus
collection hit. All six pins are in both files, including the four supporting
collections; without them there they would be installed as dependencies at
whatever the Galaxy resolver picked, which is not what this file claims is
running.

ND 4.2.1 support landed in `cisco.dcnm` 3.12.1, and `cisco.nac_dc_vxlan` 0.9.0
itself requires `cisco.dcnm >= 3.13.0`, `ansible.netcommon >= 4.1.0` and
`community.general >= 8.5.0`. Its Python dependencies (`nac-yaml`,
`nac-validate`, `macaddress`, `packaging`, `jmespath`, `requests`) are in
`ansible-automation/requirements.txt`; they are hard runtime requirements
because the collection reads and validates the model in Python, not in Jinja.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ERROR! the role 'cisco.nac_dc_vxlan.validate' was not found`, followed by a list of role search paths | The **collection** is not installed. Ansible reports a missing collection as a missing role and prints the role search path, which points at the playbook rather than at what is installed. Nothing is wrong with the playbook | [Before you run anything](#before-you-run-anything), step 1 |
| `Collection cisco.nac_dc_vxlan does not support Ansible version …` | You are not in the bootstrap's `~/venv`. 0.9.0 declares `requires_ansible ">=2.15.0,<2.19.0"` and this repo pins `ansible-core` 2.17.14 | `which ansible-playbook` — it should be under `~/venv/bin`. If apt offers to install `ansible-core`, decline; that is an unpinned copy outside the venv |
| `No inventory was parsed, only implicit localhost is available` | You ran from `playbooks/` instead of the directory holding `ansible.cfg` | `cd` up one level and re-run |
| `[WARNING]: ansible-pylibssh not installed, falling back to paramiko` during stage 00 | Your `~/venv` predates the `ansible-pylibssh` pin. `network_cli` autodetects its SSH library and warns when it has to fall back | Harmless — paramiko works and the serials still collect. To clear it, `pip install -r ansible-automation/requirements.txt` in `~/venv`, or re-run `01_bootstrap_script_server.yml` |
| Stage 00 reports `UNREACHABLE` against a switch and stops | SSH to that management address failed. This is the only stage that talks to a switch rather than to Nexus Dashboard. It fails before writing anything, so the data model is left as it was rather than half generated | Check the VPN is up and you can reach `198.18.128.x`, that the address in `dc_switches.yml` is right, and that the vault credentials are current, then re-run the stage |
| Stage 00 fails saying a serial never reached the file | A switch name in `dc_switches.yml` does not match the name in `topology_switches.nac.yaml.example`. The substitution anchors on that name, so a mismatch matches nothing and leaves a placeholder behind | Make the two files agree on the name and re-run the stage |
| Stage 03 fails pointing at `topology_switches.nac.yaml` | The file is missing, or a serial is still `REPLACE_ME`, which means no clean stage 00 run has produced it | Re-run stage 00. It regenerates the file from scratch and refuses to leave a placeholder behind — see [Why serial discovery is its own stage](#why-serial-discovery-is-its-own-stage-and-why-it-generates-the-model) |
| Stage 02 (or 03) fails at step `inventory` with `MODULE FAILURE` and, in the traceback, `command timeout triggered, timeout value is 30 secs` | The discovery call runs for minutes and the httpapi connection timed out at its 30-second default. The failure carries `cisco.dcnm`'s generic "verify your login credentials, access permissions and fabric details" text, so it reads like a credential problem and is not. It is stage 02 rather than 03 because 02 runs the same create role and the switch model already exists by then | `git pull` — `inventory/group_vars/nd/connection.yml` sets both timeouts to 1000. For one run without editing, add `-e ansible_command_timeout=1000 -e ansible_connect_timeout=1000`. See [Things that will bite you](#things-that-will-bite-you) |
| Stage 02 (or 03) fails at step `interface_all` (`dcnm_interface`) with `RETURN_CODE: 500` on `POST .../lan-fabric/rest/globalInterface`, and each `DATA` entry says `An unexpected error occurred during template execution`, naming `DC-Leaf2:DC-Leaf1:vPC3`, `vPC4` and `vPC5` | Suspected — a non-ASCII character in a port-channel `description`. The em dash in `MAIN server — vPC3` was the only non-ASCII byte in the request and the only field in it that was not a collection default, and NDFC renders that string through a Velocity template. Not proven: NDFC returns the same generic message for unrelated faults | `git pull` — the descriptions are plain hyphens as of 2026-09-25. **A pull on its own is not enough:** what NDFC reads is the generated `topology_switches.nac.yaml`, so re-run `playbooks/00_discover_dc_switch_serials.yml` afterwards, with the VPN up. See [Things that will bite you](#things-that-will-bite-you) |
| You changed `topology_switches.nac.yaml.example`, or pulled a change to it, and the build behaves as though nothing changed | The pipeline never reads the `.example`. It reads `topology_switches.nac.yaml`, which stage 00 generates from it and which is gitignored build output, so git never touches it | Re-run `playbooks/00_discover_dc_switch_serials.yml`. It regenerates the file from the current `.example` and `dc_switches.yml`. It SSHes to the switches, so the VPN has to be up |
| Stage 02 (or 03) sits at the `inventory` step for minutes with no output | Not a fault. Nexus Dashboard is holding one request open per switch role while it discovers and imports the five switches | Wait. Interrupting it leaves the import half done. See [Things that will bite you](#things-that-will-bite-you) |
| Stage 07 refuses to run, saying the fabric already exists | Working as intended | See [Coverage, and what is left to do](#coverage-and-what-is-left-to-do), item 3 |
