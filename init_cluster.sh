#!/bin/bash

VARS_FILE="deploycluster_parameter.sh"

source ./${VARS_FILE}

## Database type and version detection
# Default values
export DB_TYPE="cloudberry"
export DB_VERSION="unknown"
export LEGACY_VERSION="false"
export CLOUDBERRY_BINARY_PATH="/usr/local/cloudberry-db"
cluster_env="greenplum_path.sh"

if [ -n "$CLOUDBERRY_RPM" ]; then
    log_time "Detecting database type and version from RPM filename: $CLOUDBERRY_RPM"
    
    # Determine database type and set binary path
    if [[ "$CLOUDBERRY_RPM" == *"greenplum"* ]]; then
        export DB_TYPE="greenplum"
        export CLOUDBERRY_BINARY_PATH="/usr/local/greenplum-db"
        cluster_env="greenplum_path.sh"
        
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
        cluster_env="greenplum_path.sh"
    elif [[ "$CLOUDBERRY_RPM" == *"synxdb4"* ]]; then
        export DB_TYPE="synxdb"
        export DB_VERSION="4"
        export CLOUDBERRY_BINARY_PATH="/usr/local/synxdb4"
        cluster_env="cluster_env.sh"
    elif [[ "$CLOUDBERRY_RPM" == *"synxdb"* ]]; then
        export DB_TYPE="synxdb"
        export DB_VERSION="2"
        export CLOUDBERRY_BINARY_PATH="/usr/local/synxdb"
        cluster_env="synxdb_path.sh"
    fi
    
    log_time "Database type: $DB_TYPE"
    log_time "Database version: $DB_VERSION"
    log_time "CLOUDBERRY_BINARY_PATH set to: $CLOUDBERRY_BINARY_PATH"
    log_time "Cluster environment file: $cluster_env"
else
    log_time "CLOUDBERRY_RPM not specified, using default settings"
    log_time "Database type: $DB_TYPE"
    log_time "CLOUDBERRY_BINARY_PATH: $CLOUDBERRY_BINARY_PATH"
    log_time "Cluster environment file: $cluster_env"
fi

if [ "${1}" == "single" ] || [ "${1}" == "multi" ]; then  
  cluster_type="${1}"  
else  
  cluster_type="${DEPLOY_TYPE}"
fi  

if [ "$cluster_type" = "multi" ]; then  
  COORDINATOR_HOSTNAME=$(sed -n '/##Coordinator hosts/,/##Segment hosts/p' segmenthosts.conf|sed '1d;$d'|awk '{print $2}')
fi


echo "LEGACY_VERSION=${LEGACY_VERSION}"

rm -rf ${INIT_CONFIGFILE} ${MACHINE_LIST_FILE}

echo "ARRAY_NAME=${ARRAY_NAME}" > ${INIT_CONFIGFILE}
echo "MACHINE_LIST_FILE=${MACHINE_LIST_FILE}" >> ${INIT_CONFIGFILE}
echo "SEG_PREFIX=${SEG_PREFIX}" >> ${INIT_CONFIGFILE}
echo "PORT_BASE=${PORT_BASE}" >> ${INIT_CONFIGFILE} 
echo "declare -a DATA_DIRECTORY=(${DATA_DIRECTORY})" >> ${INIT_CONFIGFILE} 
echo "TRUSTED_SHELL=${TRUSTED_SHELL}" >> ${INIT_CONFIGFILE} 
echo "CHECK_POINT_SEGMENTS=${CHECK_POINT_SEGMENTS}" >> ${INIT_CONFIGFILE}
echo "ENCODING=${ENCODING}" >> ${INIT_CONFIGFILE}
echo "DATABASE_NAME=${DATABASE_NAME}" >> ${INIT_CONFIGFILE}

if [ "$LEGACY_VERSION" = "true" ]; then
  echo "MASTER_HOSTNAME=${COORDINATOR_HOSTNAME}" >> ${INIT_CONFIGFILE}
  echo "MASTER_DIRECTORY=${COORDINATOR_DIRECTORY}" >> ${INIT_CONFIGFILE} 
  echo "MASTER_PORT=${COORDINATOR_PORT}" >> ${INIT_CONFIGFILE} 
else
  echo "COORDINATOR_HOSTNAME=${COORDINATOR_HOSTNAME}" >> ${INIT_CONFIGFILE} 
  echo "COORDINATOR_DIRECTORY=${COORDINATOR_DIRECTORY}" >> ${INIT_CONFIGFILE} 
  echo "COORDINATOR_PORT=${COORDINATOR_PORT}" >> ${INIT_CONFIGFILE}  
fi

if [ "$WITH_MIRROR" = "true" ]; then
  echo "MIRROR_PORT_BASE=${MIRROR_PORT_BASE}" >> ${INIT_CONFIGFILE}
  echo "MIRROR_DATA_DIRECTORY=(${MIRROR_DATA_DIRECTORY})" >> ${INIT_CONFIGFILE}
fi

if [ "$cluster_type" = "single" ]; then  
  echo ${COORDINATOR_HOSTNAME} > ${MACHINE_LIST_FILE}
elif [ "$cluster_type" = "multi" ]; then
  sed -n '/##Segment hosts/,/#Hashdata hosts end/p' segmenthosts.conf|sed '1d;$d'|awk '{print $2}' >> ${MACHINE_LIST_FILE}
else  
  echo "DEPLOY_TYPE must be either 'single' or 'multi'"  
fi

chown -R ${ADMIN_USER}:${ADMIN_USER} ${CLOUDBERRY_BINARY_PATH} ${INIT_CONFIGFILE} ${MACHINE_LIST_FILE}

COORDINATOR_DATA_DIRECTORY="${COORDINATOR_DIRECTORY}/${SEG_PREFIX}-1"

su ${ADMIN_USER} -l -c "source ${CLOUDBERRY_BINARY_PATH}/${cluster_env};gpinitsystem -a -c ${INIT_CONFIGFILE} -h ${MACHINE_LIST_FILE}"

su ${ADMIN_USER} -l -c "export COORDINATOR_DATA_DIRECTORY="${COORDINATOR_DATA_DIRECTORY}";source ${CLOUDBERRY_BINARY_PATH}/${cluster_env};psql -d ${DATABASE_NAME} -c \"alter user ${ADMIN_USER} password 'Hashdata@123'\""
echo "host all all 0.0.0.0/0 trust" >> ${COORDINATOR_DATA_DIRECTORY}/pg_hba.conf

echo "Setting up environment variables for ${ADMIN_USER}..."

echo "source ${CLOUDBERRY_BINARY_PATH}/${cluster_env}" >> /home/${ADMIN_USER}/.bashrc

if [ "$LEGACY_VERSION" = "true" ]; then
  sed -i '/MASTER_DATA_DIRECTORY/d' /home/${ADMIN_USER}/.bashrc
  echo "export MASTER_DATA_DIRECTORY=${COORDINATOR_DATA_DIRECTORY}" >> /home/${ADMIN_USER}/.bashrc 
else
  sed -i '/COORDINATOR_DATA_DIRECTORY/d' /home/${ADMIN_USER}/.bashrc
  echo "export COORDINATOR_DATA_DIRECTORY=${COORDINATOR_DATA_DIRECTORY}" >> /home/${ADMIN_USER}/.bashrc 
fi

echo "Finished setting up environment variables for ${ADMIN_USER}..."

su ${ADMIN_USER} -l -c "source ${CLOUDBERRY_BINARY_PATH}/${cluster_env};gpstop -u"
log_time "Finished init cluster..."