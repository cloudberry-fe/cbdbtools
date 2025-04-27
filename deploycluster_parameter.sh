# environment options
export ADMIN_USER="gpadmin"

## set to 'true' if you want to setup OS parameters only
export INIT_ENV_ONLY="false"
export CLOUDBERRY_RPM="/tmp/hashdata-lightning-release.rpm"
export CLOUDBERRY_RPM_URL="http://downloadlink.com/cloudberry.rpm"
export CLOUDBERRY_BINARY_PATH="/usr/local/cloudberry-db"
export INIT_CONFIGFILE="/tmp/gpinitsystem_config"
export WITH_MIRROR="false"
export DEPLOY_TYPE="single"
## set to 'multi' for multiple nodes deployment
export WITH_STANDBY="false"

# define parameters used for init cluster
export COORDINATOR_PORT="5432"
export COORDINATOR_DIRECTORY="/data0/database/coordinator"
export ARRAY_NAME="CBDB_SANDBOX"
export MACHINE_LIST_FILE="/tmp/hostfile_gpinitsystem"
export SEG_PREFIX="gpseg"
export PORT_BASE="6000"
export DATA_DIRECTORY="/data0/database/primary /data0/database/primary"
export COORDINATOR_HOSTNAME=$(hostname -s)
export TRUSTED_SHELL="ssh"
export CHECK_POINT_SEGMENTS="8"
export ENCODING="UNICODE"
export DATABASE_NAME="gpadmin"

# define parameters used for mirror if WITH_MIRROR set to true
export MIRROR_PORT_BASE="7000"
export MIRROR_DATA_DIRECTORY="/data0/database/mirror /data0/database/mirror"

# define segment host access info, "keyfile" and "password" accees are supported to setup remote servers
export SEGMENT_ACCESS_METHOD="keyfile"
export SEGMENT_ACCESS_USER="root"
export SEGMENT_ACCESS_KEYFILE="/tmp/keyfiles"
export SEGMENT_ACCESS_PASSWORD="XXXXXXXX"

function log_time() {
  printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}
export -f log_time