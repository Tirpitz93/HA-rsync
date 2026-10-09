![rsync logo](rsync/logo.png)

[![Add to Home Assistant][ha-badge]][ha-url]
[![Apache 2.0 License][license-badge]][license-url]

---

This add-on wraps `rsync` over SSH to sync folders between your Home Assistant instance and a remote machine. Whether you're backing up your `/config` directory offsite, pulling media files from a NAS, or keeping a warm standby in sync — if rsync can do it, this add-on can automate it.

Each folder entry in the config can push *or* pull independently, with its own rsync options. The add-on runs, syncs everything, and exits — pair it with an automation to trigger it on a schedule.

## What you'll need

- `rsync` installed on the **remote machine** (if you see `bash: rsync: command not found` in the logs, that's why)
- SSH key-based authentication set up for your user on the remote
- The remote's SSH port reachable from your HA instance

## Getting started

### 1. Add the repository

Click the badge above, or go to **Settings → Add-ons → Add-on Store → ⋮ → Repositories** and paste:

```text
https://github.com/Tirpitz93/HA-rsync#copilot/install-fork-ha-enable-update-urls
```

This URL tracks the isolated fork-installation branch, `copilot/install-fork-ha-enable-update-urls`, rather than the upstream repository.
Home Assistant uses the repository URL you add to fetch updates; the URLs in the metadata are project links.
If you merge these changes into your default branch, you can instead add `https://github.com/Tirpitz93/HA-rsync`.

### 2. Install and configure

After installing, edit the configuration before starting the add-on. At minimum you need `remote_host`, `username`, and at least one folder.

### 3. Copy your public key to the remote

On first run, the add-on generates an Ed25519 key pair and saves it to the path you configured (default: `/ssl/rsync/id_rsa`). You'll find the public key at `/ssl/rsync/id_rsa.pub`. Copy it to your remote:

```bash
ssh-copy-id -i /path/to/id_rsa.pub myuser@192.168.1.100
```

Or paste the contents of `id_rsa.pub` into `~/.ssh/authorized_keys` on the remote. Once that's done, start the add-on and check the logs.

## Testing and updating this fork

- Keep fork-installation changes on `copilot/install-fork-ha-enable-update-urls`; merge or rebase your feature changes onto it to test them in HA.
- For an upstream PR, use a feature branch based on upstream without the fork-installation commit. Cherry-pick only the feature commits, not the fork metadata changes.
- The add-on has no prebuilt `image` configured, so Home Assistant builds it from this repository's Dockerfile when installing or updating.
- For each test update, change `version` in `rsync/config.yaml` to a new version (starting from `0.1.0`), and push your changes to the branch HA tracks.
- In **Settings → Add-ons → Add-on Store → ⋮**, choose **Check for updates**, then open the installed fork add-on and select **Update**. Pushing code without changing the version does not offer an add-on update.
- An upstream installation is separate from this fork. Copy its configuration to the fork and stop the upstream add-on before testing.
- Repository installations use a repository-specific add-on ID, not `local_rsync`. Use the fork's ID (visible in its add-on page URL) in your automations.

## Configuration

```yaml
private_key_file: /ssl/rsync/id_rsa
username: myuser
remote_host: 192.168.1.100
remote_port: 22  # optional
folders:
  - local: /config
    remote: /home/myuser/ha-backup
    direction: push

  - local: /media/music
    remote: /home/myuser/music
    direction: pull
    options: "--archive --compress"
```

### Options

| Key | Required | Default | Description |
| --- | --- | --- | --- |
| `private_key_file` | yes | `/ssl/rsync/id_rsa` | Path to SSH private key. Must be under `/ssl/`. |
| `username` | yes | — | SSH user on the remote machine. |
| `remote_host` | yes | — | IP address or hostname of the remote. |
| `remote_port` | no | `22` | SSH port on the remote. |
| `folders[].local` | yes | — | Local path on Home Assistant to sync. |
| `folders[].remote` | yes | — | Corresponding path on the remote machine. |
| `folders[].direction` | no | `push` | `push` sends local → remote. `pull` receives remote → local. |
| `folders[].options` | no | see below | Custom rsync flags, replacing the defaults entirely. |

Default rsync options when `options` is not set:

```text
--archive --recursive --compress --delete --prune-empty-dirs
```

## Running on a schedule

The add-on runs once and exits — it doesn't loop in the background. To sync automatically, trigger it from a Home Assistant automation:

```yaml
automation:
  alias: Nightly rsync backup
  trigger:
    platform: time
    at: "02:30:00"
  action:
    service: hassio.addon_start
    data:
      addon: local_rsync
```

## Volume access

The add-on can read and write the following HA directories:

| Path | Access |
| --- | --- |
| `/share` | read / write |
| `/config` | read / write |
| `/ssl` | read / write (key storage) |
| `/backup` | read only |
| `/media` | read only |

## Troubleshooting

`Permission denied (publickey)` — The public key hasn't been added to `authorized_keys` on the remote yet.

`Host key verification failed` — The remote's SSH host key changed (e.g. after a reinstall). The add-on uses `StrictHostKeyChecking=accept-new`, so it accepts new hosts automatically but will reject a changed key. Remove the old entry from the container's known hosts and re-run.

`bash: rsync: command not found` — rsync isn't installed on the remote machine.

One folder fails but others don't run — This was fixed in a recent update. The add-on now logs the failure and continues with remaining folders, then exits with a non-zero code at the end.

---

## License & attribution

Released under the [Apache License 2.0](LICENCE).

Forked from the [rsync add-on by Markus Poeschl](https://github.com/Poeschl-HomeAssistant-Addons/rsync) (Apache 2.0). Changes include security hardening, Alpine upgrade, and updated documentation. See [NOTICE](NOTICE) for the full attribution.

[ha-badge]: https://img.shields.io/badge/Add%20to-Home%20Assistant-41BDF5?logo=home-assistant&style=flat-square
[ha-url]: https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FTirpitz93%2FHA-rsync%23copilot%2Finstall-fork-ha-enable-update-urls
[license-badge]: https://img.shields.io/badge/license-Apache%202.0-blue?style=flat-square
[license-url]: LICENCE
