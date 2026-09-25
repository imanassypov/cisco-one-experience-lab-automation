# PseudoCo DC fabric — Nexus as Code pipeline

Automates the **NDFC - DC Fabric Deployment** section of the student guide: the
VXLAN EVPN fabric `Pseudoco-DC1` on Nexus Dashboard 4.2.1.10, its five
switches, the vPC pair, the server port-channels, and the MAIN / PROD / IOT
VRFs and networks.

Built on [Cisco Nexus as Code](https://netascode.cisco.com/docs/data_models/vxlan/overview/)
(`cisco.nac_dc_vxlan`), which is a declarative layer over `cisco.dcnm`. You
describe the fabric you want in YAML under `playbooks/host_vars/`; the collection works
out the API calls.

## Running it

Everything runs on the Kali script server, from **this directory** — the one
holding `ansible.cfg`, not from `playbooks/`. The relative paths in
`ansible.cfg` that reach the vault and the vars plugin are resolved against
the working directory, so running from anywhere else breaks authentication:

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/02_data_center/nac_vxlan/ansible
ansible-playbook playbooks/00_dc_deploy.yml
```

**The first run stops part way, on purpose.** Stage 02 prints the switch
serial numbers, and you transcribe them into the data model yourself, so
stage 03 halts until you have. Copy the serials in as described under
"Why serial discovery is its own stage", then run the same command again and
it goes end to end.

| Playbook | What it does |
|---|---|
| `playbooks/00_dc_deploy.yml` | Imports 01, 02, 03, 04, 06 |
| `playbooks/01_fabric.yml` | Ensures the fabric object exists |
| `playbooks/02_discover_serials.yml` | Read-only. Prints the switch serials for you to transcribe |
| `playbooks/03_create.yml` | Creates the full intent on the controller |
| `playbooks/04_deploy.yml` | Pushes that intent to the switches |
| `playbooks/05_remove.yml` | Destructive prune. Not in `00`. Needs `-e dc_remove_confirm=REMOVE_OK` |
| `playbooks/06_verify_fabric.yml` | Nexus Dashboard API verification, writes `evidence/` |
| `playbooks/07_external_fabric.yml` | Creates the External fabric. Not in `00` — different inventory host |

Useful overrides:

- `-e dc_verify_fail_on_mismatch=false` — stage 06 reports without failing
- `--tags cr_manage_fabric` — narrows a create run to the fabric object only

## Layout

```
ansible.cfg
collections/requirements.yml
inventory/
  static_inventory.yml            one host per FABRIC, not per device
  group_vars/all/dc_switches.yml  switches, IPs, roles, port-channels, seed
  group_vars/nd/connection.yml    httpapi transport, vault-sourced credentials
  group_vars/nd/nd.yml            remove-role delete-mode flags, all false
playbooks/
  00_dc_deploy.yml … 07_external_fabric.yml
  host_vars/Pseudoco-DC1/*.nac.yaml   the Nexus as Code data model
  host_vars/External/global.nac.yaml
  templates/
evidence/                         written by stage 06, gitignored
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

`playbooks/host_vars/Pseudoco-DC1/topology_switches.nac.yaml` is **written by
hand and gitignored**. `topology_switches.nac.yaml.example` is the tracked
template you copy it from.

Credentials come from the vault-encrypted `Lab Topology/lab_access.yml` via the
repo's `plugins/vars/lab_access.py` vars plugin, exactly as the campus EVPN
collection does. Nothing in this tree contains a password, and nothing here
should ever acquire one.

## Why serial discovery is its own stage, and why you transcribe by hand

Nexus as Code identifies a switch by `serial_number`, not by hostname or
management IP, and it is strict about it. Rule 301 in the validate role walks
every entry in `vxlan.topology.switches` and fails the run if any of them
lacks a serial, before anything reaches Nexus Dashboard.

There is an awkwardness underneath that. The import itself does not use the
serial — `fabric_inventory.j2` imports each switch by `seed_ip` with
`max_hops: 0`, and `serial_number` appears there only in the POAP blocks. So
the collection insists on a value it does not need for the one operation that
could discover it, and you cannot read a serial out of the fabric until the
switch is already in the fabric.

`playbooks/02_discover_serials.yml` breaks that. It reads
`.../inventory/switchesByFabric` for switches already imported, and for
anything still missing it runs the same CDP crawl the guide's Add Switches
dialog performs (`.../inventory/test-reachability`, seeded at
`198.18.128.101`, two hops), which reports serials without importing
anything. It runs after `playbooks/01_fabric.yml` because both endpoints are
fabric-scoped.

**It prints the serials and stops there.** Putting them into
`topology_switches.nac.yaml` is yours to do:

```bash
cp playbooks/host_vars/Pseudoco-DC1/topology_switches.nac.yaml.example \
   playbooks/host_vars/Pseudoco-DC1/topology_switches.nac.yaml
# then replace each REPLACE_ME with the serial printed for that management IP
```

That is deliberate rather than unfinished. Generating the file would hide the
one thing worth learning here, which is what the data model is keyed on; and
serials belong to a single dCloud pod, so the file is gitignored either way.

Transcribe carefully and match on management IP, not on position. Rule 301
only checks that `serial_number` is non-empty, so a wrong or duplicated serial
passes validation and fails much later inside the create role. Stage 03 at
least catches the obvious case: it refuses to start if the file is missing, or
if any `REPLACE_ME` is still in it.

The stage is read-only against the switches: `test-reachability` reports what
is discoverable, it does not import anything. The import that writes to a
switch happens in stage 03.

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
as literal text. That is the whole reason stage 02 writes serials out as
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

## Not automated

**VRF-Lite to the edge router.** The guide extends MAIN, PROD and IOT out of
DC-Service-Leaf to DC-SITE11-CEDGE8Kv over VRF-Lite. Two reasons it is not
here:

1. The IOS-XE edge router is out of scope for this pipeline, so nothing puts it
   in the External fabric, and without it Nexus Dashboard has no far-end to
   compute the inter-fabric connection against.
2. Nexus as Code's `overlay_extensions.vrf_lites` is not the same feature. It
   models per-switch BGP/OSPF routing policy for an already-established
   extension (it renders `ndfc_vrf_lite_ebgp.j2`, and its rules live under
   `roles/validate/files/rules/external/`). The guide's step is the
   `EXTEND: VRF_LITE` attachment with auto-allocated dot1q tags and IFC
   addressing. No shipped example pairs the two, so this needs a spike against
   the live appliance before it can be written down as automation.

**The guide's VRF-Lite fabric settings.** `Back2BackAndToExternal`, the
`192.168.252.0/24` DCI subnet, Auto Deploy for Peer and Auto Allocation of
Unique IP are all on the fabric's Resources tab in the UI and have no key in
the 0.9.0 data model. Set them by hand if the spike above needs them.

**Fabric Monitor Mode on the External fabric.** No key in the data model.
`cisco.dcnm`'s `dcnm_fabric` exposes it as `IS_READ_ONLY` if it turns out to
matter.

## Version pinning

`collections/requirements.yml` here and
`00_scriptserver_bootstrap/roles/script_server_bootstrap/files/requirements.yml`
must stay identical — the bootstrap file is the one that actually gets
installed, so a higher pin here alone is never applied. Same trap the campus
collection hit.

ND 4.2.1 support landed in `cisco.dcnm` 3.12.1, and `cisco.nac_dc_vxlan` 0.9.0
itself requires `cisco.dcnm >= 3.13.0`, `ansible.netcommon >= 4.1.0` and
`community.general >= 8.5.0`. Its Python dependencies (`nac-yaml`,
`nac-validate`, `macaddress`, `packaging`, `jmespath`, `requests`) are in
`ansible-automation/requirements.txt`; they are hard runtime requirements
because the collection reads and validates the model in Python, not in Jinja.
