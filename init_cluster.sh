#!/bin/bash

VARS_FILE="deploycluster_parameter.sh"

source ./${VARS_FILE}

if [ "${1}" == "single" ] || [ "${1}" == "multi" ]; then  
  cluster_type="${1}"  
else  
  cluster_type="${DEPLOY_TYPE}"
fi  

if [ "$cluster_type" = "multi" ]; then  
  COORDINATOR_HOSTNAME=$(sed -n '/##Coordinator hosts/,/##Segment hosts/p' segmenthosts.conf|sed '1d;$d'|awk '{print $2}')
fi

LEGACY_VERSION="false"

if [[ "${CLOUDBERRY_RPM}" =~ greenplum ]]; then
  # Extract the version number, compatible with filenames that do not contain open-source-
  version=$(echo ${CLOUDBERRY_RPM} | grep -oP 'greenplum-db-\K[0-9.]+')
  echo "Greenplum version is $version"
  # Get the major version number
  major_version=$(echo $version | cut -d. -f1)
  # Determine if the major version number is less than 7
  if [ $major_version -lt 7 ]; then
    LEGACY_VERSION="true"
    echo "Greenplum version is lower than 7"
  fi
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

su ${ADMIN_USER} -l -c "source ${CLOUDBERRY_BINARY_PATH}/greenplum_path.sh;gpinitsystem -a -c ${INIT_CONFIGFILE} -h ${MACHINE_LIST_FILE}"

su ${ADMIN_USER} -l -c "export COORDINATOR_DATA_DIRECTORY="${COORDINATOR_DATA_DIRECTORY}";source ${CLOUDBERRY_BINARY_PATH}/greenplum_path.sh;psql -d ${DATABASE_NAME} -c \"alter user ${ADMIN_USER} password 'Hashdata@123'\""
echo "host all all 0.0.0.0/0 trust" >> ${COORDINATOR_DATA_DIRECTORY}/pg_hba.conf

echo "Setting up environment variables for ${ADMIN_USER}..."

sed -i '/greenplum_path.sh/d' /home/${ADMIN_USER}/.bashrc
echo "source ${CLOUDBERRY_BINARY_PATH}/greenplum_path.sh" >> /home/${ADMIN_USER}/.bashrc

if [ "$LEGACY_VERSION" = "true" ]; then
  sed -i '/MASTER_DATA_DIRECTORY/d' /home/${ADMIN_USER}/.bashrc
  echo "export MASTER_DATA_DIRECTORY=${COORDINATOR_DATA_DIRECTORY}" >> /home/${ADMIN_USER}/.bashrc 
else
  sed -i '/COORDINATOR_DATA_DIRECTORY/d' /home/${ADMIN_USER}/.bashrc
  echo "export COORDINATOR_DATA_DIRECTORY=${COORDINATOR_DATA_DIRECTORY}" >> /home/${ADMIN_USER}/.bashrc 
fi

echo "Finished setting up environment variables for ${ADMIN_USER}..."

su ${ADMIN_USER} -l -c "source ${CLOUDBERRY_BINARY_PATH}/greenplum_path.sh;gpstop -u"
log_time "Finished init cluster..."