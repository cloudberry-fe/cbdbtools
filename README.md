# CBDBTools

CBDBTools is a set of scripts designed to automate the deployment and initialization of a HashData database cluster. It supports both single-node and multi-node cluster setups.

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
├── mirrorlessfailover.sh    # Script for failover handling in a mirrorless setup
├── run.sh                   # Entry point script to start the deployment
├── segmenthosts.conf        # Configuration file defining coordinator and segment hosts
```

## Prerequisites

1. **Operating System**: CentOS/RHEL 7, 8, or 9
2. **Dependencies**:
   - `sshpass` (will be automatically installed via yum, if fails, the tool will attempt to build from source using sshpass-1.10.tar.gz)
   - `gcc` and `make` (for building sshpass from source if needed)
  

3. **Environment**:
   - Ensure passwordless SSH access is configured between the coordinator and segment nodes
   - Update the `segmenthosts.conf` file with the correct IP addresses and hostnames
   - Sufficient disk space for database installation and data
   - Proper system resources (RAM, CPU) as per HashData requirements

## Usage

### 1. Configure Parameters
Edit the `deploycluster_parameter.sh` file to set the appropriate environment variables:
- `DEPLOY_TYPE`: Set to `single` for single-node or `multi` for multi-node deployment
- `WITH_MIRROR`: Set to `true` to enable mirror segments
- `SEGMENT_ACCESS_METHOD`: Choose between `keyfile` or `password` for segment host access
- `INIT_ENV_ONLY`: When set to `true`, the tool will only configure the operating system environment (including system parameters, user creation, and directory setup) without installing the database software or initializing the cluster. This is useful when you want to:
  - Prepare multiple hosts for future database installation
  - Verify system configurations before database installation
  - Update system settings on existing hosts
  - Troubleshoot environment issues independently of database setup
- `CLOUDBERRY_RPM`: Path to the database RPM package
- `CLOUDBERRY_RPM_URL`: URL to download the RPM if not present locally

### 2. Define Hosts
Update the `segmenthosts.conf` file with the IP addresses and hostnames of your coordinator and segment nodes.

### 3. Start Deployment
Run the `run.sh` script to start the deployment process:
```bash
bash run.sh [single|multi] [--help]
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
