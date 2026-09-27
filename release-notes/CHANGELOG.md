# Changelog

The five changes that matter from this repository's history, newest first. This
file replaces the per-date notes that used to live here: 91 entries across seven
dated files, consolidated into the arcs they actually formed. Exact error
strings, version numbers and API paths are kept deliberately — they are the
reason these notes exist. Full history is in `git log`.

- **02_data_center — the DC VXLAN EVPN fabric is now automated, built on Cisco Nexus as Code.** *2026-09-25 to 2026-09-27.* A one-paragraph stub became a working
  pipeline at `nac_vxlan/ansible/` that builds the DC fabric end to end,
  covering the guide's **NDFC - DC Fabric Deployment** sections 4 through 8: the
  `Pseudoco-DC1` fabric and its five switches, the DC-Leaf1/DC-Leaf2 vPC pair,
  the three server port-channels, the MAIN / PROD / IOT VRFs and networks with
  their attachments, the `External` fabric in Monitor Mode with the pod's
  pre-configured edge router discovered into it, and the VRF-Lite extensions
  that carry all three VRFs out of the border leaf.
  Built on `cisco.nac_dc_vxlan` 0.9.0 over `cisco.dcnm` 3.13.0 rather than
  `cisco.dcnm` alone, which gives one module per Nexus Dashboard object and so
  means transcribing the student's click sequence with every dependency written
  out by hand. Credentials come from the same vault-encrypted `lab_access.yml`
  as the campus collection.

  Stage 00 is serial discovery and has to be separate, because Nexus as Code
  keys a switch on `serial_number` and serials are pod-local, so they cannot be
  committed. It SSHes with `cisco.nxos.nxos_facts` and generates
  `topology_switches.nac.yaml` from the tracked `.example`; that output is
  gitignored and silently overwritten every run, and it is the only stage
  needing the switch VPN. Numbering is load-bearing, and survives every
  renumber: the orchestrated stages are contiguous and are exactly what
  `01_dc_deploy.yml` imports in order, while the lowest and highest numbers are
  the ones you invoke by name. The import is **greenfield** — `preserve_config: false` is
  hardcoded in the collection's inventory template, so stage 02 erases the
  running configuration of all five switches as it onboards them, with no
  prompt and no flag to disable it.

  Three stages are hand-written because the data model cannot reach them, a
  boundary established by dumping every nvPair the fabric templates can emit —
  134 for VXLAN EVPN, 30 for External — and checking the guide against that list
  rather than grepping for names that might be wrong. Stage
  03 applies eight fabric settings, five of them VRF-Lite nvPairs through
  `cisco.dcnm.dcnm_fabric` while License Tier, Telemetry and Location are
  properties of the ND 4.2 fabric object at `/api/v1/manage/fabrics/<fabric>`
  and need a `dcnm_rest` read-modify-write run *after* the `dcnm_fabric` task.
  Two of those nvPairs mislead. `VRF_LITE_AUTOCONFIG` defaults to `Manual`,
  under which the controller never auto-creates an inter-fabric link at all and
  external connectivity cannot be built, so it is set to `Back2Back&ToExternal`.
  And `AUTO_SYMMETRIC_VRF_LITE` is the **Auto Deploy for Peer** checkbox, which
  writes nothing by itself — it is stamped onto an IFC at creation time and
  "does not affect the existing IFCs", so setting it later reaches nothing
  already built.
  Stage 04 creates `External` in Monitor Mode with `dcnm_fabric` because the
  Nexus as Code roles cannot: the create role always config-saves after its
  inventory step and gets `HTTP 500 - Fabric External cannot be deployed without
  any switches`, and its template ties `IS_READ_ONLY` to the bootstrap setting
  so it can never emit `true`. The edge router is *discovered into* that fabric
  over the ND 4.x manage API, since the legacy NDFC API `dcnm_inventory` drives
  has no IOS-XE support.

  Stage 05 closes the one thing the data model genuinely cannot say. A
  `vrf_attach_group` entry in `vrfs.nac.yaml` names a switch and nothing else,
  with no key for `EXTEND: VRF_LITE`, the sub-interface, the dot1q tag or the
  neighbour address, so attaching the border leaf there would give it the VRFs
  without the extensions — worse than not attaching it. The stage therefore
  drives `cisco.dcnm.dcnm_vrf` directly, which does support
  `attach[].vrf_lite[]`, from intent declared in
  `inventory/group_vars/all/dc_vrf_lite.yml`. Three properties of it are
  deliberate. It uses `state: merged`, because stage 02 attached each VRF to
  DC-Leaf1 and DC-Leaf2 and `replaced` would detach them — and conversely it has
  to run after stage 02 on *every* pass, since stage 02's create role runs
  `state: replaced` against a model that omits DC-Service-Leaf and so strips the
  extensions each time. It sits before the deploy because stages 02 through 05
  only write intent to the controller and, past that one-time import wipe,
  **stage 06 is the only stage that changes running configuration**, so the
  parent interface, the three dot1q sub-interfaces and their BGP neighbours all
  land in one Recalculate and Deploy rather than the guide's
  deploy-edit-deploy sequence, which is an
  artefact of driving the controller through a UI one dialog at a time. And the
  addresses are pinned rather than left to `AUTO_UNIQUE_VRF_LITE_IP_PREFIX`,
  which is on and would otherwise allocate them from `DCI_SUBNET_RANGE`.

  **The edge router is out of scope by design, not a gap.** The pod ships
  `DC-SITE11-CEDGE8Kv` already configured, so there is nothing for the
  automation to write, and that is why the addresses are pinned: the far side of
  each link already answers at exactly those addresses, and a leaf that picked
  its own would never bring BGP up. It is also why `IS_READ_ONLY: true` is the
  correct, protective setting rather than an obstacle — Nexus Dashboard will
  never write to a device the lab owns, and it could not in any case, since
  "Auto IFC is supported on Cisco Nexus devices only". Cisco's scope statement
  for VRF-Lite autoconfiguration, "Border role in the VXLAN fabric and Edge
  Router role in the connected external fabric device", is likewise why only the
  border leaf ever appears in a deploy: the leaves and spines fall outside every
  supported case
  ([Cisco VRF Lite](https://www.cisco.com/c/en/us/td/docs/dcn/ndfc/1221/articles/ndfc-vrf-lite/vrf-lite.html)).
  The DC fabric side is automated end to end. Details in
  [the DC collection README](../ansible-automation/02_data_center/nac_vxlan/ansible/README.md).

- **02_data_center — the Nexus Dashboard failures that did not announce themselves.** *2026-09-25 to 2026-09-27.* Each cost real debugging time because the
  controller reported success, or named the wrong thing in its failure.

  **Batched VLAN allocation collides, and a green `vrfs` step hides it.** The run
  died at `networks` with `Entered network VLAN id 2300 is already in use`. In
  `cisco.dcnm` 3.13.0, `dcnm_vrf.py` (4011-4043) and `dcnm_network.py` (5056)
  GET `.../resource-manager/vlan/{fabric}?vlanUsageType=TOP_DOWN_VRF_VLAN` for
  any object whose VLAN is 0; that returns the next *free* VLAN without
  reserving it and nothing is committed between iterations, so every object in a
  run gets the bottom of the range. `dcnm_vrf` hit the same wall two steps
  earlier and still reported `ok (changed=True)`, because it does not inspect
  the per-attachment `DATA` map inside an HTTP 200 body. Every VRF and network
  now pins `vlan_id` (2000-2002, 2300-2302). Omitting one is safe when a human
  clicks **Propose VLAN**, one object at a time with a save between, and unsafe
  in a batched API run — so wherever the guide leans on interactive allocation,
  the model must pin what the GUI would have proposed.

  **The switch import dies at 30 seconds and blames your credentials.** The
  inventory step POSTs to
  `fabrics/{fabric}/inventory/discover?setAndUseDiscoveryCredForLan=true`, once
  per switch *role*, and the controller holds it open while it SSHes to the
  switches. `ansible.netcommon.httpapi`'s 30-second
  `persistent_command_timeout` tore that down with `ConnectionError: command
  timeout triggered, timeout value is 30 secs`, which presents as a credential
  problem because `cisco.dcnm`'s httpapi plugin appends "Please verify your
  login credentials, access permissions and fabric details" to every transport
  exception. `group_vars/nd/connection.yml` now sets `ansible_command_timeout`
  and `ansible_connect_timeout` to 1000, the vendor floor; `cisco.dcnm` guards
  this in `plugins/action/dcnm_inventory.py`, but the guard never fires because
  `cisco.nac_dc_vxlan` routes only `dcnm_vrf` and `dcnm_network` through their
  action plugins. The step now sits silent for minutes — that is the discovery
  call working.

  **Two data-model traps, both silent.** A non-ASCII byte can be fatal: `POST
  .../lan-fabric/rest/globalInterface` returned `500` with "An unexpected error
  occurred during template execution" on the three vPC port-channels, whose
  descriptions were the only fields that were not collection defaults and whose
  em dash was the sole non-ASCII byte in the request. A strong suspect rather
  than a proven cause, so the boundary was made checkable instead: nothing under
  `ansible-automation/02_data_center/` may contain a byte above 127. And there
  is **no schema** — `schema_path` defaults to empty and the fallback file does
  not exist, so validation is skipped with a warning and a misspelled or
  misplaced key is dropped in silence. The collection's own
  `tests/integration/host_vars/examples/` are still the pre-1.0 flat shape, so
  following them validates cleanly and builds the wrong fabric.

  **The verify stage reported a healthy fabric as broken, twice over.** It first
  crashed with `'None' has no attribute 'split'` out of
  `(a.portNames | default('')).split(',')`, because the controller returns
  `portNames` as JSON `null` and Jinja's `default()` substitutes only for an
  *undefined* value; it reads `default('', true)` now. Behind the crash, the
  attachment endpoints enumerate every switch that *could* carry a VRF or
  network and report unattached ones as `lanAttachState: NA`, which were folded
  into the "must be DEPLOYED" test, so all six objects failed every run; the
  stage now partitions on `isLanAttached`, while an attached switch in `PENDING`
  or `OUT-OF-SYNC` still fails. Separately, an attach-group name matching
  nothing resolved to an empty switch list, so the strongest check passed having
  proved nothing — with `MAIN` naming a nonexistent `dc_leafs` the stage
  reported `11 of 11 check(s) match the declared intent` with `failed=0`. Every
  named group is now asserted to resolve before the first API call.

  **A `0/5` deploy is a statement about one instant, not proof the fabric is
  finished.** Recalculate and Deploy fired straight after the External fabric
  stage reported `0/5` and skipped, then a minute later picked up exactly one
  switch, `DC-Service-Leaf`, and deployed it — with nothing having run in
  between and no switch touched. The controller correlates the
  border-leaf-to-edge-router CDP adjacency asynchronously, after the router add
  returns 202 with an empty body, so a deploy fired seconds later truthfully has
  nothing pending; clicking through the UI hides the delay because the wizard is
  slower than the controller. **The pipeline no longer deploys twice** — that
  wait is now explicit inside stage 05 as `until`/`retries`, six attempts twenty
  seconds apart, extended with `-e dc_vrf_lite_retries=12`. The habit outlives
  the fix: "no changes" means only that the controller had nothing pending when
  it was asked, and a switch appearing on a re-run is not drift but something
  the controller learned between passes. Trust `check_sync -> in_sync=True`
  after a run that deployed something.

- **campus EVPN — the pipeline runs end to end as stages 01-12, with the software upgrade inside it.** *2026-09-19 to 2026-09-24.* SWIM was reintroduced as stage
  `09_swim`, deliberately ahead of the composite deploy so switches are on their
  intended image before EVPN and telemetry configuration lands, and intent
  verification moved to stage 12. `00_site_deploy.yml` now imports all twelve
  stages, where it previously stopped short of provisioning the access point and
  never verified the result; any `--tags` or stage number from before 2026-09-19
  no longer matches. Three caveats belong with a plain orchestrator run, because
  each can fail a run that previously could not: stage 09 **reloads the fabric**
  (`-e swim_activate=false`), stage 11 blocks up to ten minutes polling for an
  access point and then asserts, so a pod with no AP cabled fails *after* the
  fabric is built (`-e ap_expected_count=0`), and stage 12 fails the run on any
  intent mismatch (`-e verify_fail_on_mismatch=false`).

  SWIM uses **`cisco.catalystcenter`, not `cisco.dnac`**, and that is not a
  preference: `cisco.dnac` 6.46.0 `swim_workflow_manager.py:3378` calls
  `tagging_details.get("device_tags")` with no default, so golden tagging dies
  with `TypeError: 'NoneType' object is not iterable` whenever `device_tags` is
  absent (fixed at line 4280 in `cisco.catalystcenter` 2.11.0). The symptom is
  the dangerous part — tagging reports success, `isTaggedGolden` stays false,
  and distribute and activate answer "No eligible devices" forever. **CCO import
  does not work in this pod either:** Catalyst Center rejects every CCO image
  with `NCSW10375: … is not the latest or suggested image from cisco`, even ones
  its own catalogue flags `ciscoLatest: true`, and `software.cisco.com` answers
  HTTP 403 from the script server. So the bootstrap publishes
  `iosxe_images/*.bin` over nginx on port 8080 from `/var/www/iosxe-images`
  (`--tags image_server`), and `settings.json` uses `import_source: remote` with
  `image_base_url: http://198.18.134.12:8080`. Three settings must agree, and a
  typo in any one gives the same "could not import".

  Re-runs are idempotent: the role GETs
  `/dna/intent/api/v1/networkDeviceImages` and passes only when at least one
  device is tagged golden *and* every such device is `DEVICE_UP_TO_DATE`, with
  only `"no eligible devices"` forgiven. That surfaced a trap worth
  generalising: `goldenImages` is **absent from the record, not null**, on
  devices the image is not tagged for, so `d.goldenImages or []` raises — and
  Ansible blames the consuming `set_fact` rather than the expression that broke.
  Always `d.get('goldenImages') or []`.

  Verified live: Site-105's three switches went 17.12.01 to 26.01.02 in install
  mode, committed, in about 16.4 minutes. **Activation looks dead for roughly 12
  of those minutes** and the devices show `Unreachable` with
  `reachabilityFailureReason: "In Service Maintenace"` (the controller's own
  typo) — maintenance mode, not a fault, clearing on completion. Do not diagnose
  a hang before about 20 minutes, and re-read the device rather than trusting
  pre-reload output. Rollback and postcheck remain unproven on hardware and stay
  gated behind `-e swim_rollback=true`.

- **diagnosis — two subsystems that reported themselves broken while healthy, and one hard stop that now has a recovery.** *2026-09-22 to 2026-09-24.* Grouped
  because the lesson is shared: the failure message here routinely names the
  wrong thing, and reading *which* checks passed is what isolates the fault.

  **Stage 12 reported every telemetry subscription `absent` and every receiver
  `no receiver`, on switches answering `53 subscriptions, 53 Valid, 0 Invalid`
  and streaming at that moment.** Two faults were stacked.
  `filter_plugins/genie.py` ends with `json.loads(json.dumps(parsed))` and JSON
  keys are always text, so Genie's integer keys reach Jinja as `"40101"` — look
  them up with `| string`, never `| int`. And Command Runner returns the command
  itself as the first line of output; most Genie parsers skip it, but the
  `show telemetry ietf subscription all` parser reads it as the whole output,
  raises `SchemaEmptyParserError`, and the filter maps that to `{}` meaning "the
  device genuinely has nothing" — a deliberately silent path. `genie_parse` now
  strips a leading line equal to the command, and the stage reports all 51
  evaluated checks matching, `failed=0`. Do not debug this from an SSH capture:
  Command Runner text and SSH text differ and the difference *is* the bug. Pull
  the real thing —
  `POST /dna/intent/api/v1/network-device-poller/cli/read-request`, poll for
  `progress.fileId`, `GET /dna/intent/api/v1/file/{fileId}`.

  **Stage 08 failing with `AAA CLI(s) are already present on the device … Remove
  the CLIs, resync the device and retry` is a dirty pod, not a playbook defect,
  and no `-e` override reaches it** because the check runs on the appliance. The
  tell that it is stale Catalyst Center config rather than lab base config:
  `pac key`, `automate-tester`, `dynamic-author client 198.18.5.101`,
  `dnac-client-radius-group`, `dnac-radius_198.18.5.101`. Catalyst Center held
  no provisioning record, so stage 08 classified all three switches as new and
  POSTed, and since stage 02 puts ISE `198.18.5.101` into the site's
  `client_and_endpoint_aaa` intent, provisioning tried to write AAA the
  appliance refused to overwrite. Recovery, verified on `198.18.128.22/.23/.24`:
  remove the block in dependency order — accounting, the dot1x/cts lists,
  `aaa server radius dynamic-author`, the group, the named RADIUS server, then
  the `radius-server attribute`/`dead-criteria`/`deadtime` and
  `ip radius source-interface` lines — **keeping `aaa new-model`,
  `aaa authentication login default local` and
  `aaa authorization exec default local` or SSH login dies**; `write memory`,
  because stage 09 reloads and an unsaved removal returns; force a resync with
  `PUT /dna/intent/api/v1/network-device/sync?forceSync=true` and wait for
  `collectionStatus: Managed`, since the controller caches the old running
  config; then re-run stage 08, which completes `failed=0 changed=1`.

  **Assurance stage 08 stopping at "3/5 checks passed" is a Splunk licence stop,
  not a data problem, and the evidence report's own guidance misleads here.**
  The three checks that pass never run a search; the two that fail are the only
  ones that do. `/services/licenser/localslave` shows
  `LocalSearch: DISABLED_DUE_TO_GRACE_PERIOD` against
  `dcloud-lm.splunk.show:8089`, and `/services/messages` gives the reason:
  `LM__FAILED_TO_CONECT_TO_MANAGER … Signature mismatch between license slave …
  pass4SymmKey` — the host is a licence peer of the shared dCloud manager,
  handed over without `[general] pass4SymmKey` reconciled, so it has had no
  successful check-in since 2026-05-09 and the grace period lapsed. It is easy
  to misread because **Settings > Licensing shows no alerts** (licence alerts are
  daily-volume violations tracked on the manager) and enforcement covers only
  non-internal indexes, so `index=_internal`, `| makeresults` and
  `| inputlookup` still work and the instance looks alive. Date the outage from
  `last_manager_contact_success_time`, never from `first failure time=` in the
  message, which restarts with splunkd. KV Store being down on the same host is
  a **second, unrelated fault**: mongod reports `InvalidSSLConfiguration` on
  `/opt/splunk/etc/auth/mycerts/server.pem`, expired 2026-07-22, and validates
  that certificate only at startup, so the expiry stayed invisible for two
  months until the deploy role's closing `splunk restart` exposed it. Do not
  repoint `[sslConfig] serverCert` at Splunk's default certificate — that one
  carries a `BEGIN ENCRYPTED PRIVATE KEY` where the pod's is plain, so
  `sslPassword` becomes load-bearing and a wrong value is fatal to splunkd. Both
  are pod faults to escalate together.

- **bootstrap and repo structure — no playbook runs git, pins have one source of truth, and the guide is published from `/docs`.** *2026-09-22 to 2026-09-25.*
  `playbooks/02_sync_from_git.yml` and
  `roles/script_server_bootstrap/tasks/sync_repo.yml` are both **deleted**.
  Refreshing the checkout is a plain `git pull`, followed by re-running
  `01_bootstrap_script_server.yml` only if a note says a pin moved. Prompted by
  a live failure — `Local modifications exist in the destination: … (force=no)`
  with `ok=29 changed=3`, where packages, the venv, `PATH` and the Galaxy
  collections had all already succeeded and the bootstrap failed anyway over
  uncommitted work — but the pull was worse than a bad error message. The role
  ran from the checkout it was rewriting, at step 6 of 8, having already read
  `requirements.txt`, the Galaxy pins and its own `defaults/main.yml` off disk
  *before* that point, so the pull could not inform the work that followed. All
  it achieved was making `defaults/main.yml` disagree with the task files for
  the rest of the play, since Ansible loads role defaults **once** while
  `include_tasks` re-reads from disk — which is what produced
  `'script_server_image_owner' is undefined` pointing at a task whose name only
  existed in the new commit, with nothing wrong with the variable.

  **Python pins now have one source of truth.** `ansible-core`, `paramiko`,
  `netaddr`, both Catalyst Center SDKs and `rich` had been pinned twice, in
  `ansible-automation/requirements.txt` and again as `script_server_*_version`
  variables in the role; they agreed, but bumping one would have had the role
  silently reinstall a different version over the staged one with a clean-looking
  evidence block. `venv.yml` installs from `requirements.txt` directly now, and
  a missing `requirements.txt` fails the play instead of building an unpinned
  venv. The same discipline applies to Galaxy pins, where the failure is silent
  in both directions: the bootstrap's `files/requirements.yml` is the file that
  actually gets installed, so a higher pin in a collection's own
  `requirements.yml` alone is never applied, and `ansible-galaxy collection
  install` **without `--force` silently skips a collection already present at
  any version** — which is how a `cisco.catalystcenter` bump went unapplied.

  **Three student-facing papercuts fixed.** A clean bootstrap used to end in
  `Command 'ansible-playbook' not found` in the same shell, because `01` appends
  the venv export to the shell startup files and an already-open shell never
  re-reads them; the evidence block's `PATH binaries` line was actively
  misleading, since the check exports `PATH` inside its own task before calling
  `command -v`. The run now closes with an explicit **NEXT** line:
  `exec $SHELL -l` or a new SSH session, then `ansible-playbook --version`.
  `/var/www/iosxe-images` is no longer `root:root`, so a student can `scp` a
  `.bin` straight into the web root with no `sudo` and no publish step. And
  there is one document per audience now: `User Guide/one_cisco_lab.html` became
  `docs/index.html`, published by GitHub Pages from `main` / `/docs` (a space in
  a directory name becomes `%20`, and Pages serves only the root or `docs/`),
  while `GETTING_STARTED.md` was merged into the campus EVPN README, so
  bookmarks to it should become `README.md#before-you-begin`.
