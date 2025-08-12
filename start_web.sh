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


#Step 1: Installing Software Dependencies
log_time "Step 1: Installing Software Dependencies..."

# Check if the /etc/os-release file exists
echo "Check os-release version and make proper settings for YUM sources"

if [ -f /etc/os-release ]; then
    # Source the /etc/os-release file to get the system information
    source /etc/os-release

    # Extract the first digit of the VERSION_ID
    first_digit=$(echo "$VERSION_ID" | cut -c1)

    # Execute different operations based on the first digit of the VERSION_ID
    case "$first_digit" in
        7)
            # Operation in 7
            echo "This is a operating system with version ID starting with 7."
            rm -rf /etc/yum.repos.d/*
            curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.huaweicloud.com/repository/conf/CentOS-7-anon.repo
            yum clean all
            yum makecache
            
            # You can add specific commands for Operation A here, for example, setting up the environment on the coordinator node
            # sh init_env.sh single
            ;;
        8)
            # Operation B
            echo "This is a operating system with version ID starting with 8."
            rm -rf /etc/yum.repos.d/*
            curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.huaweicloud.com/repository/conf/CentOS-8-anon.repo
            yum clean all
            yum makecache
            # You can add specific commands for Operation B here
            ;;
        9)
            # Operation C
            echo "This is a operating system with version ID starting with 9. Executing Operation C."
            # You can add specific commands for Operation C here, such as starting the database cluster deployment
            # bash run.sh multi
            ;;
        *)
            echo "Unsupported OS version ID starting with: $first_digit"
            ;;
    esac
else
    echo "/etc/os-release file not found. Unable to determine the operating system version."
fi

# Install required packages
log_time "Step 3: Install required packages..."
yum install -y python3 python3-pip

# Check if virtual environment exists, if not create it
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Upgrade pip to latest version
pip3 install -i https://mirrors.aliyun.com/pypi/simple  --upgrade pip

# Install required packages in the virtual environment
echo "Installing required packages..."
pip3 install -i https://mirrors.aliyun.com/pypi/simple flask gunicorn psutil

# Verify Flask installation
if ! python3 -c "import flask" &> /dev/null; then
    echo "Error: Flask installation failed"
    exit 1
fi

# Start the web application using Gunicorn
echo "Starting web application with Gunicorn..."
exec gunicorn --bind 0.0.0.0:5000 --workers 4 --timeout 600 wsgi:app