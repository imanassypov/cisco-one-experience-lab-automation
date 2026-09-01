# Campus — EVPN track (Catalyst Center templates)

Site 105 campus EVPN/VXLAN is built by **Catalyst Center**, not by Ansible pushing IOS CLI. Ansible only drives CatC (site, settings, templates, profile, provision). Jinja **DEFN / FUNC / FABRIC** templates render the fabric. Methodology: [imanassypov/CatalystCenter-BGP-EVPN-VXLAN](https://github.com/imanassypov/CatalystCenter-BGP-EVPN-VXLAN).

Independent of the [SDA track](../sda/).

Author on the Mac in this repo. Run on the Kali script server after `git pull` (or Mac `02_sync_from_git.yml`). Ansible on Kali is on PATH from `~/venv`. All playbooks run from `ansible/`.

## Vendored trees

Copied (not a submodule) from `CatalystCenter-BGP-EVPN-VXLAN` `main` at
`6d2afa3a2becfe71f8f036ee79a0a1c164ba0433`
(“Install dmz2 Type-5 on campus…”). Splunk assurance, CML node configs, and `CICD Pipeline/utils` were not copied.

```
evpn/
  Catalyst Center Templates/   # Site DEFN/FUNC/FABRIC .j2 and BGP-EVPN-BUILD.yml
  Settings/                    # settings.json SSOT (DNS/NTP/AAA/sites/devices)
  ansible/                     # only playbook collection (CatC CICD + Site 105 verify)
```

`ansible/` is wired to the sibling folders:

- `template_source: local` and `template_local_root` → `evpn/` (so `Catalyst Center Templates/…` resolves)
- `settings_json_path` → `evpn/Settings/settings.json`
- CatC API host: `cat-center.corp.pseudoco.com` (credentials from `lab_access['Catalyst Center']` in `Lab Topology/lab_access.yml`, not in `settings.json` or plaintext inventory)
- Appliance **3.1.5**. Ansible/SDK API profile is **3.1.3.0** (`catc_version` / `dnac_version`) because `catalystcentersdk` has no `3.1.5` profile. Collections: `cisco.catalystcenter` 2.10.2, `cisco.dnac` 6.46.0; SDKs `catalystcentersdk` 3.1.3.0.1 and `dnacentersdk` 2.10.6 (installed by `00_scriptserver_bootstrap`).

## Do not provision yet

`Settings/settings.json` matches the live CatC hierarchy (Global → state → city → building → MAIN). Discovery jobs: `Site-105-Discovery` (RANGE `172.30.255.1–3`, Loopback, no NETCONF) and `C9800-WLC` (RANGE `198.18.5.103`, NETCONF 830) assigned to DC-Site-10 / MAIN. CatC inventory IPs for the fabric are those loopbacks; Ansible SSH verify still uses `198.18.128.22–24`.

**DEFN** is remapped to Site-105: CatC FQDNs `Site_105-Leaf1|Leaf2|Border-Spine.dcloud.cisco.com`, ASN **65535**, VRFs **Main / PROD / IOT** (ids 10 / 101 / 102), static BUM `232.1.1.1`, VRF-Lite SVI handoff on Border-Spine `Gi1/0/48` toward SD-WAN AS 65534. `DeployTemplate` is still false. **Do not run `09_provision_devices` or `10_deploy_composite` until you ask to provision.**

## CatC pipeline (run from `ansible/`)

Stages, in order, from `ansible/playbooks/`:

| Playbook | Purpose |
| --- | --- |
| `00_site_deploy.yml` | Orchestrator (later stages) |
| `01_site_hierarchy.yml` | CatC site hierarchy |
| `02_network_settings.yml` | DNS/NTP/AAA from Settings |
| `03_credentials.yml` | Device credentials in CatC |
| `04_device_discovery.yml` | Discovery |
| `05_assign_to_site.yml` | Assign devices to sites |
| `06.*` | SWIM (optional; not required to sync templates) |
| `07_template_sync.yml` | Publish `.j2` into CatC projects; build composite `BGP-EVPN-BUILD` |
| `08_network_profile.yml` | Network profile |
| `09_provision_devices.yml` | Provision (`DeployTemplate` still false; do not run until asked) |
| `10_deploy_composite.yml` | Deploy composite (do not run until asked) |

Safe to inspect after the repo-root `.vault` can decrypt `Lab Topology/lab_access.yml`: syntax-check or a dry read of `07_template_sync.yml`. Real CatC runs stay on the script server (`cisco.catalystcenter` / `cisco.dnac`). Install collections from `ansible/collections/requirements.yml` into `~/venv` if a stage reports a missing collection.

### Vault

One file at the repository root unlocks `Lab Topology/lab_access.yml` for every collection:

```bash
cd ~/cisco-one-experience-lab-automation
cp .vault.example .vault   # one line: lab vault password
ansible-vault view "Lab Topology/lab_access.yml"
```

Do not commit `.vault` or an unencrypted `lab_access.yml`.

### Run (script server)

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/01_campus/evpn/ansible
ansible-playbook playbooks/07_template_sync.yml
```

## Post-deploy verify

These playbooks do **not** build the fabric. After CatC has provisioned Site 105, use them for TCP/22 and `ios_command` evidence.

| Inventory name | Role | SSH mgmt | CatC / Loopback0 |
| --- | --- | --- | --- |
| Site_105-Leaf1 | Leaf | 198.18.128.22 | 172.30.255.1 |
| Site_105-Leaf2 | Leaf | 198.18.128.23 | 172.30.255.2 |
| Site_105-Border-Spine | Border + spine | 198.18.128.24 | 172.30.255.3 |

| Playbook | Purpose |
| --- | --- |
| `playbooks/12_verify_preflight.yml` | TCP/22 to all three switches |
| `playbooks/13_verify_collect_facts.yml` | Version, interfaces, OSPF, BGP EVPN, NVE, VRF, VLAN → `ansible/evidence/` |

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/01_campus/evpn/ansible
ansible-playbook playbooks/12_verify_preflight.yml
ansible-playbook playbooks/13_verify_collect_facts.yml
```

`ansible/evidence/` is local output and is gitignored.
