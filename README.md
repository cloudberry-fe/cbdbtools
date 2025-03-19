# CBDBTools

CBDBTools is a set of scripts designed to automate the deployment and initialization of a HashData database cluster. It supports both single-node and multi-node cluster setups.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Repository Structure](#repository-structure)
- [Usage](#usage)
- [Scripts Overview](#scripts-overview)
- [Notes](#notes)
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

1. **Operating System**: CentOS 7 or compatible Linux distribution.
2. **Dependencies**:
   - `wget`
   - `sshpass`
   - `epel-release`

3. **Environment**:
   - Ensure passwordless SSH access is configured between the coordinator and segment nodes.
   - Update the `segmenthosts.conf` file with the correct IP addresses and hostnames for your cluster.

## Usage

### 1. Configure Parameters
Edit the `deploycluster_parameter.sh` file to set the appropriate environment variables for your deployment. Key parameters include:
- `DEPLOY_TYPE`: Set to `single` for single-node deployment or `multi` for multi-node deployment.
- `WITH_MIRROR`: Set to `true` to enable mirror segments.
- `SEGMENT_ACCESS_METHOD`: Choose between `keyfile` or `password` for segment host access.

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

## Scripts Overview

### `deploycluster.sh`
The main deployment script that orchestrates the deployment process.

### `deploycluster_parameter.sh`
Contains environment variables and configuration parameters used across all scripts.

### `init_env.sh`
Sets up the environment on the coordinator node.

### `init_env_segment.sh`
Sets up the environment on segment nodes.

### `init_cluster.sh`
Initializes the database cluster.

### `mirrorlessfailover.sh`
Handles failover scenarios in a mirrorless setup.

### `run.sh`
Entry point script to start the deployment process.

### `segmenthosts.conf`
Defines the coordinator and segment hosts for the cluster.

## Notes

- The scripts modify system files such as `/etc/hosts` and `/etc/sysctl.conf`. Use with caution on production systems.
- For multi-node deployments, ensure all segment nodes are reachable via SSH from the coordinator.

## Support

For issues or questions:
1. File an issue in this repository
2. Contact the repository maintainer
