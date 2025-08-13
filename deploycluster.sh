VARS_FILE="deploycluster_parameter.sh"

source ./${VARS_FILE}

## Database type and version detection
# Default values
export DB_TYPE="cloudberry"
export DB_VERSION="unknown"
export LEGACY_VERSION="false"
export CLOUDBERRY_BINARY_PATH="/usr/local/cloudberry-db"
export CLUSTER_ENV="greenplum_path.sh"

if [ -n "$CLOUDBERRY_RPM" ]; then
    log_time "Detecting database type and version from RPM filename: $CLOUDBERRY_RPM"
    
    # Determine database type and set binary path
    if [[ "$CLOUDBERRY_RPM" == *"greenplum"* ]]; then
        export DB_TYPE="greenplum"
        export CLOUDBERRY_BINARY_PATH="/usr/local/greenplum-db"
        export CLUSTER_ENV="greenplum_path.sh"
        
        # Extract Greenplum version
        version=$(echo ${CLOUDBERRY_RPM} | grep -oP 'greenplum-db-\K[0-9.]+')
        export DB_VERSION="$version"
        log_time "Greenplum version detected: $version"
        
        # Check if legacy version (major version < 7)
        major_version=$(echo $version | cut -d. -f1)
        if [ $major_version -lt 7 ]; then
            export LEGACY_VERSION="true"
            log_time "Detected legacy Greenplum version (major version < 7)"
        fi
    elif [[ "$CLOUDBERRY_RPM" == *"hashdata-lightning-2"* ]]; then
        export DB_TYPE="hashdata-lightning"
        export CLOUDBERRY_BINARY_PATH="/usr/local/hashdata-lightning"
        export CLUSTER_ENV="greenplum_path.sh"
    elif [[ "$CLOUDBERRY_RPM" == *"synxdb4"* ]]; then
        export DB_TYPE="synxdb"
        export DB_VERSION="4"
        export CLOUDBERRY_BINARY_PATH="/usr/local/synxdb4"
        export CLUSTER_ENV="cluster_env.sh"
    elif [[ "$CLOUDBERRY_RPM" == *"synxdb"* ]]; then
        export DB_TYPE="synxdb"
        export DB_VERSION="2"
        export CLOUDBERRY_BINARY_PATH="/usr/local/synxdb"
        export CLUSTER_ENV="synxdb_path.sh"
    fi
    
    log_time "Database type: $DB_TYPE"
    log_time "Database version: $DB_VERSION"
    log_time "CLOUDBERRY_BINARY_PATH set to: $CLOUDBERRY_BINARY_PATH"
    log_time "Cluster environment file: $CLUSTER_ENV"
else
    log_time "CLOUDBERRY_RPM not specified, using default settings"
    log_time "Database type: $DB_TYPE"
    log_time "CLOUDBERRY_BINARY_PATH: $CLOUDBERRY_BINARY_PATH"
    log_time "Cluster environment file: $CLUSTER_ENV"
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