VARS_FILE="deploycluster_parameter.sh"

source ./${VARS_FILE}

log_time "CBDB tools version is: V1.2_dev20251111"

## Database type and version detection
# Default values
export DB_TYPE="unknown"
export DB_KEYWORD="unknown"
export DB_VERSION="unknown"
export LEGACY_VERSION="false"
export CLOUDBERRY_BINARY_PATH="/usr/local/cloudberry-db"
export CLUSTER_ENV="greenplum_path.sh"

if [ -n "$CLOUDBERRY_RPM" ]; then
    log_time "Detecting database type and version from RPM filename: $CLOUDBERRY_RPM"
    
    # Determine database type and set binary path
    if [[ "$CLOUDBERRY_RPM" == *"greenplum"* ]]; then
        export DB_TYPE="Greenplum"
        export DB_KEYWORD="greenplum"
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
        export DB_TYPE="Hashdata Lightning"
        export DB_KEYWORD="hashdata-lightning-2"
        export DB_VERSION=$(echo ${CLOUDBERRY_RPM} | grep -oP 'hashdata-lightning-\K[0-9.]+')
        export CLOUDBERRY_BINARY_PATH="/usr/local/hashdata-lightning"
        export CLUSTER_ENV="greenplum_path.sh"
    elif [[ "$CLOUDBERRY_RPM" == *"hashdata-lightning-1"* ]]; then
        export DB_TYPE="Hashdata Lightning"
        export DB_KEYWORD="cloudberry"
        export DB_VERSION=$(echo ${CLOUDBERRY_RPM} | grep -oP 'hashdata-lightning-\K[0-9.]+')
        export CLOUDBERRY_BINARY_PATH="/usr/local/cloudberry-db"
        export CLUSTER_ENV="greenplum_path.sh"
        export LEGACY_VERSION="false"
    elif [[ "$CLOUDBERRY_RPM" == *"synxdb4"* ]]; then
        export DB_TYPE="Synxdb"
        export DB_KEYWORD="synxdb4"
        export DB_VERSION=$(echo ${CLOUDBERRY_RPM} | grep -oP 'synxdb4-\K[0-9.]+')
        export CLOUDBERRY_BINARY_PATH="/usr/local/synxdb4"
        export CLUSTER_ENV="cloudberry-env.sh"
    elif [[ "$CLOUDBERRY_RPM" == *"synxdb-2"* ]]; then
        export DB_TYPE="Synxdb"
        export DB_KEYWORD="synxdb-2"
        export DB_VERSION=$(echo ${CLOUDBERRY_RPM} | grep -oP 'synxdb-\K[0-9.]+')
        export CLOUDBERRY_BINARY_PATH="/usr/local/synxdb"
        export CLUSTER_ENV="synxdb_path.sh"
        export LEGACY_VERSION="true"
    elif [[ "$CLOUDBERRY_RPM" == *"synxdb-1"* ]]; then
        export DB_TYPE="Synxdb"
        export DB_KEYWORD="synxdb-1"
        export DB_VERSION=$(echo ${CLOUDBERRY_RPM} | grep -oP 'synxdb-\K[0-9.]+')
        export CLOUDBERRY_BINARY_PATH="/usr/local/synxdb"
        export CLUSTER_ENV="synxdb_path.sh"
        export LEGACY_VERSION="true"
    elif [[ "$CLOUDBERRY_RPM" == *"cloudberry"* ]]; then
        export DB_TYPE="Cloudberry"
        export DB_KEYWORD="cloudberry"
        export DB_VERSION=$(echo ${CLOUDBERRY_RPM} | grep -oP 'cloudberry-db-\K[0-9.]+')
        export CLOUDBERRY_BINARY_PATH="/usr/local/cloudberry-db"
        export CLUSTER_ENV="greenplum_path.sh"
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

## Update parameters in deploycluster_parameter.sh
# Function to update or add parameters in deploycluster_parameter.sh
# Parameters:
#   $1 - Parameter name
#   $2 - Parameter value
function update_deploy_parameter() {
    local param_name="$1"
    local param_value="$2"
    local param_file="./${VARS_FILE}"
    
    # Ensure parameter file exists
    if [ ! -f "${param_file}" ]; then
        log_time "Error: Parameter file ${param_file} not found"
        return 1
    fi
    
    # Check if parameter exists in the file
    if grep -q "^export ${param_name}=" "${param_file}"; then
        # Delete existing parameter - CentOS/Linux syntax
        sed -i "/^export ${param_name}=.*/d" "${param_file}"
        if [ $? -eq 0 ]; then
            log_time "Deleted existing ${param_name} from ${param_file}"
        else
            log_time "Error deleting ${param_name} from ${param_file}"
            return 1
        fi
    fi
    
    # Add new parameter setting without adding extra newlines
    # Use printf to avoid adding implicit newlines
    printf "export %s=\"%s\"\n" "${param_name}" "${param_value}" >> "${param_file}"
    log_time "Added ${param_name}=${param_value} to ${param_file}"
}

# Update parameters
sed -i '/^export -f log_time$/q' "./${VARS_FILE}"
printf "\n" >> "./${VARS_FILE}"

update_deploy_parameter "DB_TYPE" "$DB_TYPE"
update_deploy_parameter "DB_KEYWORD" "$DB_KEYWORD"
update_deploy_parameter "DB_VERSION" "$DB_VERSION"
update_deploy_parameter "LEGACY_VERSION" "$LEGACY_VERSION"
update_deploy_parameter "CLOUDBERRY_BINARY_PATH" "$CLOUDBERRY_BINARY_PATH"
update_deploy_parameter "CLUSTER_ENV" "$CLUSTER_ENV"

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