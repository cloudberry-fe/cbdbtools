#!/bin/bash

VARS_FILE="deploycluster_parameter.sh"

source ./${VARS_FILE}

# New: Check for existing deployment processes
log_time "Checking for existing deployment processes..."

# Find all running deploycluster.sh processes (excluding current process)
EXISTING_PROCESSES=$(ps aux | grep -v grep | grep -v $$ | grep deploycluster.sh)

if [ -n "${EXISTING_PROCESSES}" ]; then
  log_time "Found existing deployment processes:";
  echo "${EXISTING_PROCESSES}";
  
  # Find related log files
  log_time "Associated log files:";
  ls -la deploy_cluster_*.log 2>/dev/null || echo "No log files found";
  
  log_time "Exiting to avoid multiple deployments.";
  exit 1;
fi

log_time "No existing deployment processes found. Proceeding with deployment."

if [ "${1}" == "single" ] || [ "${1}" == "multi" ]; then  
  cluster_type="${1}"  
else  
  cluster_type="${DEPLOY_TYPE}"
fi  

log_time "Started deploy the cluster in backgroud with mode ${DEPLOY_TYPE}."

logfilename=$(date +%Y%m%d)_$(date +%H%M%S)

log_time "Check deploy_cluster_$logfilename.log for more detail."

nohup sh deploycluster.sh $cluster_type > deploy_cluster_$logfilename.log 2>&1 &