#/bin/bash

VARS_FILE="deploycluster_parameter.sh"

source ./${VARS_FILE}

log_time "Install necessary tools: wget and sshpass."

yum install -y wget sshpass

log_time "Start downloading HashData binaries..."

if [ "${1}" == "single" ] || [ "${1}" == "multi" ]; then  
  cluster_type="${1}"  
else  
  cluster_type="${DEPLOY_TYPE}"
fi  

log_time "Started deploy the cluster in backgroud with mode ${DEPLOY_TYPE}."

logfilename=$(date +%Y%m%d)_$(date +%H%M%S)

log_time "Check deploy_cluster_$logfilename.log for more detail."

nohup sh deploycluster.sh $cluster_type > deploy_cluster_$logfilename.log 2>&1 &