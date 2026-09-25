# 00 — Script server bootstrap

Prepares the **Kali Linux** script server at `198.18.134.12` so every later lab collection can run **on** that host.

This collection runs **on the script server itself**. You SSH in, clone this repository there, and bootstrap the box from its own checkout. Nothing is installed on your laptop, and no playbook reaches across the network to configure another machine.

Connect **Cisco Secure Client / AnyConnect** to the dCloud session first — that is what makes `198.18.134.12` reachable.

Host and URL index: [PseudoCo_Lab_Access_Lookup.md](../../Lab%20Topology/PseudoCo_Lab_Access_Lookup.md). Credentials for this collection and every later playbook come from vault-encrypted [lab_access.yml](../../Lab%20Topology/lab_access.yml) (`script_server` key here). Do not put passwords in playbooks or unencrypted inventory.

## Quick start

```bash
# 1. From your laptop, connect the dCloud VPN, then SSH to the script server
ssh cisco@198.18.134.12

# 2. Clone this repository onto the script server
git clone https://github.com/imanassypov/cisco-one-experience-lab-automation.git
cd cisco-one-experience-lab-automation/ansible-automation/00_scriptserver_bootstrap

# 3. Stage the box. Prompts once for your dCloud POD number.
./stage-script-server.sh

# 4. Bootstrap. Uses the venv directly - nothing to activate.
~/venv/bin/ansible-playbook playbooks/00_preflight.yml
~/venv/bin/ansible-playbook playbooks/01_bootstrap_script_server.yml
```

You can clone anywhere — `~/cisco-one-experience-lab-automation` is only a convention. Every path is derived from where the playbook lives, so a clone under any directory works.

The staging script also writes the repo-root `.vault` for you and seeds `lab.yml` with the pod number you entered, so there is nothing to create by hand. To skip the prompt on an unattended re-run: `LAB_POD_ID=7 ./stage-script-server.sh`.

> Call `ansible-playbook` by its full path until `01` has run — that is the playbook that puts `~/venv/bin` on `PATH`. `01` writes that export to `~/.zshrc`, `~/.bashrc`, `~/.profile` and `~/.zprofile`, but a **shell that is already open never re-reads those files**, so the session you ran the bootstrap from still answers `Command 'ansible-playbook' not found`. Reload it with `exec $SHELL -l`, or open a new SSH session, then confirm with `ansible-playbook --version`. If apt offers to install `ansible-core`, say no: that would be an unpinned copy outside the venv.

## Why a staging script before Ansible

`stage-script-server.sh` exists to solve a chicken-and-egg problem: you cannot run `ansible-playbook` to install Ansible. The script does the minimum needed to get Ansible running, and the bootstrap playbook does everything else.

| Step | Done by | What |
| --- | --- | --- |
| Base packages | `stage-script-server.sh` | `git`, `python3`, `pip`, `venv`, `python3-dev`, `gcc`, `libffi-dev`, `libssl-dev` |
| Virtualenv at `~/venv` | `stage-script-server.sh` | Pins from [`requirements.txt`](../requirements.txt) — `ansible-core`, `paramiko`, `ansible-pylibssh`, `netaddr`, both CatC SDKs, `rich`. The bootstrap role reads that same file, so the shared pins are defined once |
| `.vault` and `lab.yml` | `stage-script-server.sh` | Writes the vault passphrase and the POD number it prompted for |
| Everything else | `01_bootstrap_script_server.yml` | DNS, PATH, Galaxy collections, Genie/pyATS |

The script is idempotent — re-running it is harmless. It refuses to run on anything other than Linux, so running it on your laptop by mistake fails immediately and prints the SSH command you actually wanted.

## What the bootstrap installs

- Lab DNS `198.18.5.102` first (then dCloud `198.18.128.1`) in `/etc/network/interfaces` and `/etc/resolv.conf` so `cat-center.corp.pseudoco.com` resolves
- OS packages, kept deliberately minimal: `git`, `pip`, and the versioned `pythonX.Y-venv`. No compiler and no `-dev` headers — every pinned wheel is prebuilt for this interpreter, and on the dCloud image `libffi-dev` / `libssl-dev` cannot install without dragging `libc6` forward
- The user virtualenv at `~/venv` (Ansible is **not** installed with apt/yum)
- Everything pinned in [`requirements.txt`](../requirements.txt) — `ansible-core`, `paramiko`, `ansible-pylibssh`, `netaddr`, both CatC SDKs, and `rich`, which renders the stage 12 markdown report in the terminal. The role installs from that file rather than repeating the versions, so `stage-script-server.sh` and the bootstrap can never disagree
- `genie` and `pyats`, pinned in the role's `script_server_python_packages` — stage 12 parses every CLI response with Genie, which adds roughly 700 MB. Deliberately not in `requirements.txt`: none of it is needed to run `ansible-playbook`, so staging stays fast
- Pinned CatC Python SDKs (`catalystcentersdk` 3.1.3.0.1, `dnacentersdk` 2.10.6) for appliance 3.1.5 / API profile 3.1.3.0
- Venv CLI binaries on PATH (`~/.bashrc`, `~/.profile`, `~/.zshrc`, `~/.zprofile` — Kali's default shell is zsh) and symlinked into `~/bin`
- Pinned Cisco Galaxy collections — see [`files/requirements.yml`](roles/script_server_bootstrap/files/requirements.yml) for the authoritative versions
- On Kali, disables the HashiCorp apt source if it targets `kali-rolling` (that repo has no Release file and breaks `apt update`)
- Seeds `inventory/group_vars/all/lab.yml` from the tracked example, and never overwrites it afterwards
- An nginx site on port **8080** serving IOS-XE software images to Catalyst Center — see below

## The IOS-XE image server

Campus stage 09 (SWIM) upgrades the fabric switches. Catalyst Center has to pull
the `.bin` from somewhere, and in this pod that somewhere is the script server.

> **Why not import from cisco.com.** Catalyst Center refuses every CCO image
> here with `NCSW10375: … is not the latest or suggested image from cisco`,
> including builds its own catalogue flags `ciscoLatest` or
> `recommended=CISCO`, and `software.cisco.com` answers **HTTP 403** from the
> script server. Serving the file locally sidesteps the CCO catalogue entirely,
> which also means you are not restricted to the handful of builds Cisco
> currently suggests.

The images are **not in git** — they are hundreds of MB each and GitHub rejects
anything over 100 MB. Stage them by hand, exactly like `.vault` and `lab.yml`:

```bash
# From your laptop, into the checkout on the script server
scp iosxe_images/*.bin cisco@198.18.134.12:cisco-one-experience-lab-automation/iosxe_images/
```

Then bootstrap (or re-bootstrap). Every `.bin` found in `iosxe_images/` is
copied to the web root and proved downloadable before the play finishes:

```bash
ansible-playbook playbooks/01_bootstrap_script_server.yml
curl -I http://198.18.134.12:8080/cat9k_iosxe.26.01.02.SPA.bin   # expect 200
```

Browse `http://198.18.134.12:8080/` for a directory listing of what Catalyst
Center can see.

> **Copying straight into the web root also works.** The bootstrap gives
> `/var/www/iosxe-images` to the login user (`cisco`), so you can skip the
> checkout and `scp` a `.bin` directly to it — useful when the file is already
> on the box or you do not want a second copy eating disk:
>
> ```bash
> scp cat9k_iosxe.26.01.02.SPA.bin cisco@198.18.134.12:/var/www/iosxe-images/
> ```
>
> nginx serves it immediately; no re-run needed. Note the bootstrap only
> *publishes* from the checkout, so a file placed here directly is not
> re-created if you ever delete it. If you hit `Permission denied`, the web
> root predates this change — re-run
> `01_bootstrap_script_server.yml --tags image_server` once to take ownership
> of the directory and everything already in it.

| Variable | Default | Purpose |
| --- | --- | --- |
| `script_server_image_http_enabled` | `true` | Set false to skip the image server entirely |
| `script_server_image_http_port` | `8080` | Own port, so nginx's default site is left alone |
| `script_server_image_root` | `/var/www/iosxe-images` | Where the published images live |
| `script_server_image_owner` | `{{ ansible_user_id }}` | Owns the web root and its images, so the student can `scp` into it without `sudo` |
| `script_server_image_source_dir` | `<repo>/iosxe_images` | Where you stage the `.bin` files |

The matching consumer is `swim.import_source: remote` plus `swim.image_base_url`
in `01_campus/evpn/Settings/settings.json`. Point that at this server and stage
11 will import from it.

nginx is installed **only if missing** — it already ships on the dCloud Kali
image, and a needless apt transaction on this box risks the `libc6` breakage
described below.

> **Why so little is installed from apt.** The dCloud image tracks `kali-rolling` and `kali-last-snapshot` at the same time, so apt offers base packages far newer than what is installed — `python3` 3.14 against 3.13, `libc6` 2.43 against 2.40. Asking apt for an already-installed package is an upgrade request, and upgrading `python3` breaks the ~120 installed `python3-*` packages that require an older one. So the bootstrap names as little as possible and never runs `apt --fix-broken install`, which would attempt exactly that system-wide upgrade.

## Playbook sequence

| Playbook | Purpose | Re-runnable |
| --- | --- | --- |
| `00_preflight.yml` | Confirm you are on Linux, the checkout is complete, `.vault` decrypts, and `sudo` works | Yes, read-only |
| `01_bootstrap_script_server.yml` | DNS, packages, venv, PATH, collections, `lab.yml` seed, verification | Yes |

### Updating the checkout is plain git

**No playbook here runs git.** To pick up a lab fix published after you cloned:

```bash
cd ~/cisco-one-experience-lab-automation
git pull
```

Re-run `01_bootstrap_script_server.yml` afterwards only if the update changed a pinned collection or Python package — check the newest file in [`release-notes/`](../../release-notes/), which says so.

There used to be a `02_sync_from_git.yml` that wrapped `ansible.builtin.git`. It was removed because it added confusion without adding anything: it did what `git pull` does, in a way that obscured what was happening, and it encouraged putting the pull inside the bootstrap too. That was actively harmful. The bootstrap runs from the checkout it would have been rewriting, and it reads `requirements.txt`, the Galaxy pins and its own `defaults/main.yml` off disk *before* the point where the pull sat — so the pull could not inform the work that followed it, and all it achieved was making `defaults/main.yml` disagree with the task files for the rest of the play. On top of that, a dirty tree aborted the whole bootstrap after packages, the venv, PATH and the collections had already succeeded.

If `git pull` refuses because you have edited tracked files:

```bash
git status                 # see what changed
git stash                  # keep the changes for later
git checkout -- .          # or discard them
```

`.vault`, `lab.yml` and `iosxe_images/` are gitignored and can never be what is blocking you — untracked and ignored files do not stop a pull.

The bootstrap still seeds `lab.yml` from the tracked example and checks `.vault`, in `tasks/pod_files.yml`. Those two files are gitignored, so no git operation creates or protects them, which is exactly why the role has to.

Later collections (`01_campus` and onward) use the same `00_`, `01_`, … naming inside their own `playbooks/` folders.

## The vault password file

`ansible.cfg` reads the repo-root `.vault` (gitignored) to decrypt `Lab Topology/lab_access.yml`. `stage-script-server.sh` writes it for you with the shared lab passphrase.

Preflight proves the passphrase actually works before anything is changed — a wrong passphrase fails there with a readable message instead of an opaque decrypt error mid-run.

> **This is encryption theatre, on purpose.** `lab_access.yml` is committed **and** the passphrase that opens it is in `stage-script-server.sh`, so anyone with the repository can read every lab credential. That is an acceptable trade for a disposable dCloud pod whose credentials are already public demo values, and it removes a step students routinely got wrong. It is **not** a pattern to copy: a real environment needs a unique passphrase per environment, kept out of the repository and injected from a secret store. Override it here with `VAULT_PASSPHRASE=... ./stage-script-server.sh`.

## After bootstrap

Every later collection runs from this same checkout, with Ansible already on PATH:

```bash
cd ~/cisco-one-experience-lab-automation/ansible-automation/01_campus/evpn/ansible
ansible-playbook playbooks/01_site_hierarchy.yml
```

Confirm `ansible-playbook --version` works in a fresh interactive shell without `source ~/venv/bin/activate` — `path.yml` puts the venv binaries on PATH for both bash and zsh. See the root README for the development workflow.
