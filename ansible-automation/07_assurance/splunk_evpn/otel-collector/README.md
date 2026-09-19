# OTel Collector — Campus BGP EVPN Telemetry Pipeline

This folder holds the collector configuration for the assurance pipeline. The collector
itself is upstream `otelcol-contrib`, installed from its official release package — there
is no fork, no patch and no build step.

> **Deployment is automated.** Stage 03 of [`../ansible/playbooks`](../ansible/playbooks/)
> installs the package; stage 04 renders the config and restarts the service. This README
> explains what those stages do and how to troubleshoot them.

> **Context for network engineers:** if you are new to OpenTelemetry or MDT, read the
> parent [`README.md`](../README.md) before tuning this collector.

## Contents

| File | Purpose |
|---|---|
| [`agent_config.yaml.j2`](agent_config.yaml.j2) | Jinja template for the live collector config. Rendered to `/etc/otelcol-contrib/config.yaml` by the `otel_collector_deploy` role. |
| [`yanggrpcreceiver-numeric-key-issue.md`](yanggrpcreceiver-numeric-key-issue.md) | Why the version floor exists. Historical, but load-bearing. |
| `README.md` | This document. |

## Overview

```
Site 105 EVPN fabric (3)                  Splunk host 198.18.5.109
  Site_105-Leaf1                   gRPC   ┌───────────────────────────────────────┐
  Site_105-Leaf2                dial-out  │  otelcol-contrib.service              │
  Site_105-Border-Spine ────────────────▶ │   receiver: yang_grpc  :57444         │
                                          │   receiver: hostmetrics               │
  device config (rendered by              │   processor: batch                    │
  FABRIC-TELEMETRY-SPLUNK.j2):            │   exporter: splunk_hec ──┐            │
  "receiver ip address                    └──────────────────────────┼────────────┘
   198.18.5.109 57444                                                │ https://localhost:8088
   protocol grpc-tcp"                                                ▼
                                                        Splunk HEC → index=evpn_assurance (metric)
```

| Item | Value |
|---|---|
| Host | `198.18.5.109` (`splunk.corp.pseudoco.com`) |
| Package | `otelcol-contrib` **≥ 0.161.0** from [opentelemetry-collector-releases](https://github.com/open-telemetry/opentelemetry-collector-releases/releases) |
| Binary | `/usr/bin/otelcol-contrib` |
| systemd unit | `otelcol-contrib.service` (owned by the package) |
| Live config path | `/etc/otelcol-contrib/config.yaml` |
| YANG gRPC receiver | `yang_grpc` on `0.0.0.0:57444`, transport tcp |
| Exporter | `splunk_hec` → `https://localhost:8088/services/collector` (loopback — the collector and Splunk share this host) |
| Target index | `evpn_assurance` (metric) |

## The version floor

`otel_package_version` is a **floor, not a preference**.

| Release | `extractKeys` behaviour |
|---|---|
| ≤ v0.155.0 | Key extraction gated on the protobuf value being a string — numeric YANG list keys (`vni`, `evni`, `vlan-id`) silently dropped |
| ≥ v0.161.0 | `formatValueToString(subField)` with no type gate — numeric keys emitted as dimensions |

Anything older produces dashboards that render perfectly and show nothing on every per-VNI
panel, because all the per-VNI series collapse into one. Full analysis in
[`yanggrpcreceiver-numeric-key-issue.md`](yanggrpcreceiver-numeric-key-issue.md).

The receiver is **alpha** stability upstream, so verify after bumping rather than assuming.
Stage 08 checks that metrics still join to the device inventory, which is exactly the
symptom a dimension change would produce.

## Troubleshooting

```bash
# Is it running, and which version?
systemctl status otelcol-contrib
otelcol-contrib --version

# Is yang_grpc actually in this build? The core distribution does not carry it.
otelcol-contrib components | grep yang_grpc

# Why did it fail to start?
sudo journalctl -u otelcol-contrib -n 50 --no-pager

# Are the fabric nodes connected?
ss -tn state established '( sport = :57444 )'

# Is it managing to write to Splunk? Expect 0.
curl -s localhost:8888/metrics | grep otelcol_exporter_send_failed_metric_points
```

A config change needs a restart:

```bash
sudo systemctl restart otelcol-contrib
```

Expect a telemetry gap. The fabric holds long-lived gRPC streams that do not drain on
`SIGTERM`, so systemd waits out `TimeoutStopSec` before the new process starts listening.
