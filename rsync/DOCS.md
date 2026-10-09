## Precondition

Make sure to have `rsync` installed on the remote machine. In case the addon gives you an `bash: rsync: command not found` in the logs `rsync` is missing there.

## Key files

The addon generates its own key files when no file is found at the specified location. If you use your own key make sure it is passwordless.

## Config

Example config:

```yaml
private_key_file: /ssl/rsync/id_rsa
username: user
folders:
  - local: /config
    remote: /home/user/config-target
    direction: push
  - local: /media/playlists
    remote: /home/user/cool-playlists
    options: '--archive --recursive --compress'
    direction: pull
remote_host: ''

```

### `private_key_file`

The private key for the authentification on the remote machine. It specifies also the location of the generated key-pair if no key file is found.
The location of the file is fixed to the `/ssl` volume.

### `username`

The username for the user on the remote machine the key is accepted.

### `folders`

The list of folders you want to sync with the remote machine.

### `folders` - `local`

The local folder for rsync.

### `folders` - `remote`

The remote folder for rsync

### `folders` - `options` (optional)

Use your own options for rsync. This string is replacing the default one and get directly to rsync. The default is `--archive --recursive --compress --delete --prune-empty-dirs`.

### `folders` - `direction` (optional)

Specify the direction of synchronization for each folder:

- `push`: Copy from Home Assistant to the remote machine (default)
- `pull`: Copy from the remote machine to Home Assistant

### `remote_host`

The ip or host of the remote machine you want to connect to.

### `remote_port` (optional)

The ssh port on the remote machine. If not set the default `22` is assumed.

## Home Assistant sensors

The add-on publishes sensor states through the Home Assistant API. They are created automatically the first time the add-on runs; no REST sensor, MQTT broker, or additional Home Assistant configuration is required.

| Entity | Description |
| --- | --- |
| `sensor.rsync_status` | `running`, `idle` after success, or `error`; includes last run start and end timestamps. |
| `sensor.rsync_bytes_transferred` | Bytes transferred during the current run. |
| `sensor.rsync_transfer_rate_up` | Current upload rate in bytes per second. |
| `sensor.rsync_transfer_rate_down` | Current download rate in bytes per second. |
| `sensor.rsync_last_exit_code` | Exit code from the most recent run. |
| `sensor.rsync_last_run_duration` | Duration of the most recent run in seconds. |

Transfer metrics update while rsync is running. The add-on manifest grants access to the Home Assistant API; no credentials need to be added to the add-on options.
