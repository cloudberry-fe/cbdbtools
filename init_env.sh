#!/bin/bash

VARS_FILE="deploycluster_parameter.sh"

source ./${VARS_FILE}

if [ "${1}" == "single" ] || [ "${1}" == "multi" ]; then  
  cluster_type="${1}"  
else  
  cluster_type="${DEPLOY_TYPE}"
fi  

# Log a message with timestamp
function log_time() {
  printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Configure the /etc/hosts file on the coordinator
function config_hostsfile()
{
  log_time "Set /etc/hosts on coordinator..."
  awk '/#Hashdata hosts begin/,/#Hashdata hosts end/' segmenthosts.conf > /tmp/hostsfile
  sed -i '/#Hashdata hosts begin/,/#Hashdata hosts end/d' /etc/hosts
  cat /tmp/hostsfile >> /etc/hosts
}

# Copy necessary files to segment hosts
function copyfile_segment()
{ 
  log_time "Copy init_env_segment.sh id_rsa.pub Cloudberry rpms to segment hosts"
  if [ "${SEGMENT_ACCESS_METHOD}" == "keyfile" ]; then
    bash multiscp.sh -f /tmp/segment_hosts.txt -u ${SEGMENT_ACCESS_USER} -k ${SEGMENT_ACCESS_KEYFILE} -P 22 -t 60 -v -c 10 init_env_segment.sh /tmp
    bash multiscp.sh -f /tmp/segment_hosts.txt -u ${SEGMENT_ACCESS_USER} -k ${SEGMENT_ACCESS_KEYFILE} -P 22 -t 60 -v -c 10 deploycluster_parameter.sh /tmp
    bash multiscp.sh -f /tmp/segment_hosts.txt -u ${SEGMENT_ACCESS_USER} -k ${SEGMENT_ACCESS_KEYFILE} -P 22 -t 60 -v -c 10 /tmp/hostsfile /tmp
    bash multiscp.sh -f /tmp/segment_hosts.txt -u ${SEGMENT_ACCESS_USER} -k ${SEGMENT_ACCESS_KEYFILE} -P 22 -t 60 -v -c 10 /home/${ADMIN_USER}/.ssh/id_rsa.pub /tmp
    bash multiscp.sh -f /tmp/segment_hosts.txt -u ${SEGMENT_ACCESS_USER} -k ${SEGMENT_ACCESS_KEYFILE} -P 22 -t 60 -v -c 10 ${CLOUDBERRY_RPM} ${CLOUDBERRY_RPM}
  elif [ "${SEGMENT_ACCESS_METHOD}" == "password" ]; then
    bash multiscp.sh -f /tmp/segment_hosts.txt -u ${SEGMENT_ACCESS_USER} -p ${SEGMENT_ACCESS_PASSWORD} -P 22 -t 60 -v -c 10 init_env_segment.sh /tmp
    bash multiscp.sh -f /tmp/segment_hosts.txt -u ${SEGMENT_ACCESS_USER} -p ${SEGMENT_ACCESS_PASSWORD} -P 22 -t 60 -v -c 10 deploycluster_parameter.sh /tmp
    bash multiscp.sh -f /tmp/segment_hosts.txt -u ${SEGMENT_ACCESS_USER} -p ${SEGMENT_ACCESS_PASSWORD} -P 22 -t 60 -v -c 10 /tmp/hostsfile /tmp
    bash multiscp.sh -f /tmp/segment_hosts.txt -u ${SEGMENT_ACCESS_USER} -p ${SEGMENT_ACCESS_PASSWORD} -P 22 -t 60 -v -c 10 /home/${ADMIN_USER}/.ssh/id_rsa.pub /tmp
    bash multiscp.sh -f /tmp/segment_hosts.txt -u ${SEGMENT_ACCESS_USER} -p ${SEGMENT_ACCESS_PASSWORD} -P 22 -t 60 -v -c 10 ${CLOUDBERRY_RPM} ${CLOUDBERRY_RPM}
  fi
  log_time "Finished copying init_env_segment.sh id_rsa.pub Cloudberry rpms to segment hosts"
}

# Initialize the environment on segment hosts
function init_segment()
{
  log_time "Start initializing configuration on segment hosts"
  logfilename=$(date +%Y%m%d)_$(date +%H%M%S)
  if [ "${SEGMENT_ACCESS_METHOD}" == "keyfile" ]; then
    bash multissh.sh -f /tmp/segment_hosts.txt -u ${SEGMENT_ACCESS_USER} -k ${SEGMENT_ACCESS_KEYFILE} -P 22 -t 60 -v -c 10 "bash -c 'sh /tmp/init_env_segment.sh \$(hostname) &> /tmp/init_env_segment_\$(hostname)_$logfilename.log'"
  elif [ "${SEGMENT_ACCESS_METHOD}" == "password" ]; then
    bash multissh.sh -f /tmp/segment_hosts.txt -u ${SEGMENT_ACCESS_USER} -p ${SEGMENT_ACCESS_PASSWORD} -P 22 -t 60 -v -c 10 "bash -c 'sh /tmp/init_env_segment.sh \$(hostname) &> /tmp/init_env_segment_\$(hostname)_$logfilename.log'"
  fi
  log_time "Finished initializing configuration on segment hosts"
}

# Setup the environment on the coordinator node for the Hashdata database
# Step 1: Installing Software Dependencies
log_time "Step 1: Installing Software Dependencies..."

# curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.huaweicloud.com/repository/conf/CentOS-7-anon.repo
# yum clean all
# yum makecache

cat /usr/share/zoneinfo/Asia/Macau > /usr/share/zoneinfo/Asia/Shanghai

yum install -y epel-release

yum install -y apr apr-util bash bzip2 curl iproute krb5-devel libcurl libevent libuuid libuv libxml2 libyaml libzstd openldap openssh openssh-clients openssh-server openssl openssl-libs perl python3 python3-psycopg2 python3-psutil python3-devel python3-pyyaml python3-setuptools python39 readline rsync sed tar which zip zlib git passwd wget net-tools

# Step 2: Turn off firewalls
log_time "Step 2: Turn off firewalls..."

systemctl stop firewalld.service
systemctl disable firewalld.service

sed s/^SELINUX=.*$/SELINUX=disabled/ -i /etc/selinux/config
setenforce 0

# Step 3: Configuring system parameters
log_time "Step 3: Configuring system parameters..."

timedatectl set-timezone Asia/Macau

shmall=$(expr $(getconf _PHYS_PAGES) / 2)
shmmax=$(expr $(getconf _PHYS_PAGES) / 2 \* $(getconf PAGE_SIZE))

echo "######################
# HASHDATA CONFIG PARAMS #
######################

kernel.shmall = _SHMALL
kernel.shmmax = _SHMMAX
kernel.shmmni = 4096
vm.overcommit_memory = 2
vm.overcommit_ratio = 95

net.ipv4.ip_local_port_range = 10000 65535
kernel.sem = 250 2048000 200 8192
kernel.sysrq = 1
kernel.core_uses_pid = 1
kernel.msgmnb = 65536
kernel.msgmax = 65536
kernel.msgmni = 2048
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.conf.all.arp_filter = 1
net.ipv4.ipfrag_high_thresh = 41943040
net.ipv4.ipfrag_low_thresh = 31457280
net.ipv4.ipfrag_time = 60
net.core.netdev_max_backlog = 10000
net.core.rmem_max = 2097152
net.core.wmem_max = 2097152
vm.swappiness = 10
vm.zone_reclaim_mode = 0
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 100
vm.dirty_background_ratio = 0
vm.dirty_ratio = 0
vm.dirty_background_bytes = 1610612736
vm.dirty_bytes = 4294967296
kernel.core_pattern=/var/core/core.%h.%t" |sed s/_SHMALL/${shmall}/ | sed s/_SHMMAX/${shmmax}/ >> /etc/sysctl.conf

echo "######################
# HashData CONFIG PARAMS #
######################

* soft nofile 524288
* hard nofile 524288
* soft nproc 131072
* hard nproc 131072
* soft  core unlimited" >> /etc/security/limits.conf

cat /usr/share/zoneinfo/Asia/Shanghai > /etc/localtime 

sysctl -p
log_time "More optimization parameters need to be configured manually for production purpose, please refer to documentation..."

echo "######################
# HashData SSH PARAMS #
######################

ClientAliveInterval 60
ClientAliveCountMax 3
MaxStartups 1000:30:3000
MaxSessions 3000" >> /etc/ssh/sshd_config

systemctl restart sshd

# Step 4: Create database admin user
log_time "Step 4: Create database user ${ADMIN_USER}..."

if ! id "$ADMIN_USER" &>/dev/null; then
  groupadd ${ADMIN_USER} 
  useradd ${ADMIN_USER} -r -m -g ${ADMIN_USER}
  usermod -aG wheel ${ADMIN_USER}
  echo ${ADMIN_USER_PASSWORD}|passwd --stdin ${ADMIN_USER}
  echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
  chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}
else 
  if grep -q "COORDINATOR_DATA_DIRECTORY" /home/${ADMIN_USER}/.bashrc; then
    echo "The COORDINATOR_DATA_DIRECTORY setting exists, commenting it out..."
    sed -i "/COORDINATOR_DATA_DIRECTORY/s/^/#/" /home/${ADMIN_USER}/.bashrc
  fi
  if grep -q "greenplum_path.sh" /home/${ADMIN_USER}/.bashrc; then
    echo "The greenplum_path.sh setting exists, commenting it out..."
    sed -i "/greenplum_path.sh/s/^/#/" /home/${ADMIN_USER}/.bashrc
  fi
fi

# Step 5: Create folders needed for the cluster
log_time "Step 5: Create folders needed..."
rm -rf ${COORDINATOR_DIRECTORY} ${DATA_DIRECTORY}
mkdir -p ${COORDINATOR_DIRECTORY} ${DATA_DIRECTORY}
chown -R ${ADMIN_USER}:${ADMIN_USER} ${COORDINATOR_DIRECTORY} ${DATA_DIRECTORY}

if [ "${WITH_MIRROR}" = "true" ]; then
  rm -rf ${MIRROR_DATA_DIRECTORY}
  mkdir -p ${MIRROR_DATA_DIRECTORY}
  chown -R ${ADMIN_USER}:${ADMIN_USER} ${MIRROR_DATA_DIRECTORY}
fi

# Check the INIT_ENV_ONLY environment variable
if [ "${INIT_ENV_ONLY}" != "true" ]; then

  # Step 6: Installing database software
  log_time "Step 5: Installing database software..."
  
  rpmfile=$(ls ${CLOUDBERRY_RPM} 2>/dev/null)
    
  if [ -z "$rpmfile" ]; then  
    wget ${CLOUDBERRY_RPM_URL} -O ${CLOUDBERRY_RPM}
  fi
  
  # Clean up previous installation checks and check if the variable contains the word "greenplum"
  
  # Ensure the CLOUDBERRY_RPM variable is set
  if [ -z "${CLOUDBERRY_RPM}" ]; then
      echo "Error: The environment variable CLOUDBERRY_RPM is not set."
      exit 1
  fi
  
  # Check if the RPM package name contains greenplum or cloudberry
  if [[ "${CLOUDBERRY_RPM}" =~ greenplum ]]; then
      keyword="greenplum"
  elif [[ "${CLOUDBERRY_RPM}" =~ cloudberry ]]; then
      keyword="cloudberry"
  else
      keyword="none"
  fi
  
  # Handle installation and permissions based on the keyword
  if [ "${keyword}" != "none" ]; then
      # Check if there is a directory containing the keyword under /usr/local
      if find /usr/local -maxdepth 1 -type d -name "*${keyword}*" -print -quit | grep -q .; then
          echo "The ${keyword} directory is detected, force installing the RPM and modifying permissions..."
          soft_link="/usr/local/${keyword}-db"
          # Check if the symbolic link exists
          if [ -L "$soft_link" ]; then
          # Remove the symbolic link
            rm -f "$soft_link"
            echo "The symbolic link $soft_link has been removed"
          else
            echo "The symbolic link $soft_link does not exist"
          fi
          echo "Operation completed!"
          rpm -ivh ${CLOUDBERRY_RPM} --force
      else
          echo "The ${keyword} directory is not found, using YUM to install..."
          yum install -y "${CLOUDBERRY_RPM}"
      fi
     # Modify directory permissions  
    chown -R ${ADMIN_USER}:${ADMIN_USER} /usr/local/${keyword}*
    echo "The owner of /usr/local/${keyword}* has been changed to ${ADMIN_USER}:${ADMIN_USER}"
  else
      echo "No relevant product keyword is detected, trying to use YUM to install, manual permission configuration may be required..."
      yum install -y ${CLOUDBERRY_RPM}
  fi
fi

# Execute file copying and remote initialization
config_hostsfile
copyfile_segment
init_segment

log_time "Finished environment initialization on the coordinator and segment nodes..."