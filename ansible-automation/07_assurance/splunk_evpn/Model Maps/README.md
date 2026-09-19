# Model Maps — Cisco EVPN CLI ⇄ Operational Model Mappings

This folder contains the Cisco "CLI to Operational Model Mapping" reference PDFs for the EVPN/VXLAN
features used in the **Campus BGP EVPN Splunk Assurance** project, together with clean, readable
Markdown transcriptions of each.

Each mapping document ties three representations of the same operational data together:

| Representation | What it is | Where it is used |
| --- | --- | --- |
| **CLI field** | The human-readable `show …` output | Operator troubleshooting |
| **OpenConfig (OC) xpath** | Vendor-neutral `openconfig-network-instance` model | Cross-vendor tooling |
| **Cisco native YANG xpath** | `Cisco-IOS-XE-*-oper` model | **Streamed by the OTel `yang_grpc` receiver** |
| **TDL path** | Internal Telemetry Definition Language encoder path (`ios_oper/…`) | On-box encoder |

> **Platform scope:** Every feature in this folder is available **only on CAT9k platforms**.

---

## Documents

| Markdown transcription | Source PDF(s) | Model container(s) |
| --- | --- | --- |
| [NVE-Component-Model-Map.md](NVE-Component-Model-Map.md) | `EVPN-CLI to Operational Model Mapping for NVE component-270526-203607.pdf` | `nve-oper`, `nve-vni-oper`, `nve-peer-oper`, `nve-oper-counters`, `nve-vni-oper-counters` |
| [EVPN-Manager-Component-Model-Map.md](EVPN-Manager-Component-Model-Map.md) | `…EVPN Manager Component-270526-194354.pdf` | `evpn-inst` (EVI, VLAN, Pseudoport, Peer) |
| [EVPN-Route-Statistics-Model-Map.md](EVPN-Route-Statistics-Model-Map.md) | `…EVPN Route Statistics-270526-203721.pdf` (also appended to the Manager PDF) | `evpn-stats/evpn-vni-rt-cnt` |

### Note on the source PDFs

Originally there were **four PDFs** but only **three distinct mapping documents**. The redundant
export has been removed, leaving **three PDFs**:

- The two **EVPN Manager Component** PDFs (`-194354` and `-203647`) were **content-identical
  exports** — both contained the EVPN Manager Component mapping **followed by** an appended copy of
  the EVPN Route Statistics mapping. The `-203647` duplicate was **deleted**; `-194354` is kept.
- The standalone **EVPN Route Statistics** PDF (`-203721`) is that same Route Statistics mapping on
  its own.

The Markdown files de-duplicate this: the Route Statistics content lives once in
[EVPN-Route-Statistics-Model-Map.md](EVPN-Route-Statistics-Model-Map.md).

---

## How these mappings feed the Splunk pipeline

![Pipeline flow: Cisco native YANG → MDT gRPC dial-out → OTel Collector → splunk_hec → Splunk index → dashboards](../images/pipeline-flow.png)

The dashboards key off the **Cisco native YANG xpaths** documented here (encoded as `cisco.encoding_path`
dimensions in Splunk). Use these tables to find the exact leaf behind any panel value. For the full
telemetry primer (MDT, OTel, worked metric example), see [`../README.md`](../README.md).

---

## Known telemetry caveats (cross-references)

| Topic | Where documented |
| --- | --- |
| Numeric YANG list keys (`vni`, `evni`, `vni-id`) — **fixed upstream** in `otelcol-contrib` 0.161.0, which is why that version is a floor | [`../otel-collector/yanggrpcreceiver-numeric-key-issue.md`](../otel-collector/yanggrpcreceiver-numeric-key-issue.md) |
| Releases up to v0.155.0 drop numeric list keys — historical, and the reason for the pin | [`../otel-collector/README.md`](../otel-collector/README.md) |
| `cp-vnis` / top-level `rmac` deprecated in 17.18, replaced by `peer-vni-group/{vni,evni,rmac}` | [NVE-Component-Model-Map.md → Version-gating summary](NVE-Component-Model-Map.md#version-gating-summary-1718) |
| EVPN route-stat leaves are cumulative Update/Delete counters (take a delta in Splunk) | [EVPN-Route-Statistics-Model-Map.md → Telemetry note](EVPN-Route-Statistics-Model-Map.md#why-this-matters-for-the-splunk-evpn-assurance-pipeline) |
| Collector configuration & dimension-model migration | [`../otel-collector/README.md`](../otel-collector/README.md) |

---

## Regenerating these transcriptions

The Markdown files were produced from the PDFs (the multi-column PDF layout makes direct copy/paste
unreliable). To re-extract a PDF to Markdown for verification:

1. Convert the PDF to Markdown (e.g. via the `markitdown` tool or `markitdown <file.pdf>`).
2. Reconcile the per-section mapping tables (the multi-column layout interleaves rows — verify each
   `Id`, YANG xpath, and "Mapped show CLI" value against the rendered PDF).
3. Keep the column order **OpenConfig xpath → Cisco YANG xpath → type → TDL path → CLI → comments**
   so the files stay diff-friendly.

## Regenerating diagrams

Pipeline and lifecycle diagrams live in [`../images/`](../images/). After editing a `.mmd` file
there, regenerate PNGs with:

```bash
cd "../images"
./regenerate-diagrams.sh
```

See [`../images/README.md`](../images/README.md) for the full asset list.
