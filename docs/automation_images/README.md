# automation_images

Screenshots and diagrams for the **Automated (Infrastructure as Code)** path in
`../index.html` — the lab guide, which lives at `docs/index.html` so GitHub Pages
serves it from the repository root. The HTML references these with a relative path:

```html
<img class="img-fluid" role="presentation" src="automation_images/a1-inventory-graph.png" alt="..." width="865" height="...">
```

> **The other image folder is not in this repository.** `index.html` came out of the
> course platform and still points 312 unique images at `one_cisco_lab_images/`, a
> sibling folder that was never committed. Those render broken both locally and on
> Pages. Everything under `automation_images/` resolves normally; nothing here depends
> on the missing folder.

## Diagrams (already committed — do not replace)

| File | Notes |
|---|---|
| `pipeline-subway-map.mmd` | Mermaid source for the subway-style pipeline map |
| `pipeline-subway-map.png` | Rendered map used in card **1** |
| `template-model.mmd` | Mermaid source for the DEFN / FUNC / FABRIC data-flow diagram |
| `template-model.png` | Rendered diagram used in card **4** |
| `evpn-dhcp-walkthrough.mmd` | Mermaid source for the DHCP relay round-trip sequence diagram |
| `evpn-dhcp-walkthrough.png` | Rendered diagram used in the optional **EVPN Fabric — DHCP Walkthrough** section (`#page-9010`) |
| `assurance-pipeline.mmd` | Mermaid source for the build → assure telemetry pipeline |
| `assurance-pipeline.png` | Rendered diagram used in the **Splunk EVPN Assurance** section (`#page-9020`) |

## Screenshots — Splunk EVPN Assurance

Captured from the source project's reference fabric, so the device names are the CML
six-node fabric rather than Site 105. They illustrate panel layout, not lab data.
Downscaled to 2400 px on the long edge to stay inside the GitHub limits.

| File | Shows |
|---|---|
| `assurance-dashboard-executive.png` | Summary view — fabric-wide scorecards, BGP trends, VRF Sankey |
| `assurance-dashboard-leafs.png` | Details view filtered to leaf nodes |
| `assurance-dashboard-alerts.png` | Alerts view |

Regenerate after editing a `.mmd` — substitute the diagram name:

```bash
mmdc -i automation_images/<name>.mmd -o automation_images/<name>.png --scale 3
/usr/bin/sips -Z 4000 automation_images/<name>.png --out automation_images/<name>.png
/usr/bin/sips -g pixelWidth -g pixelHeight automation_images/<name>.png
ls -lh automation_images/<name>.png   # must stay under 1.2 MB
```

Commit the `.mmd` and its `.png` together.

> **Puppeteer gotcha.** `mmdc` drives headless Chrome through Puppeteer and fails with
> `Could not find Chrome` if the browser was never downloaded into `~/.cache/puppeteer`.
> Install it with `npx --yes puppeteer browsers install chrome`, then pass the binary
> explicitly if `mmdc` still cannot find it:
>
> ```bash
> echo '{"executablePath":"<path under ~/.cache/puppeteer>"}' > /tmp/puppeteer-config.json
> mmdc -p /tmp/puppeteer-config.json -i automation_images/<name>.mmd -o automation_images/<name>.png --scale 3 -b white
> ```

> **Sequence-diagram gotcha.** A `Note over X` attached to the leftmost or rightmost
> participant renders outside the SVG canvas and gets clipped when the PNG is cropped.
> Span two participants instead — `Note over SD,DH` — so the box is centred inside the
> drawing area.

> **Subway map gotcha.** Its four rows are linked *subgraph-to-subgraph*
> (`LINE1 --> LINE2`), not node-to-node. Linking across subgraphs makes Mermaid
> discard each subgraph's `direction LR` and stack all sixteen stations into one
> vertical ladder — the render silently becomes 956×4000 instead of 4000×2255.
> If you add a row, keep the subgraph-level links.

## Screenshots already captured

| File | Shows | Used in |
|---|---|---|
| `a1-vpn-connected.png` | Cisco Secure Client with AnyConnect VPN connected to `dcloud-rtp-anyconnect.cisco.com`, Zero Trust Access enrolled, Umbrella active | Card **1**, Step 1 |
| `a1-jumphost-web-rdp.png` | dCloud **Servers > Jumphost1** panel with the **Web RDP** and **VM Console** buttons — the browser-only way in for a laptop that cannot install Secure Client | Card **1**, Step 1 |
| `a1-stage-script.png` | `./stage-script-server.sh` completing: venv at `/home/cisco/venv`, pinned packages, `.vault` created, POD number prompt answered | Card **1**, Step 3 |
| `a1-bootstrap-complete.png` | The `Display bootstrap evidence` block from `01_bootstrap_script_server.yml` — ansible-core version, PATH binaries, DNS, vault path, collection versions | Card **1**, Step 4 |
| `a4-template-hub-project.png` | **Design > CLI Templates** filtered to project `Site-105`, 25 templates, composite first | Card **4** |

> **Name a screenshot for the placeholder it fills, not for what you called it
> when you took it.** Both card 1 terminal shots arrived named the other way
> round — the file called `bootstrap_complete.png` was the staging script, and
> `staging_server_complete.png` was the bootstrap evidence block. Check the
> content against the `data-missing` name before wiring it in.

> **Why the jumphost shot is cropped.** It arrived showing the Remote Access
> block — RDP address, domain username and password. Those are not secrets here:
> `C1sco12345` is the shared dCloud lab password and the guide prints it
> throughout by design. The block was cut simply because it adds nothing to the
> point being made, which is *where the Web RDP button is*. Credentials belong
> in the Environment Access tables, not repeated in a screenshot.

## Screenshots still to capture

Placeholders are already wired into the HTML with `data-missing`, so the guide renders a
grey chip until the file is added. To activate an image, drop the PNG in this folder and
change its tag from `src="" data-missing="NAME.png"` to `src="automation_images/NAME.png"`.

The `aN-` filename prefix records which card a shot belongs to. It predates the
renumbering of the Infrastructure as Code cards from `A1`–`A7` to `1`–`7`; the files
keep the old prefix so the `data-missing` placeholders already in the HTML stay valid.

### Card 1 — Prepare Workstation & Script Server

All four are captured. Nothing outstanding for this card.

> Do not add a screenshot of output the guide already prints as text. The
> `ansible-inventory --graph` shot was dropped for that reason: the expected
> output is in the guide as a code block, which a student can copy, search and
> compare against — a picture of the same text can do none of that.

### Card 2 — Run the Pipeline

| Filename | What to capture |
|---|---|
| `a2-stage01-sites.png` | Catalyst Center **Design > Network Hierarchy** after stage 01 |
| `a2-stage06-templates-project.png` | **Template Hub** with CLI project `Site-105` populated |
| `a2-stage09-composite-deploy.png` | Terminal summary table at the end of stage 10 (filename kept from the pre-renumber layout) |

### Card 3 — Verify Intent

| Filename | What to capture |
|---|---|
| `a3-evidence-html-report.png` | `evidence/stage12-verification.html` open in a browser |
| `a3-md-report.png` | `python -m rich.markdown evidence/stage12-verification.md \| less -R` in the terminal |

### Card 4 — Template Model

| Filename | What to capture |
|---|---|
| `a4-composite-members.png` | Composite `BGP-EVPN-BUILD.j2` with its ordered member list |

### Card 5 — Extending the Fabric

| Filename | What to capture |
|---|---|
| `a5-git-diff.png` | `git diff` of a DEFN edit |
| `a5-catc-version-history.png` | Catalyst Center template version history showing the git commit message as the version comment |
| `a5-new-vlan-verified.png` | Stage 12 report row proving the new VLAN/VRF landed |

### Card 6 — WLC (automated path)

| Filename | What to capture |
|---|---|
| `a6-wlc-wlan-summary.png` | 9800 GUI **Configuration > Tags & Profiles > WLANs** with the pipeline-created SSID |

`a6-ap-registered.png` and `a6-ap-tag-summary.png` are no longer wanted — the guide carries the real `show ap summary` and `show ap tag summary` output inline instead.

## Conventions

- Width **865 px** for full-width screenshots (matches the rest of the guide).
- PNG only. Keep each file under 1.2 MB.
- Redact pod numbers only if they would confuse; the guide already tells students their
  pod number differs.
