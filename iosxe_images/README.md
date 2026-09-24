# iosxe_images

Staging folder for the IOS-XE software images that **campus stage 09 (SWIM)**
installs on the Site-105 switches.

The folder is deliberately empty in git. Drop your `.bin` files here on the
**script server**, then publish them — both steps are described below.

## Why the images are not in the repository

Each image is well over a gigabyte, and GitHub rejects any file above 100 MB.
So the `.bin` files are supplied by hand, the same way `.vault` and
`inventory/group_vars/all/lab.yml` are.

`.gitignore` keeps them out and keeps this folder alive:

```gitignore
iosxe_images/*
!iosxe_images/.gitkeep
!iosxe_images/README.md
```

An empty folder is **not** an error. It only means SWIM has nothing to pull yet,
so stage 09 has nothing to install.

## What to put here

Two files, and the names must match `settings.json` character for character:

```text
iosxe_images/
├── cat9k_iosxe.26.01.02.SPA.bin   ← swim.image_file           (the upgrade)
├── cat9k_iosxe.17.12.08.SPA.bin   ← swim.rollback_image_file  (the fallback)
├── .gitkeep
└── README.md
```

Copy them from your laptop:

```bash
scp cat9k_iosxe.26.01.02.SPA.bin cat9k_iosxe.17.12.08.SPA.bin \
    cisco@198.18.134.12:~/cisco-one-experience-lab-automation/iosxe_images/
```

`scp` works without `sudo` because the bootstrap hands this folder and the web
root to the login user (`script_server_image_owner`, which defaults to whoever
ran the bootstrap).

## How they reach Catalyst Center

Catalyst Center cannot read a folder on the script server, so the bootstrap
serves this folder over HTTP with nginx:

```text
iosxe_images/                       you copy the .bin here
        │
        │  01_bootstrap_script_server.yml  (tasks/http_image_server.yml)
        ▼
/var/www/iosxe-images/              nginx document root
        │
        │  http://198.18.134.12:8080/<file>.bin
        ▼
Catalyst Center                     imports, distributes, activates (stage 09)
```

If you staged the files **before** running the bootstrap, this already happened.
Otherwise re-run only that phase — it is tagged, so nothing else is touched:

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/00_scriptserver_bootstrap
ansible-playbook playbooks/01_bootstrap_script_server.yml --tags image_server
```

Then confirm what Catalyst Center is about to be pointed at is actually
reachable:

```bash
curl -sI http://198.18.134.12:8080/cat9k_iosxe.26.01.02.SPA.bin | head -1
# HTTP/1.1 200 OK
```

## Where each path is defined

The folder you copy into, the folder nginx serves, and the URL Catalyst Center
is given are three separate settings that have to agree:

| Setting | Value | Defined in |
| --- | --- | --- |
| `script_server_image_source_dir` | `<checkout>/iosxe_images` | [`00_scriptserver_bootstrap/roles/script_server_bootstrap/defaults/main.yml`](../ansible-automation/00_scriptserver_bootstrap/roles/script_server_bootstrap/defaults/main.yml) |
| `script_server_image_root` | `/var/www/iosxe-images` | same file |
| `script_server_image_http_port` | `8080` | same file |
| `script_server_image_owner` | the login user | same file |
| `script_server_image_http_enabled` | `true` | same file — set `false` to skip the web server entirely |
| `swim.image_base_url` | `http://198.18.134.12:8080` | [`01_campus/evpn/Settings/settings.json`](../ansible-automation/01_campus/evpn/Settings/settings.json) |
| `swim.image_file`<br>`swim.rollback_image_file` | the two `.bin` names | same `settings.json` block |

Stage 09 joins the last two into the download URL. In
[`roles/swim/tasks/import_and_tag.yml`](../ansible-automation/01_campus/evpn/ansible/roles/swim/tasks/import_and_tag.yml)
it is literally:

```jinja
{{ item.image_base_url }}/{{ item.image_file }}
```

A typo in either half produces the same symptom — Catalyst Center reports it
could not import the image — and the `curl` above is the quickest way to tell
which half is wrong.

## Why the images are served locally instead of from cisco.com

Catalyst Center would normally import software straight from Cisco's catalogue.
That does not work in this pod:

- every image is rejected with `NCSW10375` *"not the latest or suggested image
  from cisco"* — including builds Cisco's own catalogue flags as `ciscoLatest`
  or `recommended=CISCO`
- `software.cisco.com` answers **HTTP 403** from inside the lab

Serving the `.bin` from the script server bypasses the catalogue completely,
which has a useful side effect: **any** image can be used, not only the handful
Cisco currently suggests. That is why `swim.import_source` is `remote` rather
than `CCO`. Switching it back to `CCO` additionally needs Cisco.com credentials
under **System > Settings > Cisco.com Credentials**.

## Troubleshooting

| Symptom | Likely cause | Resolution |
| --- | --- | --- |
| Stage 09 reports it could not import the image | Filename mismatch, or the file was never published | `curl -sI` the URL. 404 means the name or the publish step; connection refused means nginx |
| `curl` returns 404 | The `.bin` is in `iosxe_images/` but not in `/var/www/iosxe-images/` | Re-run the bootstrap with `--tags image_server` |
| `curl` cannot connect | nginx is not running, or the port differs | `sudo systemctl status nginx`, and check `script_server_image_http_port` |
| `scp` says permission denied | The folder is still root-owned from a bootstrap run that predates the ownership fix | Re-run `01_bootstrap_script_server.yml --tags image_server` once to take ownership |
| Stage 09 does nothing at all | Nothing staged here | That is the expected result of an empty folder — stage them and re-run |
| You have no images and need the fabric now | — | Run the pipeline with `-e swim_activate=false` and upgrade later |

## Related

- Stage 09 reference, including phases and knobs:
  [`01_campus/evpn/ansible/README.md`](../ansible-automation/01_campus/evpn/ansible/README.md#stage-09--software-image-management-swim)
- Student walkthrough, Card 1 Step 5:
  [`docs/index.html`](../docs/index.html)
