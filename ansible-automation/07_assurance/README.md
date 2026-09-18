# 07 — Assurance

Operational assurance for the fabrics built by the earlier collections. Where `01_campus`
answers *"did the intent deploy?"*, this collection answers *"is the fabric healthy right now?"*

| Subfolder | Track | Status |
| --- | --- | --- |
| [splunk_evpn](splunk_evpn/) | Campus EVPN/VXLAN streaming telemetry → OpenTelemetry → Splunk dashboards | Implemented |

The Splunk track turns IOS-XE Model-Driven Telemetry from the Site 105 EVPN fabric into
role-aware health dashboards. Playbooks live in [splunk_evpn/ansible](splunk_evpn/ansible/)
(`ansible.cfg`, inventory, and numbered playbooks).

## Relationship to 01_campus

The two collections share one switch: the telemetry subscriptions that feed Splunk are
rendered by the same Catalyst Center template pipeline that builds the fabric.

```
01_campus/evpn  ──  Settings/settings.json  ──  telemetry.splunk.receiver_ip
                                                        │
                    stage 06 template_sync ─────────────┤
                    stage 09 deploy_composite           │  pushes `telemetry ietf
                                                        │  subscription` to the switches
                                                        ▼
07_assurance/splunk_evpn  ──  collector + index + HEC + dashboards on 198.18.5.109
```

Set `telemetry.splunk.receiver_ip` in
[`01_campus/evpn/Settings/settings.json`](../01_campus/evpn/Settings/settings.json), re-run
campus stages 06 and 09, then run this collection. Leaving the receiver IP empty is the
supported way to keep the fabric silent.
