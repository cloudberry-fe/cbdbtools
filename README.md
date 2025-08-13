# CBDBTools

CBDBTools is a suite of scripts designed to automate the deployment and initialization of HashData Lightning clusters. It also supports Greenplum and Cloudberry-based MPP databases, with both single-node and multi-node cluster setups.

The tool provides two deployment methods:
1. **Command-line deployment** - Traditional approach using shell scripts
2. **Web UI deployment** - Modern approach using a web-based interface

---

## Table of Contents

- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Deployment Methods](#deployment-methods)
  - [Command-line Deployment](#command-line-deployment)
    - [1. Configure Parameters](#1-configure-parameters)
    - [2. Define Hosts](#2-define-hosts)
    - [3. Start Deployment](#3-start-deployment)
  - [Web UI Deployment](#web-ui-deployment)
    - [Starting the Web UI](#starting-the-web-ui)
    - [Using the Web UI](#using-the-web-ui)
- [Features](#features)
- [Scripts Overview](#scripts-overview)
- [Utility Scripts](#utility-scripts)
- [Examples](#examples)
- [Notes](#notes)
- [Troubleshooting](#troubleshooting)
- [Support](#support)

---

## Repository Structure

```
.
├── deploycluster.sh             # Main script to deploy the cluster
├── deploycluster_parameter.sh   # Main configuration file with environment variables
├── init_cluster.sh              # Script to initialize the database cluster
├── init_env.sh                  # Sets up the environment on the coordinator node
├── init_env_segment.sh          # Sets up the environment on segment nodes
├── multiscp.sh                  # Utility: parallel file copy to multiple hosts
├── multissh.sh                  # Utility: parallel command execution on multiple hosts
├── run.sh                       # Entry point script to start deployment
├── segmenthosts.conf            # Host/IP configuration for coordinator and segments
├── README.md                    # Project documentation
├── cluster_deploy_web.py        # Web UI application for cluster deployment
├── start_web.sh                 # Script to start the Web UI
├── wsgi.py                      # WSGI entry point for the web application
└── templates/
    └── index.html               # Web UI template
```

**Key files:**
- `deploycluster.sh`: Orchestrates the full deployment process.
- `deploycluster_parameter.sh`: Central place for all deployment parameters.
- `init_env.sh` / `init_env_segment.sh`: Prepare OS, users, directories, and dependencies.
- `init_cluster.sh`: Initializes the database cluster after environment setup.
- `multissh.sh` / `multiscp.sh`: Utilities for parallel SSH and SCP operations.
- `segmenthosts.conf`: List of all cluster nodes and their roles.
- `run.sh`: Main entry point for launching the deployment workflow.
- `cluster_deploy_web.py`: Flask web application providing a UI for cluster deployment.
- `start_web.sh`: Script to start the web UI application.
- `templates/index.html`: HTML template for the web UI.

> **Note:** Additional scripts, logs, or temporary files may be created during deployment or troubleshooting.

---

## Prerequisites

1. **Operating System:**  
   - CentOS/RHEL 7, 8, or 9
   - The tool will check and install required packages with `YUM`, will try to update alternative yum repo for Centos7/8 automatically, save your yum repo settings if necessary. For Centos 9, make sure yum/dnf repos are configured correctly. 

2. **Supported Database Versions:**  
   - HashData Lightning  
   - Cloudberry 1.x / 2.x  
   - Greenplum 5.x / 6.x / 7.x

3. **Dependencies:**  
   - `sshpass` (automatically installed via `yum`; if installation fails, the tool will attempt to build from source using `sshpass-1.10.tar.gz`)
   - `gcc` and `make` (required for building `sshpass` from source if needed)
   - `python3` and `pip` (required for Web UI deployment)

4. **Environment:**  
   - The tool must be executed on the **coordinator** server.
   - `root` user access is required for all servers (supports both password and keyfile authentication).
   - Update `segmenthosts.conf` with the correct IP addresses and hostnames.
   - Disks must be formatted with the XFS file system and mounted with sufficient space for database installation and data.
   - Ensure adequate system resources (RAM, CPU) as per HashData requirements.

---

## Deployment Methods

CBDBTools supports two deployment methods: command-line and Web UI. Both methods use the same underlying scripts but provide different user interfaces.

### Command-line Deployment

Traditional deployment method using shell scripts directly.

#### For Single-Node Deployment

Only `deploycluster_parameter.sh` needs to be configured.

#### For Multi-Node Deployment

Both `deploycluster_parameter.sh` and `segmenthosts.conf` must be configured.

#### 1. Configure Parameters

Edit the `deploycluster_parameter.sh` file to set the required environment variables.  
The following parameters are **mandatory** and must be reviewed and set for your installation:

```
## Mandatory options
export ADMIN_USER="gpadmin"
export ADMIN_USER_PASSWORD="Hashdata@123"
export CLOUDBERRY_RPM="/tmp/hashdata-lightning-release.rpm"
export CLOUDBERRY_BINARY_PATH="/usr/local/cloudberry-db"
export COORDINATOR_HOSTNAME="mdw"
export COORDINATOR_IP="192.168.193.21"
export DEPLOY_TYPE="single"
```

- `ADMIN_USER`: OS user for cluster initialization.
- `ADMIN_USER_PASSWORD`: Password for the OS user.
- `CLOUDBERRY_RPM`: Path to the database RPM package.
- `CLOUDBERRY_BINARY_PATH`: Path where the database binary symlink will be created after installation.  
  - Default: `/usr/local/cloudberry-db` (Cloudberry), `/usr/local/hashdata-lightning` (HashData Lightning), `/usr/local/greenplum-db` (Greenplum)
- `COORDINATOR_HOSTNAME`: Hostname for the coordinator server (the tool will set this hostname).
- `COORDINATOR_IP`: IP address for the coordinator server.
- `DEPLOY_TYPE`: Set to `single` for single-node or `multi` for multi-node deployment.

With these settings (and defaults for the rest), you can create a single-node cluster on the coordinator server by simply running:

```bash
sh run.sh
```

##### Additional Parameters for Multi-Node Deployment

When `DEPLOY_TYPE` is set to `multi`, review and configure the following:

```
# Segment host access info ("keyfile" and "password" access are supported)
export SEGMENT_ACCESS_METHOD="keyfile"
export SEGMENT_ACCESS_USER="root"
export SEGMENT_ACCESS_KEYFILE="/tmp/keyfiles"
export SEGMENT_ACCESS_PASSWORD="XXXXXXXX"
```

- `SEGMENT_ACCESS_METHOD`: `keyfile` or `password`
- `SEGMENT_ACCESS_USER`: Must be `root`
- `SEGMENT_ACCESS_KEYFILE`: Path to the SSH keyfile (if using `keyfile`)
- `SEGMENT_ACCESS_PASSWORD`: Root password (if using `password`)

##### Optional Parameters

```
## Set to 'true' to configure OS parameters only
export INIT_ENV_ONLY="false"
export CLOUDBERRY_RPM_URL="http://downloadlink.com/cloudberry.rpm"
export INIT_CONFIGFILE="/tmp/gpinitsystem_config"
export WITH_MIRROR="false"
export WITH_STANDBY="false"
```

- `INIT_ENV_ONLY`: If `true`, only the OS environment is configured (no database installation or cluster initialization).
- `CLOUDBERRY_RPM_URL`: URL to download the RPM if not present locally.
- `INIT_CONFIGFILE`: Path for the generated cluster initialization config.
- `WITH_MIRROR`: Set to `true` to enable mirror segments.
- `WITH_STANDBY`: Set to `true` to enable a standby server.

##### Advanced Cluster Parameters

Adjust these as needed for your environment (see database product manuals for details):

```
# Cluster initialization parameters
export COORDINATOR_PORT="5432"
export COORDINATOR_DIRECTORY="/data0/database/coordinator"
export ARRAY_NAME="CBDB_SANDBOX"
export MACHINE_LIST_FILE="/tmp/hostfile_gpinitsystem"
export SEG_PREFIX="gpseg"
export PORT_BASE="6000"
export DATA_DIRECTORY="/data0/database/primary /data0/database/primary"
export TRUSTED_SHELL="ssh"
export CHECK_POINT_SEGMENTS="8"
export ENCODING="UNICODE"
export DATABASE_NAME="gpadmin"

# Mirror parameters (if WITH_MIRROR is true)
export MIRROR_PORT_BASE="7000"
export MIRROR_DATA_DIRECTORY="/data0/database/mirror /data0/database/mirror"
```

#### 2. Define Hosts

Update the `segmenthosts.conf` file with the IP addresses and hostnames of your coordinator and segment nodes.

- This file **must** be correctly configured for multi-node installations.
- IP addresses must be reachable within the cluster.
- Hostnames will be set automatically by the tool.
- In multi-node setups, this file overrides `COORDINATOR_HOSTNAME` and `COORDINATOR_IP` in `deploycluster_parameter.sh`.

**Example `segmenthosts.conf` for a multi-node cluster:**
```
##Define hosts used for Hashdata

#Hashdata hosts begin
##Coordinator hosts
192.168.193.21 mdw
##Segment hosts
192.168.198.201 sdw1
192.168.198.13 sdw2
#Hashdata hosts end
```

- Replace the IP addresses and hostnames with those appropriate for your environment.
- This format must be followed for the deployment scripts to correctly parse the file.

#### 3. Start Deployment

After configuring the necessary files, start the deployment process:

```bash
sh run.sh
```

**Options:**
- No arguments: Uses `DEPLOY_TYPE` from `deploycluster_parameter.sh`
- `single`: Forces single-node deployment
- `multi`: Forces multi-node deployment
- `--help`: Shows usage information

### Web UI Deployment

Modern deployment method using a web-based interface that simplifies the configuration and deployment process.

#### Starting the Web UI

To start the Web UI, run the `start_web.sh` script:

```bash
sh start_web.sh
```

This script will:
1. Turn off firewalls
2. Install required packages (python3, pip)
3. Create and activate a Python virtual environment
4. Install Flask and other required Python packages
5. Start the web application using Gunicorn on port 5000

After starting, you can access the Web UI by opening a browser and navigating to `http://<server-ip>:5000`.

#### Using the Web UI

The Web UI provides a user-friendly interface for configuring and deploying your CBDB cluster:

1. **Configuration Tab**
   - Select deployment mode (Single Node or Multi Node)
   - Configure mandatory options (Admin User, Password, RPM path, etc.)
   - Set cluster initialization parameters (Coordinator port, directories, etc.)
   - Configure mirror settings if needed
   - Set multi-node specific parameters (Segment access method, key files, etc.)
   - Upload RPM and key files directly through the UI
   - Save configuration with the "Save Configuration" button

2. **Hosts Tab** (Multi Node mode only)
   - Configure coordinator host IP and hostname
   - Add/remove segment hosts with their IPs and hostnames
   - Save host configuration with the "Save Hosts" button

3. **Deploy Tab**
   - Review all deployment configuration details
   - See warnings about data directories being deleted and recreated
   - Check configuration consistency between tabs
   - Start deployment with the "Deploy Cluster" button

The Web UI provides several advantages over command-line deployment:
- Visual configuration interface reduces the chance of configuration errors
- File upload functionality for RPM and key files
- Configuration validation and consistency checks
- Clear warnings about destructive operations (like data directory recreation)

---

## Features

- Automated environment setup across coordinator and segment nodes
- Support for CentOS/RHEL 7, 8, and 9
- Comprehensive error handling and logging
- Automatic system parameter optimization
- Support for both password and keyfile-based SSH authentication
- Flexible deployment options (single/multi-node, with/without mirrors)
- Robust SSH key management for passwordless access
- Auto-detection and configuration of OS-specific parameters
- Web-based user interface for simplified deployment
- Real-time deployment monitoring and logging
- Configuration validation and consistency checks

---

## Scripts Overview

- **deploycluster.sh**  
  Main deployment script that orchestrates the deployment process.

- **deploycluster_parameter.sh**  
  Contains environment variables and configuration parameters used across all scripts.

- **init_env.sh**  
  Sets up the environment on the coordinator node:
  - Configures system parameters and SSH settings
  - Installs required dependencies
  - Sets up authentication between nodes
  - Handles OS-specific configurations
  - Creates required directories and users

- **init_env_segment.sh**  
  Configures segment nodes with:
  - Optimized system parameters
  - User and permission setup
  - Directory structure creation
  - Database software installation
  - SSH key distribution

- **init_cluster.sh**  
  Initializes the database cluster.

- **run.sh**  
  Entry point script to start the deployment process.

- **segmenthosts.conf**  
  Defines the coordinator and segment hosts for the cluster.

- **cluster_deploy_web.py**  
  Flask web application providing a UI for cluster deployment.

- **start_web.sh**  
  Script to start the web UI application.

- **wsgi.py**  
  WSGI entry point for the web application.

---

## Utility Scripts

### multissh.sh

A powerful utility for executing commands across multiple hosts in parallel, with advanced features:

- Flexible authentication using SSH keys or passwords
- Configurable concurrency control
- Detailed execution tracking and error reporting
- Output collection and logging
- Progress monitoring and execution summary
- Support for connection timeouts and custom SSH ports
- Color-coded output for better readability

**Usage:**
```bash
sh multissh.sh [options] <command>
```
**Options:**
```
  -h, --help            Show help message
  -f, --hosts-file      Hosts file (default: segment_hosts.txt)
  -u, --user            SSH username (default: current user)
  -p, --password        SSH password
  -k, --key-file        SSH private key file
  -P, --port            SSH port (default: 22)
  -t, --timeout         Connection timeout (default: 30s)
  -v, --verbose         Enable verbose output
  -o, --output          Save output to file
  -c, --concurrency     Max parallel connections (default: 5)
```

---

### multiscp.sh

File distribution utility for copying files to multiple remote hosts simultaneously:

- Parallel file transfer capabilities
- Progress tracking for each transfer
- Support for both key and password authentication
- Configurable error handling and retry logic
- Detailed transfer logs and status reporting

**Usage:**
```bash
sh multiscp.sh [options] source_file destination_path
```
**Options:**
```
  -h, --help            Show help message
  -f, --hosts-file      Hosts file (default: segment_hosts.txt)
  -u, --user            SSH username (default: current user)
  -p, --password        SSH password
  -k, --key-file        SSH private key file
  -v, --verbose         Enable verbose output
```

---

## Examples

### multissh.sh Examples

1. Execute a command using password authentication:
    ```bash
    sh multissh.sh -v -p 'your_password' -f hosts.txt -u gpadmin "date"
    ```

2. Check disk space on all hosts using an SSH key:
    ```bash
    sh multissh.sh -v -k ~/.ssh/id_rsa -f hosts.txt -u gpadmin "df -h"
    ```

### multiscp.sh Examples

1. Copy a configuration file using password authentication:
    ```bash
    sh multiscp.sh -v -p 'your_password' -f hosts.txt -u gpadmin ./config.ini /home/gpadmin/
    ```

2. Copy and extract an archive using an SSH key:
    ```bash
    tar czf scripts.tar.gz *.sh
    sh multiscp.sh -v -k ~/.ssh/id_rsa -f hosts.txt -u gpadmin ./scripts.tar.gz /home/gpadmin/
    sh multissh.sh -v -k ~/.ssh/id_rsa -f hosts.txt -u gpadmin "cd /home/gpadmin && tar xzf scripts.tar.gz"
    ```

**Example `hosts.txt` format:**
```
192.168.1.101
192.168.1.102
192.168.1.103
```

---

## Notes

- Scripts include comprehensive error handling and logging.
- System parameters are automatically optimized based on available resources.
- All operations are logged with timestamps for troubleshooting.
- Supports automatic failover to source compilation for `sshpass` if package installation fails.
- Implements safeguards against common deployment issues.
- Web UI provides visual feedback and real-time deployment monitoring.
- Data directories will be deleted and recreated during deployment, with clear warnings in the UI.

---

## Troubleshooting

**Common issues and solutions:**

1. **SSH Connection Issues:**
   - Check network connectivity.
   - Verify SSH key permissions.
   - Ensure correct username/password or key file.

2. **Installation Failures:**
   - Check system requirements.
   - Verify RPM package integrity.
   - Review logs in `/tmp/<username>/`.

3. **Performance Issues:**
   - Verify system parameters in `sysctl.conf`.
   - Check resource allocation.
   - Review segment configuration.

4. **Web UI Issues:**
   - Ensure port 5000 is accessible through any firewalls.
   - Check that the web application is running (`ps aux | grep gunicorn`).
   - Review web application logs for errors.

---

## Support

For issues or questions:

1. File an issue in this repository.
2. Contact the repository maintainer.

---
        