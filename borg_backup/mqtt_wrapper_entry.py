#!/usr/bin/env python3
"""
MQTT Wrapper for Borg Backup Script

This wrapper executes the borg-backup.sh script and publishes
status updates to MQTT for Home Assistant integration.

"""

import os
import sys
import socket
from pathlib import Path
import logging
from logging.handlers import RotatingFileHandler

from mqtt_script_wrapper.wrapper import MQTTScriptWrapper

HOSTNAME = socket.gethostname()
SCRIPT_ID = f"borg_backup_{HOSTNAME}"

LOG_FILE = Path.home() / f".local/state/{SCRIPT_ID}/wrapper.log"
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

handler = RotatingFileHandler(
    LOG_FILE,
    maxBytes=10*1024*1024,  # 10MB
    backupCount=10
)

# Initialize logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    handlers=[
        logging.StreamHandler(sys.stdout),
        handler,
    ]
)

# ============================================================================
# CONFIGURATION
# ============================================================================

# Get package directory
WRAPPER_DIR = Path(__file__).parent.resolve()
REPO_ROOT = WRAPPER_DIR

# MQTT Topics
MQTT_TOPIC_PREFIX = f"homeassistant/sensor/{SCRIPT_ID}"

# Backup Script Alias and Path
BACKUP_SCRIPT_ALIAS = f"Borg Backup - {HOSTNAME}"
BACKUP_SCRIPT = REPO_ROOT / "borg_backup.sh"

# YAML config for MQTT connection
MQTT_CONFIG = Path(os.getenv('BORG_BACKUP_CONFIG',
                                Path('/etc/mqtt.yaml')))
if not MQTT_CONFIG.exists():
    logging.error(f"Config file not found: {MQTT_CONFIG}")
    sys.exit(1)

# ============================================================================
# Main Execution
# ============================================================================

def main():
    """Main execution function."""

    wrapper = MQTTScriptWrapper(
        BACKUP_SCRIPT_ALIAS,
        BACKUP_SCRIPT,
        MQTT_CONFIG,
        MQTT_TOPIC_PREFIX,
    )

    wrapper.wrap_script()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nBackup interrupted by user")
        sys.exit(1)
