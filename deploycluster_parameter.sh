## Mandatory options
export ADMIN_USER="gpadmin"
export ADMIN_USER_PASSWORD="Cbdb@1234"
export CLOUDBERRY_RPM="/root/hashdata-lightning-2.4.0-1.x86_64.rpm"
export COORDINATOR_HOSTNAME="mdw"
export COORDINATOR_IP="10.14.3.217"
# Set to 'multi' for multi-node deployment
export DEPLOY_TYPE="multi"

## Set to 'false' to skip database software installation (e.g. for cluster reinitialization)
export INSTALL_DB_SOFTWARE="true"
## Set to 'true' to set up OS parameters only (no database installation or cluster initialization)
export INIT_ENV_ONLY="true"
export CLOUDBERRY_RPM_URL="http://downloadlink.com/cloudberry.rpm"
export INIT_CONFIGFILE="/tmp/gpinitsystem_config"
export WITH_MIRROR="false"
export WITH_STANDBY="false"
export MAUNAL_YUM_REPO="false"
export TIMEZONE="Asia/Shanghai"

# Parameters used for cluster initialization
export COORDINATOR_PORT="5432"
export COORDINATOR_DIRECTORY="/data0/database/coordinator-synx"
export ARRAY_NAME="CBDB_SANDBOX"
export MACHINE_LIST_FILE="/tmp/hostfile_gpinitsystem"
export SEG_PREFIX="gpseg"
export PORT_BASE="6000"
export DATA_DIRECTORY="/data0/database/primary-synx /data0/database/primary-synx /data0/database/primary-synx /data0/database/primary-synx /data0/database/primary-synx /data0/database/primary-synx /data0/database/primary-synx /data0/database/primary-synx"
export TRUSTED_SHELL="ssh"
export CHECK_POINT_SEGMENTS="8"
export ENCODING="UNICODE"
export DATABASE_NAME="gpadmin"

# Mirror parameters (used if WITH_MIRROR is set to true)
export MIRROR_PORT_BASE="7000"
export MIRROR_DATA_DIRECTORY="/data0/database/mirror /data0/database/mirror"

# Segment host access (used if DEPLOY_TYPE="multi")
# Both "keyfile" and "password" access methods are supported for remote setup
export SEGMENT_ACCESS_METHOD="keyfile"
export SEGMENT_ACCESS_USER="root"
export SEGMENT_ACCESS_KEYFILE="/tmp/uploads/id_rsa"
export SEGMENT_ACCESS_PASSWORD="XXXXXXXX"

# Utility function for logging with timestamps
function log_time() {
  printf "[%s] %b\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}
export -f log_time
