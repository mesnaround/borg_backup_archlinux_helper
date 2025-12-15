# Borg Backup with MQTT Monitoring

Automated Borg backup system with MQTT status publishing for Home Assistant integration.

## Features

- Automated backups via systemd timer
- MQTT status monitoring (state, duration, exit codes)
- Systemd mount/automount support for network shares
- Python wrapper for execution monitoring
- Per-host configuration

## Install

### Prerequisites
- Arch Linux (or adjust package manager in install script)
- Root access
- MQTT broker (for monitoring)

### Installation Steps

1. Clone this repo
2. Create config files from templates:
   ```bash
   # Borg backup config
   cp conf/test-borg-backup.conf conf/my-machine.conf
   vim conf/my-machine.conf

   # MQTT config
   cp mqtt.yaml.template mqtt.yaml
   vim mqtt.yaml

   # Mount units (if using network share)
   cp systemd/mnt-bpshare-bpshare0-backup.mount.template systemd/my-mount.mount
   cp systemd/mnt-bpshare-bpshare0-backup.automount.template systemd/my-mount.automount
   vim systemd/my-mount.{mount,automount}
   ```

3. (Optional) Set up systemd mount if using network storage:
   ```bash
   cd systemd
   sudo ./setup_mount.sh
   ```

4. Update `systemd/borg-backup.service` to reference your mount unit if needed

5. Run the install script:
   ```bash
   sudo ./install-borg.sh conf/my-machine.conf mqtt.yaml
   ```

### What the installer does:
- Installs system dependencies (borg, python, uv)
- Creates Python virtual environment at `/opt/borg_backup`
- Installs MQTT wrapper and dependencies
- Copies configs to `/etc/`
- Installs systemd units to `/etc/systemd/system/`
- Enables and starts the backup timer
- Prompts for borg repository passphrase (saved to `/etc/secrets/borg-passphrase`)

## Restore 
This command restores to the current directory so make sure you are in an empty directory or expect files to get overwritten
```
mkdir /tmp/borg_extract
cd /tmp/borg_extract

borg list /path/to/backup  # Enter password here and get <archive name>
borg extract /path/to/backup::<archive name>  # replace <archive name>, looks like hostname-timestamp retrieved first from borg list
```

