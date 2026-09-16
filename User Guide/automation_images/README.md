# automation_images

Screenshots and diagrams for the **Automated (Infrastructure as Code)** path in
`one_cisco_lab.html`. The HTML references these with a relative path, exactly like
the existing `one_cisco_lab_images/` folder:

```html
<img class="img-fluid" role="presentation" src="automation_images/a1-inventory-graph.png" alt="..." width="865" height="...">
```

Upload this folder alongside the revised HTML so the references resolve.

## Diagrams (already committed — do not replace)

| File | Notes |
|---|---|
| `template-model.mmd` | Mermaid source for the DEFN / FUNC / FABRIC data-flow diagram |
| `template-model.png` | Rendered diagram used in card **A4** |

Regenerate after editing the `.mmd`:

```bash
mmdc -i automation_images/template-model.mmd -o automation_images/template-model.png --scale 3
/usr/bin/sips -Z 4000 automation_images/template-model.png --out automation_images/template-model.png
/usr/bin/sips -g pixelWidth -g pixelHeight automation_images/template-model.png
ls -lh automation_images/template-model.png   # must stay under 1.2 MB
```

## Screenshots still to capture

Placeholders are already wired into the HTML with `data-missing`, so the guide renders a
grey chip until the file is added. To activate an image, drop the PNG in this folder and
change its tag from `src="" data-missing="NAME.png"` to `src="automation_images/NAME.png"`.

### A1 — Prepare Workstation & Script Server

| Filename | What to capture |
|---|---|
| `a1-vpn-connected.png` | Cisco Secure Client showing the dCloud session connected |
| `a1-stage-script.png` | Terminal on the script server after `./stage-script-server.sh` completes |
| `a1-bootstrap-complete.png` | `PLAY RECAP` of `01_bootstrap_script_server.yml` |
| `a1-inventory-graph.png` | `ansible-inventory --graph` output on the script server |

### A2 — Run the Pipeline

| Filename | What to capture |
|---|---|
| `a2-stage01-sites.png` | Catalyst Center **Design > Network Hierarchy** after stage 01 |
| `a2-stage06-templates-project.png` | **Template Hub** with CLI project `Site-105` populated |
| `a2-stage09-composite-deploy.png` | Terminal summary table at the end of stage 09 |

### A3 — Verify Intent

| Filename | What to capture |
|---|---|
| `a3-evidence-html-report.png` | `evidence/stage10-verification.html` open in a browser |
| `a3-glow-md-report.png` | `glow -p evidence/stage10-verification.md` in the terminal |

### A4 — Template Model

| Filename | What to capture |
|---|---|
| `a4-template-hub-project.png` | Template Hub, project `Site-105`, showing DEFN / FUNC / FABRIC templates side by side |
| `a4-composite-members.png` | Composite `BGP-EVPN-BUILD.j2` with its ordered member list |

### A5 — Extending the Fabric

| Filename | What to capture |
|---|---|
| `a5-git-diff.png` | `git diff` of a DEFN edit |
| `a5-catc-version-history.png` | Catalyst Center template version history showing the git commit message as the version comment |
| `a5-new-vlan-verified.png` | Stage 10 report row proving the new VLAN/VRF landed |

### WLC (automated path)

| Filename | What to capture |
|---|---|
| `a6-wlc-wlan-summary.png` | 9800 GUI **Configuration > Tags & Profiles > WLANs** with the pipeline-created SSID |
| `a6-ap-registered.png` | 9800 **Configuration > Wireless > Access Points** with the AP registered |
| `a6-ap-tag-summary.png` | `show ap tag summary` showing Catalyst Center-generated site/policy tags |

## Conventions

- Width **865 px** for full-width screenshots (matches the rest of the guide).
- PNG only. Keep each file under 1.2 MB.
- Redact pod numbers only if they would confuse; the guide already tells students their
  pod number differs.
