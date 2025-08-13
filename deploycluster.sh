VARS_FILE="deploycluster_parameter.sh"

source ./${VARS_FILE}

if [ "${1}" == "single" ] || [ "${1}" == "multi" ]; then  
  cluster_type="${1}"  
else  
  cluster_type="${DEPLOY_TYPE}"
fi  

function delopycluster() {
  sh init_env.sh $cluster_type

  if [ "${INIT_ENV_ONLY}" != "true" ]; then
    sh init_cluster.sh $cluster_type
  fi
}

log_time "Starting deploy cluster..."
delopycluster
log_time "Finished deploy cluster..."