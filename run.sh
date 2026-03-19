#!/bin/bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VARS_FILE="deploycluster_parameter.sh"

source "${SCRIPT_DIR}/${VARS_FILE}"

log_time "Checking for existing deployment processes..."

# Find all running deploycluster.sh processes (excluding current process and grep)
EXISTING_PROCESSES=$(ps aux | grep -v grep | grep -v "$$" | grep "deploycluster.sh" || true)

if [ -n "${EXISTING_PROCESSES}" ]; then
  log_time "Found existing deployment processes:"
  echo "${EXISTING_PROCESSES}"

  log_time "Associated log files:"
  ls -la "${SCRIPT_DIR}"/deploy_cluster_*.log 2>/dev/null || echo "No log files found"

  log_time "Exiting to avoid multiple deployments."
  exit 1
fi

log_time "No existing deployment processes found. Proceeding with deployment."

if [ "${1}" = "single" ] || [ "${1}" = "multi" ]; then
  cluster_type="${1}"
else
  cluster_type="${DEPLOY_TYPE}"
fi

# Validate deploy type
if [ "$cluster_type" != "single" ] && [ "$cluster_type" != "multi" ]; then
  log_time "Error: DEPLOY_TYPE must be 'single' or 'multi', got: ${cluster_type}"
  exit 1
fi

log_time "Starting deployment in background with mode: ${cluster_type}"

logfilename="$(date +%Y%m%d_%H%M%S)"

log_time "Check deploy_cluster_${logfilename}.log for more detail."

nohup sh "${SCRIPT_DIR}/deploycluster.sh" "$cluster_type" > "${SCRIPT_DIR}/deploy_cluster_${logfilename}.log" 2>&1 &
