# CBDBTools

CBDBTools is a set of scripts designed to automate the deployment and initialization of a HashData database cluster. It supports both single-node and multi-node cluster setups.

## Repository Structure

```
.
├── delopycluster.sh             # Main script to deploy the cluster
├── deploycluster_parameter.sh   # Configuration file with environment variables
├── init_cluster.sh              # Script to initialize the cluster
├── init_env.sh                  # Script to set up the environment on the coordinator
├── init_env_segment.sh          # Script to set up the environment on segment nodes
├── mirrorlessfailover.sh        # Script for failover handling in a mirrorless setup
├── run.sh                       # Entry point script to start the deployment
├── segmenthosts.conf            # Configuration file defining coordinator and segment hosts
```

## Prerequisites

1. **Operating System**: CentOS 7 or compatible Linux distribution.
2. **Dependencies**:
   - `wget`
   - `sshpass`
   - `epel-release`
   - Various system utilities (installed automatically by the scripts).

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
bash run.sh [single|multi]
```
- If no argument is provided, the `DEPLOY_TYPE` from `deploycluster_parameter.sh` will be used.

### 4. Monitor Logs
Deployment logs are saved in a file named `delopy_cluster_<timestamp>.log`. Check this file for detailed output:
```bash
tail -f delopy_cluster_<timestamp>.log
```

## Scripts Overview

### `delopycluster.sh`
The main script that orchestrates the deployment process by calling `init_env.sh` and `init_cluster.sh`.

### `deploycluster_parameter.sh`
Contains environment variables and configuration parameters used across all scripts.

### `init_env.sh`
Sets up the environment on the coordinator node, including installing dependencies, configuring system parameters, and preparing the database user.

### `init_env_segment.sh`
Sets up the environment on segment nodes, including installing dependencies and configuring system parameters.

### `init_cluster.sh`
Initializes the database cluster using the `gpinitsystem` tool.

### `mirrorlessfailover.sh`
Handles failover scenarios in a mirrorless cluster setup.

### `run.sh`
Entry point script to start the deployment process in the background.

### `segmenthosts.conf`
Defines the coordinator and segment hosts for the cluster.

## Notes

- Ensure that the `CLOUDBERRY_RPM` file or URL in `deploycluster_parameter.sh` is valid and accessible.
- The scripts modify system files such as `/etc/hosts` and `/etc/sysctl.conf`. Use with caution on production systems.
- For multi-node deployments, ensure all segment nodes are reachable via SSH from the coordinator.

## License

This repository does not currently specify a license. Please add a license file if required.

## Support

For issues or questions, please contact the repository maintainer.
