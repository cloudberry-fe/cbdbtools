#!/bin/bash

VARS_FILE="deploycluster_parameter.sh"

SEGMENT_HOSTNAME="$1"
working_dir="$2"

source ${working_dir}/${VARS_FILE}

function log_time() {
  printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

change_hostname() {
    local new_hostname="$1"
    
    # Validate root privileges
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This operation requires root privileges." >&2
        return 1
    fi
    
    # Validate hostname format
    if [[ ! "$new_hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]]; then
        echo "Error: Invalid hostname. Must start/end with alphanumeric and can contain hyphens." >&2
        return 1
    fi
    
    local current_hostname=$(hostname)
    echo "Changing hostname from $current_hostname to $new_hostname..."
    
    # Detect OS type
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        
        case "$ID" in
            ubuntu|debian)
                echo "$new_hostname" > /etc/hostname
                sed -i "s/127.0.1.1[[:space:]]*$current_hostname/127.0.1.1\t$new_hostname/g" /etc/hosts
                hostnamectl set-hostname "$new_hostname"
                ;;
                
            centos|rhel|fedora)
                echo "$new_hostname" > /etc/hostname
                sed -i "s/127.0.0.1[[:space:]]*$current_hostname/127.0.0.1\t$new_hostname/g" /etc/hosts
                hostnamectl set-hostname "$new_hostname"
                ;;
                
            *)
                if [[ -f /etc/hostname ]]; then
                    echo "$new_hostname" > /etc/hostname
                fi
                if [[ -f /etc/hosts ]]; then
                    sed -i "s/127.0.1.1[[:space:]]*$current_hostname/127.0.1.1\t$new_hostname/g" /etc/hosts
                fi
                if command -v hostnamectl &>/dev/null; then
                    hostnamectl set-hostname "$new_hostname"
                else
                    hostname "$new_hostname"
                    echo "Warning: Hostname change may not be persistent after reboot." >&2
                fi
                ;;
        esac
        
    elif [[ "$(uname)" == "Darwin" ]]; then
        scutil --set HostName "$new_hostname"
        scutil --set LocalHostName "$new_hostname"
        scutil --set ComputerName "$new_hostname"
        dscacheutil -flushcache
        
    else
        echo "Error: Unsupported operating system." >&2
        return 1
    fi
    
    echo "Hostname changed to: $(hostname)"
    return 0
}    

#Setup the env setting on Linux OS for Hashdata database

#Step 1: Installing Software Dependencies

log_time "Step 1: Installing Software Dependencies..."

if [ "${MAUNAL_YUM_REPO}" != "true" ]; then
  # Check if the /etc/os-release file exists
  if [ -f /etc/os-release ]; then
      # Source the /etc/os-release file to get the system information
      source /etc/os-release
  
      # Checking for Oracle Linux
      IS_ORACLE_LINUX=0
      if [[ "$ID" == "ol" || "$NAME" == *"Oracle Linux"* ]]; then
          IS_ORACLE_LINUX=1
          echo "This is Oracle Linux"
      fi
  
      # Extract the first digit of the VERSION_ID
      first_digit=$(echo "$VERSION_ID" | cut -c1)
  
      # Execute different operations based on the first digit of the VERSION_ID
      case "$first_digit" in
          7)
              # Operation in 7
              echo "This is a operating system with version ID starting with 7."
              rm -rf /etc/yum.repos.d/*
              curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.huaweicloud.com/repository/conf/CentOS-7-anon.repo
              yum clean all
              yum makecache
              yum install -y libcgroup-tools
              
              # You can add specific commands for Operation A here, for example, setting up the environment on the coordinator node
              # sh init_env.sh single
              ;;
          8)
              # Operation in 8
              echo "This is a operating system with version ID starting with 8."
              if [ $IS_ORACLE_LINUX -ne 1 ]; then
                rm -rf /etc/yum.repos.d/*
                curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.huaweicloud.com/repository/conf/CentOS-8-anon.repo
                yum clean all
                yum makecache
              else
                log_time "Skip set yum repo for Oracle Linux."
              fi
              # You can add specific commands for Operation B here
              ;;
          9)
              # Operation in 9
              echo "This is a operating system with version ID starting with 9. Executing Operation C."
              # You can add specific commands for Operation C here, such as starting the database cluster deployment
              # bash run.sh multi
              ;;
          *)
              echo "Unsupported OS version ID starting with: $first_digit"
              ;;
      esac
  else
      echo "/etc/os-release file not found. Unable to determine the operating system version."
  fi
else
  log_time "Please make sure YUM repo and dependent packages are correctly configured for all hosts manually."
fi

cat /usr/share/zoneinfo/Asia/Macau > /usr/share/zoneinfo/Asia/Shanghai

yum install -y epel-release

yum install -y apr apr-util bash bzip2 curl iproute krb5-devel libcurl libevent libuuid libuv libxml2 libyaml libzstd openldap openssh openssh-clients openssh-server openssl openssl-libs perl python3 python3-psycopg2 python3-psutil python3-devel python3-pyyaml python3-setuptools python39 readline rsync sed tar which zip zlib lz4 keyutils

yum install -y git passwd wget net-tools nmon libicu

#Step 2: Turn off firewalls
log_time "Step 2: Turn off firewalls..."

systemctl stop firewalld.service
systemctl disable firewalld.service

sed s/^SELINUX=.*$/SELINUX=disabled/ -i /etc/selinux/config
setenforce 0


#Step 3: Configuring system parameters
log_time "Step 3: Configuring system parameters..."

timedatectl set-timezone Asia/Macau

shmall=$(expr $(getconf _PHYS_PAGES) / 2)
shmmax=$(expr $(getconf _PHYS_PAGES) / 2 \* $(getconf PAGE_SIZE))
min_free_kbytes=$(awk 'BEGIN {OFMT = "%.0f";} /MemTotal/ {print $2 * .03;}' /proc/meminfo)

# Clean up previous HashData sysctl configuration
sed -i '/# BEGIN HashData sysctl CONFIG/,/# END HashData sysctl CONFIG/d' /etc/sysctl.conf

echo "# BEGIN HashData sysctl CONFIG
######################
# HashData CONFIG PARAMS #
######################

kernel.shmall = _SHMALL
kernel.shmmax = _SHMMAX
kernel.shmmni = 32768
vm.overcommit_memory = 2
vm.overcommit_ratio = 95
vm.min_free_kbytes = _MIN_FREE_KBYTES
net.ipv4.ip_local_port_range = 10000 65535
kernel.sem = 32000 1048576000 1000 32768
kernel.sysrq = 1
kernel.core_uses_pid = 1
kernel.msgmnb = 65536
kernel.msgmax = 65536
kernel.msgmni = 32768
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.conf.all.arp_filter = 1
net.ipv4.ipfrag_high_thresh = 536870912
net.ipv4.ipfrag_low_thresh = 429496730
net.ipv4.ipfrag_time = 60
net.core.netdev_max_backlog = 10000
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
vm.swappiness = 1
vm.zone_reclaim_mode = 0
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 100
vm.dirty_background_bytes = 1610612736
vm.dirty_background_ratio = 0
vm.dirty_ratio = 0
vm.dirty_bytes = 4294967296
kernel.core_pattern=/var/core/core.%h.%t
# END HashData sysctl CONFIG" |sed s/_SHMALL/${shmall}/ | sed s/_SHMMAX/${shmmax}/ | sed s/_MIN_FREE_KBYTES/${min_free_kbytes}/ >> /etc/sysctl.conf

sed -i '/# BEGIN HashData limits CONFIG/,/# END HashData limits CONFIG/d' /etc/security/limits.conf

echo "# BEGIN HashData limits CONFIG
######################
# HashData CONFIG PARAMS #
######################

* soft nofile 524288
* hard nofile 524288
* soft nproc 131072
* hard nproc 131072
* soft  core unlimited
# END HashData limits CONFIG" >> /etc/security/limits.conf

cat /usr/share/zoneinfo/Asia/Shanghai > /etc/localtime 

sysctl -p
log_time "More optimization parameters need to be configured manually for production purpose, please refer to documentation..."

sed -i '/# BEGIN HashData sshd CONFIG/,/# END HashData sshd CONFIG/d' /etc/ssh/sshd_config

echo "# BEGIN HashData sshd CONFIG
######################
# HashData SSH PARAMS #
######################

ClientAliveInterval 60
ClientAliveCountMax 3
MaxStartups 1000:30:3000
MaxSessions 3000
# END HashData sshd CONFIG" >> /etc/ssh/sshd_config

systemctl restart sshd

#Step 4: Create database user
log_time "Step 4: Create database user ${ADMIN_USER}..."

if ! id "$ADMIN_USER" &>/dev/null; then
  groupadd ${ADMIN_USER} 
  useradd ${ADMIN_USER} -r -m -g ${ADMIN_USER}
  usermod -aG wheel ${ADMIN_USER}
  echo ${ADMIN_USER_PASSWORD}|passwd --stdin ${ADMIN_USER}
  echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers
  chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}
else
  # Combine all patterns to be cleaned, using regex OR condition to match multiple keywords
  if grep -qE 'COORDINATOR_DATA_DIRECTORY|MASTER_DATA_DIRECTORY|greenplum_path.sh|cluster_env.sh|synxdb_path.sh' /home/${ADMIN_USER}/.bashrc; then
    echo "Found environment variable settings to clean up, removing them..."
    # Use extended regex to match all target patterns and delete lines (macOS compatible syntax)
    sed -i -E '/COORDINATOR_DATA_DIRECTORY|MASTER_DATA_DIRECTORY|greenplum_path.sh|cluster_env.sh|synxdb_path.sh/d' /home/${ADMIN_USER}/.bashrc
  fi
fi

#Step 5: Create folders needed for the cluster
log_time "Step 5: Create folders needed..."
rm -rf ${DATA_DIRECTORY}
echo "mkdir -p ${DATA_DIRECTORY}"
mkdir -p ${DATA_DIRECTORY}
chown -R ${ADMIN_USER}:${ADMIN_USER} ${DATA_DIRECTORY}

if [ "${WITH_MIRROR}" = "true" ]; then
  rm -rf ${MIRROR_DATA_DIRECTORY}
  echo " mkdir -p ${MIRROR_DATA_DIRECTORY}"
  mkdir -p ${MIRROR_DATA_DIRECTORY}
  chown -R ${ADMIN_USER}:${ADMIN_USER} ${MIRROR_DATA_DIRECTORY}
fi

#Step 6: Setup user access keys and configure host names
log_time "Step 6: Setup user access keys and configure host names."

rm -f /home/${ADMIN_USER}/.ssh/id_rsa.pub
rm -f /home/${ADMIN_USER}/.ssh/id_rsa
rm -f /home/${ADMIN_USER}/.ssh/authorized_keys
rm -f /home/${ADMIN_USER}/.ssh/known_hosts

su ${ADMIN_USER} -l -c "ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ''"
su ${ADMIN_USER} -l -c "cat /home/${ADMIN_USER}/.ssh/id_rsa.pub > /home/${ADMIN_USER}/.ssh/authorized_keys"

sed -i '/#Hashdata hosts begin/,/#Hashdata hosts end/d' /etc/hosts
cat ${working_dir}/hostsfile >> /etc/hosts
change_hostname ${SEGMENT_HOSTNAME}

log_time "Finished env init setting on segment node ${SEGMENT_HOSTNAME}."

# Check if the INIT_ENV_ONLY environment variable is set
if [ "${INIT_ENV_ONLY}" != "true" ]; then
  #Step 7: Installing database software
  log_time "Step 7: Installing database software."
  
  filename=$(basename "$CLOUDBERRY_RPM")

  keyword=$DB_KEYWORD
  soft_link=$CLOUDBERRY_BINARY_PATH
  
  # Check if the software already installed before
  if [ "${keyword}" != "unknown" ]; then
    if find /usr/local -maxdepth 1 -type d -name "*${keyword}*" -print -quit | grep -q .; then
      echo "Previous installation found, will try to remove and reinstall."
      # Check if the soft link exists
      if [ -L "$soft_link" ]; then
        # Remove the soft link
        rm -f "$soft_link"
        echo "Soft link $soft_link has been removed."
      else
        echo "Soft link $soft_link does not exist."
      fi
      echo "Operation completed!"
      # Try RPM installation first
      if ! rpm -ivh "${working_dir}/${filename}" --force; then
        echo "RPM installation failed, trying yum install..."
        yum install -y "${working_dir}/${filename}"
      fi
    else
      echo "No previous installation found, will try to install with YUM."
      yum install -y "${working_dir}/${filename}"
    fi
    # Change directory ownership
    chown -R ${ADMIN_USER}:${ADMIN_USER} /usr/local/${keyword}*
    chown -R ${ADMIN_USER}:${ADMIN_USER} ${soft_link}*
    echo "The directory /usr/local/${keyword}* has been changed to ${ADMIN_USER}:${ADMIN_USER}."
    echo "The directory ${soft_link}* has been changed to ${ADMIN_USER}:${ADMIN_USER}."
  else
    echo "Unknown database software version, will try to install with YUM."
    yum install -y ${working_dir}/${filename}
  fi
  log_time "Finished database software installation on segment node ${SEGMENT_HOSTNAME}."
else
  log_time "Step 7: INI_ENV_ONLY mode, skip database software installation."
fi
