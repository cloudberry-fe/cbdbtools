#!/bin/bash
set -o pipefail

VARS_FILE="deploycluster_parameter.sh"

SEGMENT_HOSTNAME="$1"
working_dir="$2"

source "${working_dir}/${VARS_FILE}"
source "${working_dir}/common.sh"

log_time "Starting env init on segment node ${SEGMENT_HOSTNAME}..."

#Step 1: Installing Software Dependencies
log_time "Step 1: Installing Software Dependencies..."
configure_repo
configure_timezone "${TIMEZONE:-Asia/Shanghai}"
install_dependencies

#Step 2: Turn off firewalls
log_time "Step 2: Turn off firewalls..."
disable_firewall

#Step 3: Configuring system parameters
log_time "Step 3: Configuring system parameters..."
configure_sysctl
configure_limits
configure_sshd
configure_logind
disable_thp
configure_ntp

#Step 4: Create database user
log_time "Step 4: Create database user ${ADMIN_USER}..."
create_admin_user "${ADMIN_USER}" "${ADMIN_USER_PASSWORD}"

#Step 5: Setup user access keys and configure host names
log_time "Step 5: Setup user access keys and configure host names."

rm -f "/home/${ADMIN_USER}/.ssh/id_rsa.pub"
rm -f "/home/${ADMIN_USER}/.ssh/id_rsa"
rm -f "/home/${ADMIN_USER}/.ssh/authorized_keys"
rm -f "/home/${ADMIN_USER}/.ssh/known_hosts"

# Configure SSH client to suppress host key warnings for cluster hosts
cluster_hosts=$(awk '{print $2}' "${working_dir}/hostsfile" 2>/dev/null | paste -sd' ')
cat > "/home/${ADMIN_USER}/.ssh/config" <<SSHEOF
Host ${cluster_hosts:-*} localhost
    StrictHostKeyChecking no
    LogLevel ERROR
SSHEOF
chown "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh/config"
chmod 600 "/home/${ADMIN_USER}/.ssh/config"

su "${ADMIN_USER}" -l -c "ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ''"
su "${ADMIN_USER}" -l -c "cat /home/${ADMIN_USER}/.ssh/id_rsa.pub > /home/${ADMIN_USER}/.ssh/authorized_keys"

sed -i '/#Hashdata hosts begin/,/#Hashdata hosts end/d' /etc/hosts
cat "${working_dir}/hostsfile" >> /etc/hosts
change_hostname "${SEGMENT_HOSTNAME}"

#Step 6: Installing database software
filename=$(basename "$CLOUDBERRY_RPM")
install_db_software "${working_dir}/${filename}" "${DB_KEYWORD}" "${CLOUDBERRY_BINARY_PATH}"

#Step 7: Create data directories
create_data_directories

log_time "Finished env init setting on segment node ${SEGMENT_HOSTNAME}."
