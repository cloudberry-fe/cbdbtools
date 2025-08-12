#!/bin/bash

function log_time() {
  printf "[%s] %b\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Turn off firewalls
log_time "Step 1: Turn off firewalls..."

systemctl stop firewalld.service
systemctl disable firewalld.service

sed s/^SELINUX=.*$/SELINUX=disabled/ -i /etc/selinux/config
setenforce 0

# Kill any existing gunicorn processes
echo "Killing any existing gunicorn processes..."
pkill -f gunicorn || true

# Install required packages
log_time "Step 2: Install required packages..."
yum install -y python3 python3-pip

# Check if virtual environment exists, if not create it
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Upgrade pip to latest version
pip install -i https://mirrors.aliyun.com/pypi/simple  --upgrade pip

# Install required packages in the virtual environment
echo "Installing required packages..."
pip install -i https://mirrors.aliyun.com/pypi/simple flask gunicorn psutil

# Verify Flask installation
if ! python -c "import flask" &> /dev/null; then
    echo "Error: Flask installation failed"
    exit 1
fi

# Start the web application using Gunicorn
echo "Starting web application with Gunicorn..."
exec gunicorn --bind 0.0.0.0:5000 --workers 4 --timeout 600 wsgi:app