#!/bin/bash

VARS_FILE="deploycluster_parameter.sh"

source ./${VARS_FILE}

if [ "${1}" == "single" ] || [ "${1}" == "multi" ]; then  
  cluster_type="${1}"  
else  
  cluster_type="${DEPLOY_TYPE}"
fi  


function config_hostsfile()
{
  log_time "set /etc/hosts on coordinator..."
  awk '/#Hashdata hosts begin/,/#Hashdata hosts end/' segmenthosts.conf > /tmp/hostsfile
  sed -i '/#Hashdata hosts begin/,/#Hashdata hosts end/d' /etc/hosts
  cat /tmp/hostsfile >> /etc/hosts
}

function copyfile_segment_keyfile()
{ 
  log_time "copy init_env_segment.sh id_rsa.pub Cloudberry rpms to segment hosts"
  for i in $(cat /tmp/segment_hosts.txt); do
    (
      echo "Copying files to ${i}"
      echo "scp -i ${SEGMENT_ACCESS_KEYFILE} init_env_segment.sh ${SEGMENT_ACCESS_USER}@${i}:/tmp"
      echo "scp -i ${SEGMENT_ACCESS_KEYFILE} deploycluster_parameter.sh ${SEGMENT_ACCESS_USER}@${i}:/tmp"
      echo "scp -i ${SEGMENT_ACCESS_KEYFILE} /tmp/hostsfile ${SEGMENT_ACCESS_USER}@${i}:/tmp"
      echo "scp -i ${SEGMENT_ACCESS_KEYFILE} /home/${ADMIN_USER}/.ssh/id_rsa.pub ${SEGMENT_ACCESS_USER}@${i}:/tmp"
      echo "scp -i ${SEGMENT_ACCESS_KEYFILE} ${CLOUDBERRY_RPM} ${SEGMENT_ACCESS_USER}@${i}:${CLOUDBERRY_RPM}"
      scp -i ${SEGMENT_ACCESS_KEYFILE} init_env_segment.sh ${SEGMENT_ACCESS_USER}@${i}:/tmp
      scp -i ${SEGMENT_ACCESS_KEYFILE} deploycluster_parameter.sh ${SEGMENT_ACCESS_USER}@${i}:/tmp
      scp -i ${SEGMENT_ACCESS_KEYFILE} /tmp/hostsfile ${SEGMENT_ACCESS_USER}@${i}:/tmp
      scp -i ${SEGMENT_ACCESS_KEYFILE} /home/${ADMIN_USER}/.ssh/id_rsa.pub ${SEGMENT_ACCESS_USER}@${i}:/tmp
      scp -i ${SEGMENT_ACCESS_KEYFILE} ${CLOUDBERRY_RPM} ${SEGMENT_ACCESS_USER}@${i}:${CLOUDBERRY_RPM}
    ) &
  done
  wait
  log_time "Finished copy init_env_segment.sh id_rsa.pub Cloudberry rpms to segment hosts"
}


function copyfile_segment_password()
{ 
  log_time "copy init_env_segment.sh id_rsa.pub Cloudberry rpms to segment hosts"
  for i in $(cat /tmp/segment_hosts.txt); do
    (
      echo "Copying files to ${i}"
      echo "sshpass -p ${SEGMENT_ACCESS_PASSWORD} scp -o StrictHostKeyChecking=no init_env_segment.sh ${SEGMENT_ACCESS_USER}@${i}:/tmp"
      echo "sshpass -p ${SEGMENT_ACCESS_PASSWORD} scp -o StrictHostKeyChecking=no deploycluster_parameter.sh ${SEGMENT_ACCESS_USER}@${i}:/tmp"
      echo "sshpass -p ${SEGMENT_ACCESS_PASSWORD} scp -o StrictHostKeyChecking=no /tmp/hostsfile ${SEGMENT_ACCESS_USER}@${i}:/tmp"
      echo "sshpass -p ${SEGMENT_ACCESS_PASSWORD} scp -o StrictHostKeyChecking=no /home/${ADMIN_USER}/.ssh/id_rsa.pub ${SEGMENT_ACCESS_USER}@${i}:/tmp"
      echo "sshpass -p ${SEGMENT_ACCESS_PASSWORD} scp -o StrictHostKeyChecking=no ${CLOUDBERRY_RPM} ${SEGMENT_ACCESS_USER}@${i}:${CLOUDBERRY_RPM}"
      sshpass -p ${SEGMENT_ACCESS_PASSWORD} scp -o StrictHostKeyChecking=no init_env_segment.sh ${SEGMENT_ACCESS_USER}@${i}:/tmp
      sshpass -p ${SEGMENT_ACCESS_PASSWORD} scp -o StrictHostKeyChecking=no deploycluster_parameter.sh ${SEGMENT_ACCESS_USER}@${i}:/tmp
      sshpass -p ${SEGMENT_ACCESS_PASSWORD} scp -o StrictHostKeyChecking=no /tmp/hostsfile ${SEGMENT_ACCESS_USER}@${i}:/tmp
      sshpass -p ${SEGMENT_ACCESS_PASSWORD} scp -o StrictHostKeyChecking=no /home/${ADMIN_USER}/.ssh/id_rsa.pub ${SEGMENT_ACCESS_USER}@${i}:/tmp
      sshpass -p ${SEGMENT_ACCESS_PASSWORD} scp -o StrictHostKeyChecking=no ${CLOUDBERRY_RPM} ${SEGMENT_ACCESS_USER}@${i}:${CLOUDBERRY_RPM}
    ) &
  done
  wait
  log_time "Finished copy init_env_segment.sh id_rsa.pub Cloudberry rpms to segment hosts"
}

function init_segment_keyfile()
{
  log_time "Start init configuration on segment hosts"
  logfilename=$(date +%Y%m%d)_$(date +%H%M%S)
  for i in $(cat /tmp/segment_hosts.txt); do
    echo "ssh -n -q -i ${SEGMENT_ACCESS_KEYFILE} root@${i} \"bash -c 'sh /tmp/init_env_segment.sh &> /tmp/init_env_segment_${i}_$logfilename.log'\""
    ssh -n -q -i ${SEGMENT_ACCESS_KEYFILE} root@${i} "bash -c 'sh /tmp/init_env_segment.sh &> /tmp/init_env_segment_${i}_$logfilename.log'" &
  done
  wait
  log_time "Finished init configuration on segment hosts"
}

function init_segment_password()
{
  log_time "Start init configuration on segment hosts"
  logfilename=$(date +%Y%m%d)_$(date +%H%M%S)
  for i in $(cat /tmp/segment_hosts.txt); do
    echo "sshpass -p ${SEGMENT_ACCESS_PASSWORD} ssh -n -q root@${i} \"bash -c 'sh /tmp/init_env_segment.sh &> /tmp/init_env_segment_${i}_$logfilename.log'\""
    sshpass -p ${SEGMENT_ACCESS_PASSWORD} ssh -n -q root@${i} "bash -c 'sh /tmp/init_env_segment.sh &> /tmp/init_env_segment_${i}_$logfilename.log'" &
  done
  wait
  log_time "Finished init configuration on segment hosts"
}


#Setup the env setting on Linux OS for Hashdata database

#Step 1: Installing Software Dependencies

log_time "Step 1: Installing Software Dependencies..."

# curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.huaweicloud.com/repository/conf/CentOS-7-anon.repo
# yum clean all
# yum makecache

yum install -y epel-release

yum install -y apr apr-util bash bzip2 curl iproute krb5-devel libcgroup-tools libcurl libevent libuuid libuv libxml2 libyaml libzstd openldap openssh openssh-clients openssh-server openssl openssl-libs perl python3 python3-psycopg2 python3-psutil python3-pyyaml python3-setuptools python39 readline rsync sed tar which zip zlib git passwd wget

#Step 2: Turn off firewalls
log_time "Step 2: Turn off firewalls..."

systemctl stop firewalld.service
systemctl disable firewalld.service

sed s/^SELINUX=.*$/SELINUX=disabled/ -i /etc/selinux/config
setenforce 0


#Step 3: Configuring system parameters
log_time "Step 3: Configuring system parameters..."

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
ClientAliveCountMax 3" >> /etc/ssh/sshd_config

systemctl restart sshd

#Step 4: Create database user
log_time "Step 4: Create database user ${ADMIN_USER}..."

if ! id "$ADMIN_USER" &>/dev/null; then
  groupadd ${ADMIN_USER} 
  useradd ${ADMIN_USER} -r -m -g ${ADMIN_USER}
  usermod -aG wheel ${ADMIN_USER}
  echo "Hashdata@123"|passwd --stdin ${ADMIN_USER}
  echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers
  chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}
fi

#Step 5: Installing database software
log_time "Step 5: Installing database software..."

rpmfile=$(ls ${CLOUDBERRY_RPM} 2>/dev/null)
  
if [ -z "$rpmfile" ]; then  
  wget ${CLOUDBERRY_RPM_URL} -O ${CLOUDBERRY_RPM}
fi

# 清理之前安装包检查变量中是否包含"greenplum"字样  
if [[ "${CLOUDBERRY_RPM}" == *greenplum* ]]; then  
  yum erase -y greenplum-db*
  rm -rf /usr/local/greenplum-db*
else  
  yum erase -y cloudberry-db*
  rm -rf /usr/local/cloudberry-db*
fi

yum install -y ${CLOUDBERRY_RPM}

# 检查变量中是否包含"greenplum"字样  
if [[ "${CLOUDBERRY_RPM}" == *greenplum* ]]; then  
  chown -R ${ADMIN_USER}:${ADMIN_USER} /usr/local/greenplum*
else  
  chown -R ${ADMIN_USER}:${ADMIN_USER} /usr/local/cloudberry* 
fi

#Step 6: Setup user no-password access
log_time "Step 6: Setup user no-password access..."

rm -rf /home/${ADMIN_USER}/.ssh/
su ${ADMIN_USER} -l -c "ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ''"
su ${ADMIN_USER} -l -c "cat /home/${ADMIN_USER}/.ssh/id_rsa.pub > /home/${ADMIN_USER}/.ssh/authorized_keys"
su ${ADMIN_USER} -l -c "source ${CLOUDBERRY_BINARY_PATH}/greenplum_path.sh;gpssh-exkeys -h "$(hostname)""
su ${ADMIN_USER} -l -c "echo \"UserKnownHostsFile /home/${ADMIN_USER}/.ssh/known_hosts\" >> /home/${ADMIN_USER}/.ssh/config"


#Step7: Create folders needed for the cluster
log_time "Step7: Create folders needed..."
rm -rf ${COORDINATOR_DIRECTORY} ${DATA_DIRECTORY}
mkdir -p ${COORDINATOR_DIRECTORY} ${DATA_DIRECTORY}
chown -R ${ADMIN_USER}:${ADMIN_USER} ${COORDINATOR_DIRECTORY} ${DATA_DIRECTORY}

if [ "${WITH_MIRROR}" = "true" ]; then
  rm -rf ${MIRROR_DATA_DIRECTORY}
  mkdir -p ${MIRROR_DATA_DIRECTORY}
  chown -R ${ADMIN_USER}:${ADMIN_USER} ${MIRROR_DATA_DIRECTORY}
fi

log_time "Finished env init setting on coordinator..."

#Step 8: Setup env on segments if needed

#set -e

if [ "$cluster_type" = "multi" ]; then
  log_time "Step 8: Setup env on segment nodes..."
  rm -rf /tmp/segment_hosts.txt
  sed -n '/##Segment hosts/,/#Hashdata hosts end/p' segmenthosts.conf|sed '1d;$d'|awk '{print $2}' >> /tmp/segment_hosts.txt
  
  config_hostsfile

  for i in $(cat /tmp/segment_hosts.txt); do
    ssh-keyscan ${i} >> ~/.ssh/known_hosts
  done
  
  if [ "${SEGMENT_ACCESS_METHOD}" = "keyfile" ]; then
    copyfile_segment_keyfile
    init_segment_keyfile
  else
    copyfile_segment_password
    init_segment_password
  fi

  #Step 9: Setup no-password access for all nodes...
  log_time "Step 9: Setup no-password access for all nodes..."
  
  export COORDINATOR_HOSTNAME=$(sed -n '/##Coordinator hosts/,/##Segment hosts/p' segmenthosts.conf|sed '1d;$d'|awk '{print $2}')
  echo ${COORDINATOR_HOSTNAME} >> /tmp/segment_hosts.txt

  for i in $(cat /tmp/segment_hosts.txt); do
    echo "su ${ADMIN_USER} -l -c \"ssh ${i} 'date;exit'"\"
    su ${ADMIN_USER} -l -c "ssh-keyscan ${i} >> ~/.ssh/known_hosts"
    su ${ADMIN_USER} -l -c "ssh ${i} 'date;exit'"
  done
  
  echo "su ${ADMIN_USER} -l -c \"source ${CLOUDBERRY_BINARY_PATH}/greenplum_path.sh;gpssh-exkeys -f /tmp/segment_hosts.txt\""
  su ${ADMIN_USER} -l -c "source ${CLOUDBERRY_BINARY_PATH}/greenplum_path.sh;gpssh-exkeys -f /tmp/segment_hosts.txt"
fi
log_time "Finished env init setting on coordinator and segment nodes..."
