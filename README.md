# Instructions

## Install

### Linux
1. Clone this repo
2. Create a new conf file under /conf from one of the files already in there
3. Edit the borg-backup.service and change the After and Requires values to your .mount file of choosing. Run `systemctl list-unit-files --type=mount` to see the mount files on your machine. Setting up custom mounts for your use case is not covered in this repo.
4. Run the install-borg.sh script
```
# Usage; ./install-borg.sh <path to conf>, e.g.
./install-borg.sh conf/test-borg-backup.conf
```
  * Copies your specificed *-borg-backup.conf* file to /etc/ directory
  * Copies borg-backup.sh to /usr/local/bin and chmod it
  * Move '.service' and '.timer' files to '/etc/systemd/system/' directory and runs systemctl commands
  * Prompts you to enter an encryption password for your borg archive and creates a file at /etc/secrets/borg-passphrase to be used by borg-backup.sh

## Restore 
This command restores to the current directory so make sure you are in an empty directory or expect files to get overwritten
```
mkdir /tmp/borg_extract
cd /tmp/borg_extract

borg list /path/to/backup  # Enter password here and get <archive name>
borg extract /path/to/backup::<archive name>  # replace <archive name>, looks like hostname-timestamp retrieved first from borg list
```

