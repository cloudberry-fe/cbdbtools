# CBDBTools

CBDB Tools is a set of scripts designed to automate the deployment and initialization of a HashData Lightning cluster. It also works for Greenplum / Cloudberry based MPP databases. 
The tool supports both single-node and multi-node cluster setups.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Repository Structure](#repository-structure)
- [Usage](#usage)
- [Features](#features)
- [Scripts Overview](#scripts-overview)
- [Utility Scripts](#utility-scripts)
- [Examples](#examples)
- [Notes](#notes)
- [Troubleshooting](#troubleshooting)
- [Support](#support)

## Repository Structure

```
.
├── deploycluster.sh            # Main script to deploy the cluster
├── deploycluster_parameter.sh  # Configuration file with environment variables
├── init_cluster.sh            # Script to initialize the cluster
├── init_env.sh               # Script to set up the environment on the coordinator
├── init_env_segment.sh       # Script to set up the environment on segment nodes
├── run.sh                   # Entry point script to start the deployment
├── segmenthosts.conf        # Configuration file defining coordinator and segment hosts
```

## Prerequisites

1. **Operating System**: This tool supports CentOS/RHEL 7, 8, or 9

2. **Supported Database Versions**: HashData Lightning / Cloudberry 1.x /2.x / Greenplum 5.x / 6.x/ 7.x

3. **Dependencies**:
   - `sshpass` (will be automatically installed via yum, if fails, the tool will attempt to build from source using sshpass-1.10.tar.gz)
   - `gcc` and `make` (for building sshpass from source if needed)
  

4. **Environment**:
   - The tool must be executed on the `COORDINATOR` server.
   - Ensure `root` user access are available for all servers. It support both password access and keyfile access.
   - Update the `segmenthosts.conf` file with the correct IP addresses and hostnames in the format of the configuration file.
   - Disks are properly formated with xfs file system and mounted with sufficient disk space for database installation and data
   - Proper system resources (RAM, CPU) as per HashData requirements

## Usage

For single node deployment, only `deploycluster_parameter.sh` needed to configure

For multi node deployment, both `deploycluster_parameter.sh` and `segmenthosts.conf` needed to be configured.

### 1. Configure Parameters
Edit the `deploycluster_parameter.sh` file to set the appropriate environment variables:

The following parameter are mandatory to be reviewed and configured to your own installation:

```
## mandatory options
export ADMIN_USER="gpadmin"  
export ADMIN_USER_PASSWORD="Hashdata@123"
export CLOUDBERRY_RPM="/tmp/hashdata-lightning-release.rpm"
export CLOUDBERRY_BINARY_PATH="/usr/local/cloudberry-db"
export COORDINATOR_HOSTNAME="mdw"
export COORDINATOR_IP="192.168.193.21"
export DEPLOY_TYPE="single"
```
- `ADMIN_USER`: OS user will be used for initialize the cluster.
- `ADMIN_USER_PASSWORDq: Password need to setup when create the OS user.
- `CLOUDBERRY_RPM`: Path to the database RPM package.
- `CLOUDBERRY_BINARY_PATH` : Where database binary softlink will be created after installation. By default for Cloudberry is /usr/local/cloudberry-db, for HashData Lightninig is /usr/local/hashdata-lightning, for Greenplum is /usr/local/greenplum-db.
- `COORDINATOR_HOSTNAME`: Hostname for the coordinator server you want to configured, the tool will change the hostname to this configuration.
- `COORDINATOR_IP`: IP for coordinator server to connected with other servers.
- `DEPLOY_TYPE`: Set to `single` for single-node or `multi` for multi-node deployment. 

With above setting and leave rest of parameters by default value, the tool can create a single node cluster on the coordinator server by simple execute: `sh run.sh`

To deploy a multi server cluster, more parameters need to be reviewed and configured. When `DEPLOY_TYPE` Set to `multi` for a multi server cluster initialization, follow parameter MUST be reviewed and configured.
```
# define segment host access info, "keyfile" and "password" accees are supported to setup remote servers
export SEGMENT_ACCESS_METHOD="keyfile"
export SEGMENT_ACCESS_USER="root"
export SEGMENT_ACCESS_KEYFILE="/tmp/keyfiles"
export SEGMENT_ACCESS_PASSWORD="XXXXXXXX"
```

- `SEGMENT_ACCESS_METHOD`: Choose between `keyfile` or `password` for segment host access.
- `SEGMENT_ACCESS_USER`: Currently have to be `root` user.
- `SEGMENT_ACCESS_KEYFILE`: Path to the Keyfiles to be used when access method is `keyfile`.
- `SEGMENT_ACCESS_PASSWORD`: root user password when access method is `password`.

Follwoing parameters are most optional for different cluster configurations

```
## set to 'true' if you want to setup OS parameters only
export INIT_ENV_ONLY="false"
export CLOUDBERRY_RPM_URL="http://downloadlink.com/cloudberry.rpm"
export INIT_CONFIGFILE="/tmp/gpinitsystem_config"
export WITH_MIRROR="false"
export DEPLOY_TYPE="single"
## set to 'multi' for multiple nodes deployment
export WITH_STANDBY="false"

```

- `INIT_ENV_ONLY`: When set to `true`, the tool will only configure the operating system environment (including system parameters, user creation, and directory setup) without installing the database software or initializing the cluster. This is useful when you want to:
  - Prepare multiple hosts for future database installation
  - Verify system configurations before database installation
  - Update system settings on existing hosts
  - Troubleshoot environment issues independently of database setup
- `CLOUDBERRY_RPM_URL`: URL to download the RPM if not present locally
- `INIT_CONFIGFILE`: The file generated for init the cluster based on the configuration.
- `WITH_MIRROR`: Set to `true` to enable mirror segments
- `WITH_STANDBY`: Set to `true` to enable standby server

Following are more parameters to customize the cluster setting with similiar configurations with Cloudbery / Greenplum gpinitsystem instructions. Please review and change according to your need and refer to the database product manuals.

```
# define parameters used for init cluster
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

# define parameters used for mirror if WITH_MIRROR set to true
export MIRROR_PORT_BASE="7000"
export MIRROR_DATA_DIRECTORY="/data0/database/mirror /data0/database/mirror"
```


### 2. Define Hosts
Update the `segmenthosts.conf` file with the IP addresses and hostnames of your coordinator and segment nodes. This file MUST be correctly configued for a multi node installation. IP MUST be correctly configured to connected within the cluster and hostnames will be configured by the tool automatically. Also in a multi node installation, this configuration file will over write the setting for `COORDINATOR_HOSTNAME` and `COORDINATOR_IP` in `deploycluster_parameter.sh`.


### 3. Start Deployment
After above configuration file are properly configured:

Run the `run.sh` script to start the deployment process:
```bash
sh run.sh
```

Options:
- No arguments: Uses `DEPLOY_TYPE` from `deploycluster_parameter.sh`
- `single`: Forces single-node deployment
- `multi`: Forces multi-node deployment
- `--help`: Shows usage information

## Features

- Automated environment setup across coordinator and segment nodes
- Support for CentOS/RHEL 7, 8, and 9
- Comprehensive error handling and logging
- Automatic system parameter optimization
- Support for both password and keyfile-based SSH authentication
- Flexible deployment options (single/multi-node, with/without mirrors)
- Robust SSH key management for passwordless access
- Auto-detection and configuration of OS-specific parameters

## Scripts Overview

### `deploycluster.sh`
The main deployment script that orchestrates the deployment process.

### `deploycluster_parameter.sh`
Contains environment variables and configuration parameters used across all scripts.

### `init_env.sh`
Sets up the environment on the coordinator node:
- Configures system parameters and SSH settings
- Installs required dependencies
- Sets up authentication between nodes
- Handles OS-specific configurations
- Creates required directories and users

### `init_env_segment.sh`
Configures segment nodes with:
- Optimized system parameters
- User and permission setup
- Directory structure creation
- Database software installation
- SSH key distribution

### `init_cluster.sh`
Initializes the database cluster.

### `mirrorlessfailover.sh`
Handles failover scenarios in a mirrorless setup.

### `run.sh`
Entry point script to start the deployment process.

### `segmenthosts.conf`
Defines the coordinator and segment hosts for the cluster.

## Utility Scripts

### multissh.sh
A powerful utility for executing commands across multiple hosts in parallel with advanced features:

- Flexible authentication using SSH keys or passwords
- Configurable concurrency control
- Detailed execution tracking and error reporting
- Output collection and logging
- Progress monitoring and execution summary
- Support for connection timeouts and custom SSH ports
- Color-coded output for better readability

```bash
Usage: multissh.sh [options] <command>

Options:
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

### multiscp.sh
File distribution utility for copying files to multiple remote hosts simultaneously:

- Parallel file transfer capabilities
- Progress tracking for each transfer
- Support for both key and password authentication
- Configurable error handling and retry logic
- Detailed transfer logs and status reporting

```bash
Usage: multiscp.sh [options] source_file destination_path

Options:
  -h, --help            Show help message
  -f, --hosts-file      Hosts file (default: segment_hosts.txt)
  -u, --user            SSH username (default: current user)
  -p, --password        SSH password
  -k, --key-file        SSH private key file
  -v, --verbose         Enable verbose output
```

## Examples

### multissh.sh Examples

1. Execute command using password authentication:
```bash
sh multissh.sh -v -p 'your_password' -f hosts.txt -u gpadmin "date"
```

2. Check disk space on all hosts using SSH key:
```bash
sh multissh.sh -v -k ~/.ssh/id_rsa -f hosts.txt -u gpadmin "df -h"
```

### multiscp.sh Examples

1. Copy configuration file using password:
```bash
sh multiscp.sh -v -p 'your_password' -f hosts.txt -u gpadmin ./config.ini /home/gpadmin/
```

2. Copy and extract archive using SSH key:
```bash
tar czf scripts.tar.gz *.sh
sh multiscp.sh -v -k ~/.ssh/id_rsa -f hosts.txt -u gpadmin ./scripts.tar.gz /home/gpadmin/
sh multissh.sh -v -k ~/.ssh/id_rsa -f hosts.txt -u gpadmin "cd /home/gpadmin && tar xzf scripts.tar.gz"
```

Example hosts.txt format:
```
192.168.1.101
192.168.1.102
192.168.1.103
```

## Notes

- Scripts include comprehensive error handling and logging
- System parameters are automatically optimized based on available resources
- All operations are logged with timestamps for troubleshooting
- Supports automatic failover to source compilation for sshpass if package installation fails
- Implements safeguards against common deployment issues

## Troubleshooting

Common issues and solutions:
1. SSH Connection Issues:
   - Check network connectivity
   - Verify SSH key permissions
   - Ensure correct username/password or key file
2. Installation Failures:
   - Check system requirements
   - Verify RPM package integrity
   - Review logs in /tmp/<username>/
3. Performance Issues:
   - Verify system parameters in sysctl.conf
   - Check resource allocation
   - Review segment configuration

## Support

For issues or questions:
1. File an issue in this repository
2. Contact the repository maintainer
