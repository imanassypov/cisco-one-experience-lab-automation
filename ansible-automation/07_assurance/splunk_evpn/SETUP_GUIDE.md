# Setup Guide — manual equivalent

Everything here is automated by [`ansible/playbooks/00_assurance_deploy.yml`](ansible/playbooks/00_assurance_deploy.yml).
This guide exists for two reasons: to explain *what* the playbooks do to the Splunk host,
and to let you recover by hand when a stage fails partway.

Run the playbooks instead unless you have a reason not to. See the
[README](README.md) for the automated path.

| Stage | Playbook | Manual equivalent |
| --- | --- | --- |
| 01 | `01_preflight.yml` | [Check the host](#1-check-the-host) |
| 02 | `02_splunk_index_hec.yml` | [Create the index and HEC token](#2-create-the-index-and-hec-token) |
| 03 | `03_build_collector.yml` | [Build otelcol-yangfix](#3-build-otelcol-yangfix) |
| 04 | `04_deploy_collector.yml` | [Configure and start the collector](#4-configure-and-start-the-collector) |
| 05 | `05_render_lookups.yml` | [Populate the lookups](#5-populate-the-lookups) |
| 06 | `06_deploy_splunk_app.yml` | [Install the app](#6-install-the-app) |
| 07 | `07_enable_fabric_telemetry.yml` | [Configure the fabric](#7-configure-the-fabric) |
| 08 | `08_verify_assurance.yml` | [Verify](#8-verify) |

All commands run on the Splunk host (`198.18.5.109`) unless stated otherwise.

## 1. Check the host

```bash
/opt/splunk/bin/splunk status splunkd          # expect "splunkd is running"
systemctl cat splunk-otel-collector.service    # does the unit exist?
ss -lntp | grep 57444                          # expect no output
command -v go ocb                              # needed only for a local build
```

## 2. Create the index and HEC token

The index **must** be a metrics index. An event index accepts the collector's HTTP POSTs
and then silently discards every metric point, which looks exactly like a dead collector.

```bash
/opt/splunk/bin/splunk add index evpn_assurance -datatype metric -auth <user>:<pass>

/opt/splunk/bin/splunk http-event-collector enable \
  -uri https://127.0.0.1:8089 -enable-ssl 1 -port 8088 -auth <user>:<pass>

/opt/splunk/bin/splunk http-event-collector create evpn-collector \
  -uri https://127.0.0.1:8089 \
  -description "OpenTelemetry YANG telemetry from the campus EVPN fabric" \
  -index evpn_assurance -indexes evpn_assurance -auth <user>:<pass>
```

Confirm the datatype took, then keep the token for step 4:

```bash
curl -sk -u <user>:<pass> \
  'https://127.0.0.1:8089/services/data/indexes/evpn_assurance?output_mode=json' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["entry"][0]["content"]["datatype"])'
```

## 3. Build otelcol-yangfix

The stock `yanggrpcreceiver` drops numeric YANG list keys (`vni`, `evni`, `vlan-id`), so
every per-VNI panel comes back empty. Full analysis:
[`otel-collector/yanggrpcreceiver-numeric-key-issue.md`](otel-collector/yanggrpcreceiver-numeric-key-issue.md).

Needs **Go 1.25+** and **ocb v0.150.0**. The lab Splunk appliance usually has neither, so
build on the script server or your laptop and copy the result over.

```bash
mkdir -p /tmp/otelbuild/src && cd /tmp/otelbuild
cp <repo>/ansible-automation/07_assurance/splunk_evpn/otel-collector/builder.yaml .
tar -xzf <repo>/ansible-automation/07_assurance/splunk_evpn/otel-collector/receiver_yang_26_05_27.tar.gz -C ./src
ocb --config builder.yaml
```

`builder.yaml` pins collector core v0.150.0 and replaces the upstream receiver module with
`../src/receiver/yanggrpcreceiver`. That path ends up in `_build/go.mod` verbatim, so Go
resolves it relative to `_build/` rather than to your working directory — keep
`builder.yaml` and `src/` as siblings or the build cannot find the patched source.

Install it on the Splunk host:

```bash
sudo install -o root -g root -m 0755 ./_build/otelcol-yangfix /usr/local/bin/otelcol-yangfix
# An ocb-built distribution has no --version flag. Listing components proves the
# patched receiver is actually in the binary, which matters more anyway.
/usr/local/bin/otelcol-yangfix components | grep yang_grpc
```

## 4. Configure and start the collector

Render [`otel-collector/agent_config.yaml.j2`](otel-collector/agent_config.yaml.j2) by hand
— substitute the HEC token from step 2 — and write it to `/etc/otel/collector/agent_config.yaml`
with mode `0640`, owned by root. The file carries a live credential.

> **The HEC endpoint must be loopback.** Splunk and the collector share this host; the
> exporter must not leave the box and come back.

Point systemd at the custom binary. Blanking `ExecStart` first is required — systemd
appends otherwise:

```bash
sudo mkdir -p /etc/systemd/system/splunk-otel-collector.service.d
sudo tee /etc/systemd/system/splunk-otel-collector.service.d/override.conf >/dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/local/bin/otelcol-yangfix --config=${SPLUNK_CONFIG}
EOF

echo 'SPLUNK_CONFIG=/etc/otel/collector/agent_config.yaml' \
  | sudo tee /etc/otel/collector/splunk-otel-collector.conf >/dev/null

sudo systemctl daemon-reload
sudo systemctl restart splunk-otel-collector.service
```

> **Expect a ~90 second gap.** The collector does not drain its gRPC streams on `SIGTERM`,
> so systemd waits out `TimeoutStopSec` and force-kills it before the new process listens.

Check it:

```bash
systemctl show -p ExecStart splunk-otel-collector.service    # must name otelcol-yangfix
sudo journalctl -u splunk-otel-collector --since '5 min ago' | grep 'Everything is ready'
ss -lntp | grep 57444
```

### Rolling back to the stock collector

```bash
sudo rm /etc/systemd/system/splunk-otel-collector.service.d/override.conf
sudo systemctl daemon-reload && sudo systemctl restart splunk-otel-collector.service
```

Numeric YANG keys will start dropping again.

## 5. Populate the lookups

Run this one on the control node rather than by hand — it derives both CSVs from the same
`DEFN-*.j2` files that built the fabric:

```bash
cd ansible-automation/07_assurance/splunk_evpn/ansible
ansible-playbook playbooks/05_render_lookups.yml
```

If you must write them manually, the columns are:

```
evpn_device_inventory.csv   source,hostname,ip_address,loopback,site,role,description
evpn_segment_inventory.csv  vlan,l2vni,l3vni,vrf,segment_name,overlay_leaves,access_leaves
```

`hostname` **must** equal the `cisco.node_id` dimension the collector emits — the Catalyst
Center inventory hostname, which is the IOS hostname plus `ip domain name`. Get it wrong
and every dashboard panel renders correctly and returns nothing.

## 6. Install the app

```bash
# On the control node
./packaging/build-app.sh          # → packaging/dist/campus_evpn_assurance-<version>.spl

# On the Splunk host
sudo /opt/splunk/bin/splunk install app /tmp/campus_evpn_assurance-<version>.spl \
  -update 1 -auth <user>:<pass>
sudo /opt/splunk/bin/splunk restart -auth <user>:<pass>
```

Confirm the build number actually changed — Splunk keeps serving a cached app if an
install half-fails:

```bash
grep '^build' /opt/splunk/etc/apps/campus_evpn_assurance/default/app.conf
```

## 7. Configure the fabric

Do **not** paste subscriptions onto the switches. They are rendered by
`FABRIC-TELEMETRY-SPLUNK.j2` in the campus collection, driven by `telemetry.splunk` in
`01_campus/evpn/Settings/settings.json`:

```bash
cd ansible-automation/01_campus/evpn/ansible
ansible-playbook playbooks/06_template_sync.yml
ansible-playbook playbooks/09_deploy_composite.yml
ansible-playbook playbooks/11_verify_intent.yml
```

Subscriptions land in the 40101–40121 band, deliberately above the range Catalyst Center
uses for its own dynamic subscriptions (< 10000).

Two IOS-XE parser constraints worth knowing if you ever hand-edit the templates:

- XPaths must be plain and absolute (`/nve-oper-data/nve-oper`). Namespace-prefixed forms
  with a colon are rejected.
- Use the `receiver ip address` form, not named receivers. Named receivers report
  "Transport requested" and never flow.

## 8. Verify

```bash
cd ansible-automation/07_assurance/splunk_evpn/ansible
ansible-playbook playbooks/08_verify_assurance.yml
```

By hand:

```bash
# Fabric sessions on the receiver port — expect one per fabric node
ss -tn state established '( sport = :57444 )' | tail -n +2 | wc -l

# HEC export failures — expect 0
curl -s localhost:8888/metrics | grep otelcol_exporter_send_failed_metric_points
```

In Splunk, the join that matters:

```spl
| mstats latest("cisco.cp-vnis.") WHERE index=evpn_assurance BY "cisco.node_id"
| `evpn_lookup`
```

Rows with `site` and `role` populated mean the lookup join works. Rows with those columns
empty mean `cisco.node_id` does not match the device inventory — re-run stage 05.

Then open **Campus EVPN Assurance** in Splunk Web: Summary, Details and Alerts.
