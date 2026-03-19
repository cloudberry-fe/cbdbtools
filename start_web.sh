#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VARS_FILE="deploycluster_parameter.sh"

source "${SCRIPT_DIR}/${VARS_FILE}"
source "${SCRIPT_DIR}/common.sh"

# Detect OS
detect_os

# Turn off firewalls
log_time "Step 1: Turn off firewalls..."
disable_firewall

# Kill any existing gunicorn processes
log_time "Killing any existing gunicorn processes..."
pkill -f gunicorn || true

# Step 2: Installing Software Dependencies
log_time "Step 2: Installing Software Dependencies..."
configure_repo

# Install required packages based on OS
log_time "Step 3: Install required packages..."
if [ "$OS_FAMILY" = "debian" ]; then
    apt-get update
    apt-get install -y python3 python3-pip python3-venv openssl
else
    yum install -y epel-release
    yum install -y python3 python3-pip openssl-devel openssl
fi

# Configure SSHD
configure_sshd

# Create virtual environment
log_time "Creating virtual environment..."
cd "${SCRIPT_DIR}"
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install required packages
log_time "Installing required packages..."
pip install flask gunicorn

# Verify Flask installation
if ! python3 -c "import flask" &>/dev/null; then
    log_time "Error: Flask installation failed"
    exit 1
fi

# Start the web application using Gunicorn
log_time "Starting web application with Gunicorn..."
exec gunicorn --bind 0.0.0.0:5000 --workers 4 --timeout 600 wsgi:app
