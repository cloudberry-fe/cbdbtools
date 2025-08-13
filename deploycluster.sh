VARS_FILE="deploycluster_parameter.sh"

source ./${VARS_FILE}

## Dynamically set CLOUDBERRY_BINARY_PATH based on RPM filename
# Default path: /usr/local/cloudberry-db
if [ -n "$CLOUDBERRY_RPM" ]; then
    echo "Setting CLOUDBERRY_BINARY_PATH based on RPM filename: $CLOUDBERRY_RPM"
    
    # Declare associative array for RPM keyword to path mapping
    declare -A rpm_paths=(
        ["greenplum"]="/usr/local/greenplum-db"
        ["hashdata-lightning-2"]="/usr/local/hashdata-lightning"
        ["synxdb4"]="/usr/local/synxdb4"
        ["synxdb"]="/usr/local/synxdb"
    )
    
    # Iterate through the array to find matching keyword
    for keyword in "${!rpm_paths[@]}"; do
        if [[ "$CLOUDBERRY_RPM" == *"$keyword"* ]]; then
            export CLOUDBERRY_BINARY_PATH="${rpm_paths[$keyword]}" 
            break
        fi
    done
    
    echo "CLOUDBERRY_BINARY_PATH set to: $CLOUDBERRY_BINARY_PATH"
else
    echo "CLOUDBERRY_RPM not specified, using default CLOUDBERRY_BINARY_PATH: $CLOUDBERRY_BINARY_PATH"
fi

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