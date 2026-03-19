#!/bin/bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VARS_FILE="deploycluster_parameter.sh"

source "${SCRIPT_DIR}/${VARS_FILE}"

log_time "CBDB tools version is: V1.3"

## Database type and version detection
# Default values
export DB_TYPE="unknown"
export DB_KEYWORD="unknown"
export DB_VERSION="unknown"
export LEGACY_VERSION="false"
export CLOUDBERRY_BINARY_PATH="/usr/local/cloudberry-db"
export CLUSTER_ENV="greenplum_path.sh"

if [ -n "$CLOUDBERRY_RPM" ]; then
    log_time "Detecting database type from package: $CLOUDBERRY_RPM"

    if [[ "$CLOUDBERRY_RPM" == *"greenplum"* ]]; then
        export DB_TYPE="Greenplum"
        export DB_KEYWORD="greenplum"
        export CLOUDBERRY_BINARY_PATH="/usr/local/greenplum-db"
        export CLUSTER_ENV="greenplum_path.sh"

        version=$(echo "${CLOUDBERRY_RPM}" | grep -oP 'greenplum-db-\K[0-9.]+')
        export DB_VERSION="$version"
        log_time "Greenplum version: $version"

        major_version=$(echo "$version" | cut -d. -f1)
        if [ -n "$major_version" ] && [ "$major_version" -lt 7 ] 2>/dev/null; then
            export LEGACY_VERSION="true"
            log_time "Detected legacy Greenplum (major < 7)"
        fi
    elif [[ "$CLOUDBERRY_RPM" == *"hashdata-lightning"* ]]; then
        export DB_TYPE="Hashdata Lightning"
        # Extract version from both RPM (hashdata-lightning-2.4.0) and DEB (hashdata-lightning_2.4.0) naming
        export DB_VERSION=$(echo "${CLOUDBERRY_RPM}" | grep -oP 'hashdata-lightning[-_]\K[0-9.]+')
        local hl_major=$(echo "$DB_VERSION" | cut -d. -f1)
        if [ "$hl_major" = "1" ]; then
            export DB_KEYWORD="cloudberry"
            export CLOUDBERRY_BINARY_PATH="/usr/local/cloudberry-db"
        else
            export DB_KEYWORD="hashdata-lightning-${hl_major}"
            export CLOUDBERRY_BINARY_PATH="/usr/local/hashdata-lightning"
        fi
        export CLUSTER_ENV="greenplum_path.sh"
    elif [[ "$CLOUDBERRY_RPM" == *"synxdb4"* ]]; then
        export DB_TYPE="Synxdb"
        export DB_KEYWORD="synxdb4"
        export DB_VERSION=$(echo "${CLOUDBERRY_RPM}" | grep -oP 'synxdb4-\K[0-9.]+')
        export CLOUDBERRY_BINARY_PATH="/usr/local/synxdb4"
        export CLUSTER_ENV="cloudberry-env.sh"
    elif [[ "$CLOUDBERRY_RPM" == *"synxdb-2"* ]]; then
        export DB_TYPE="Synxdb"
        export DB_KEYWORD="synxdb-2"
        export DB_VERSION=$(echo "${CLOUDBERRY_RPM}" | grep -oP 'synxdb-\K[0-9.]+')
        export CLOUDBERRY_BINARY_PATH="/usr/local/synxdb"
        export CLUSTER_ENV="synxdb_path.sh"
        export LEGACY_VERSION="true"
    elif [[ "$CLOUDBERRY_RPM" == *"synxdb-1"* ]]; then
        export DB_TYPE="Synxdb"
        export DB_KEYWORD="synxdb-1"
        export DB_VERSION=$(echo "${CLOUDBERRY_RPM}" | grep -oP 'synxdb-\K[0-9.]+')
        export CLOUDBERRY_BINARY_PATH="/usr/local/synxdb"
        export CLUSTER_ENV="synxdb_path.sh"
        export LEGACY_VERSION="true"
    elif [[ "$CLOUDBERRY_RPM" == *"cloudberry"* ]]; then
        export DB_TYPE="Cloudberry"
        export DB_KEYWORD="cloudberry"
        export DB_VERSION=$(echo "${CLOUDBERRY_RPM}" | grep -oP 'cloudberry-db-\K[0-9.]+')
        export CLOUDBERRY_BINARY_PATH="/usr/local/cloudberry-db"
        export CLUSTER_ENV="greenplum_path.sh"
    fi

    log_time "Database type: $DB_TYPE"
    log_time "Database version: $DB_VERSION"
    log_time "Binary path: $CLOUDBERRY_BINARY_PATH"
    log_time "Cluster env: $CLUSTER_ENV"
else
    log_time "CLOUDBERRY_RPM not specified, using default settings"
fi

## Update parameters in deploycluster_parameter.sh
function update_deploy_parameter() {
    local param_name="$1"
    local param_value="$2"
    local param_file="${SCRIPT_DIR}/${VARS_FILE}"

    if [ ! -f "${param_file}" ]; then
        log_time "Error: Parameter file ${param_file} not found"
        return 1
    fi

    # Remove existing parameter if present
    if grep -q "^export ${param_name}=" "${param_file}"; then
        sed -i "/^export ${param_name}=.*/d" "${param_file}"
    fi

    printf 'export %s="%s"\n' "${param_name}" "${param_value}" >> "${param_file}"
    log_time "Set ${param_name}=${param_value}"
}

# Truncate file after log_time export and append detected values
sed -i '/^export -f log_time$/q' "${SCRIPT_DIR}/${VARS_FILE}"
printf "\n" >> "${SCRIPT_DIR}/${VARS_FILE}"

update_deploy_parameter "DB_TYPE" "$DB_TYPE"
update_deploy_parameter "DB_KEYWORD" "$DB_KEYWORD"
update_deploy_parameter "DB_VERSION" "$DB_VERSION"
update_deploy_parameter "LEGACY_VERSION" "$LEGACY_VERSION"
update_deploy_parameter "CLOUDBERRY_BINARY_PATH" "$CLOUDBERRY_BINARY_PATH"
update_deploy_parameter "CLUSTER_ENV" "$CLUSTER_ENV"

if [ "${1}" = "single" ] || [ "${1}" = "multi" ]; then
  cluster_type="${1}"
else
  cluster_type="${DEPLOY_TYPE}"
fi

deploycluster() {
  bash "${SCRIPT_DIR}/init_env.sh" "$cluster_type"

  if [ "${INIT_ENV_ONLY}" != "true" ]; then
    bash "${SCRIPT_DIR}/init_cluster.sh" "$cluster_type"
  else
    log_time "INIT_ENV_ONLY=true, skipping cluster initialization."
  fi
}

log_time "Starting deploy cluster..."
deploycluster
log_time "Finished deploy cluster."
