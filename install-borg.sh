#!/usr/bin/env bash

set -xve

pacman -S --needed borg

if [[ -z $1 ]]; then
    echo "Need to pass an argument for to specify the config file. Usage: ./$0 <path/to/my.conf>"
    exit 1
fi

# pick one from the conf directory or use as a template
CONFIG_FILE=$1

if [[ ! -f $CONFIG_FILE ]]; then
    echo "($CONFIG_FILE) is not a valid file path"
    exit 2
fi

cp $CONFIG_FILE /etc/borg-backup.conf
cp borg-backup.{service,timer} /etc/systemd/system/

chmod +x borg-backup.sh
cp borg-backup.sh /usr/local/bin

# Enable systemd
systemctl daemon-reload
systemctl enable borg-backup.timer
systemctl start borg-backup.timer


save_borg_passphrase() {
    local passphrase_file="/etc/secrets/borg-passphrase"
    
    echo "Enter Borg repository passphrase:"
    read -s passphrase
    echo
    
    echo "Confirm passphrase:"
    read -s passphrase_confirm
    echo
    
    if [ "$passphrase" != "$passphrase_confirm" ]; then
        echo "Error: Passphrases don't match!"
        return 1
    fi
    
    sudo mkdir -p /etc/secrets/
    echo "$passphrase" | sudo tee "$passphrase_file" > /dev/null
    sudo chmod 600 "$passphrase_file"
    
    unset passphrase passphrase_confirm
    
    echo "Passphrase saved to $passphrase_file"
    echo "CRITICAL: Back this passphrase up to a safe location!"
    echo "Without it, your encrypted backups are unrecoverable."
}

# Run it
save_borg_passphrase

