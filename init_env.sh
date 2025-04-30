#!/bin/bash

VARS_FILE="deploycluster_parameter.sh"

source ./${VARS_FILE}

working_dir="/tmp/${SEGMENT_ACCESS_USER}"

if [ "${1}" == "single" ] || [ "${1}" == "multi" ]; then  
  cluster_type="${1}"  
else  
  cluster_type="${DEPLOY_TYPE}"
fi  

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

function config_hostsfile()
{
  log_time "set /etc/hosts on coordinator..."
  awk '/#Hashdata hosts begin/,/#Hashdata hosts end/' segmenthosts.conf > ${working_dir}/hostsfile
  sed -i '/#Hashdata hosts begin/,/#Hashdata hosts end/d' /etc/hosts
  cat ${working_dir}/hostsfile >> /etc/hosts
}

function copyfile_segment()
{ 
  log_time "copy init_env_segment.sh id_rsa.pub Cloudberry rpms to segment hosts"
  HOSTS_FILE="${working_dir}/segment_hosts.txt"
  if [ "${SEGMENT_ACCESS_METHOD}" = "keyfile" ]; then
    sudo sh multissh -v -k ${SEGMENT_ACCESS_KEYFILE} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} "rm -rf ${working_dir};mkdir -p ${working_dir}"
    ehco "sudo sh multiscp.sh -v -k ${SEGMENT_ACCESS_KEYFILE} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} init_env_segment.sh ${working_dir}"
    echo "sudo sh multiscp.sh -v -k ${SEGMENT_ACCESS_KEYFILE} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} deploycluster_parameter.sh ${working_dir}"
    echo "sudo sh multiscp.sh -v -k ${SEGMENT_ACCESS_KEYFILE} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} ${working_dir}/hostsfile ${working_dir}"
    echo "sudo sh multiscp.sh -v -k ${SEGMENT_ACCESS_KEYFILE} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} /home/${ADMIN_USER}/.ssh/id_rsa.pub ${working_dir}"
    echo "sudo sh multiscp.sh -v -k ${SEGMENT_ACCESS_KEYFILE} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} ${CLOUDBERRY_RPM} ${working_dir}"
    sudo sh multiscp.sh -v ENT_ACCESS_KEYFILE} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} init_env_segment.sh ${working_dir}
    sudo sh multiscp.sh -v ENT_ACCESS_KEYFILE} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} deploycluster_parameter.sh ${working_dir}
    sudo sh multiscp.sh -v ENT_ACCESS_KEYFILE} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} ${working_dir}/hostsfile ${working_dir}
    sudo sh multiscp.sh -v ENT_ACCESS_KEYFILE} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} /home/${ADMIN_USER}/.ssh/id_rsa.pub ${working_dir}
    sudo sh multiscp.sh -v ENT_ACCESS_KEYFILE} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} ${CLOUDBERRY_RPM} ${working_dir}
  else
    echo "sudo sh multiscp.sh -v -p ${SEGMENT_ACCESS_PASSWORD} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} init_env_segment.sh ${working_dir}"
    echo "sudo sh multiscp.sh -v -p ${SEGMENT_ACCESS_PASSWORD} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} deploycluster_parameter.sh ${working_dir}"
    echo "sudo sh multiscp.sh -v -p ${SEGMENT_ACCESS_PASSWORD} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} ${working_dir}/hostsfile ${working_dir}"
    echo "sudo sh multiscp.sh -v -p ${SEGMENT_ACCESS_PASSWORD} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} /home/${ADMIN_USER}/.ssh/id_rsa.pub ${working_dir}"
    echo "sudo sh multiscp.sh -v -p ${SEGMENT_ACCESS_PASSWORD} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} ${CLOUDBERRY_RPM} ${working_dir}"
    sudo sh multiscp.sh -v -p ${SEGMENT_ACCESS_PASSWORD} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} init_env_segment.sh ${working_dir}
    sudo sh multiscp.sh -v -p ${SEGMENT_ACCESS_PASSWORD} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} deploycluster_parameter.sh ${working_dir}
    sudo sh multiscp.sh -v -p ${SEGMENT_ACCESS_PASSWORD} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} ${working_dir}/hostsfile ${working_dir}
    sudo sh multiscp.sh -v -p ${SEGMENT_ACCESS_PASSWORD} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} /home/${ADMIN_USER}/.ssh/id_rsa.pub ${working_dir}
    sudo sh multiscp.sh -v -p ${SEGMENT_ACCESS_PASSWORD} -f $HOSTS_FILE -u ${SEGMENT_ACCESS_USER} ${CLOUDBERRY_RPM} ${working_dir}
  fi
  log_time "Finished copy init_env_segment.sh id_rsa.pub Cloudberry rpms to segment hosts"
}

function init_segment()
{
  log_time "Start init configuration on segment hosts"
  logfilename=$(date +%Y%m%d)_$(date +%H%M%S)

  if [ "${SEGMENT_ACCESS_METHOD}" = "keyfile" ]; then
    for i in $(cat ${working_dir}/segment_hosts.txt); do
      echo "ssh -n -q -i ${SEGMENT_ACCESS_KEYFILE} ${SEGMENT_ACCESS_USER}@${i} \"bash -c 'sudo sh ${working_dir}/init_env_segment.sh ${i} ${working_dir} &> ${working_dir}/init_env_segment_${i}_$logfilename.log'\""
      ssh -n -q -i ${SEGMENT_ACCESS_KEYFILE} ${SEGMENT_ACCESS_USER}@${i} "bash -c 'sudo sh ${working_dir}/init_env_segment.sh ${i} ${working_dir} &> ${working_dir}/init_env_segment_${i}_$logfilename.log'" &
    done
    wait
  else
    for i in $(cat ${working_dir}/segment_hosts.txt); do
      echo "sshpass -p ${SEGMENT_ACCESS_PASSWORD} ssh -n -q ${SEGMENT_ACCESS_USER}@${i} \"bash -c 'sudo sh ${working_dir}/init_env_segment.sh ${i} ${working_dir} &> ${working_dir}/init_env_segment_${i}_$logfilename.log'\""
      sshpass -p ${SEGMENT_ACCESS_PASSWORD} ssh -n -q ${SEGMENT_ACCESS_USER}@${i} "bash -c 'sudo sh ${working_dir}/init_env_segment.sh ${i} ${working_dir} &> ${working_dir}/init_env_segment_${i}_$logfilename.log'" &
    done
    wait
  fi
  log_time "Finished init configuration on segment hosts"
}



#Setup the env setting on Linux OS for Hashdata database

#Step 1: Installing Software Dependencies

log_time "Step 1: Installing Software Dependencies..."

# Check if the /etc/os-release file exists
if [ -f /etc/os-release ]; then
    # Source the /etc/os-release file to get the system information
    source /etc/os-release

    # Extract the first digit of the VERSION_ID
    first_digit=$(echo "$VERSION_ID" | cut -c1)

    # Execute different operations based on the first digit of the VERSION_ID
    case "$first_digit" in
        7)
            # Operation in 7
            echo "This is a operating system with version ID starting with 7."
            curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.huaweicloud.com/repository/conf/CentOS-7-anon.repo
            yum clean all
            yum makecache
            
            # You can add specific commands for Operation A here, for example, setting up the environment on the coordinator node
            # sh init_env.sh single
            ;;
        8)
            # Operation B
            echo "This is a operating system with version ID starting with 8. Executing Operation B."
            # You can add specific commands for Operation B here
            ;;
        9)
            # Operation C
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

cat /usr/share/zoneinfo/Asia/Macau > /usr/share/zoneinfo/Asia/Shanghai

yum install -y epel-release

log_time "Install necessary tools: wget and sshpass."
yum install -y wget sshpass

log_time "Install necessary dependencies."
yum install -y apr apr-util bash bzip2 curl iproute krb5-devel libcurl libevent libuuid libuv libxml2 libyaml libzstd openldap openssh openssh-clients openssh-server openssl openssl-libs perl python3 python3-psycopg2 python3-psutil python3-pyyaml python3-setuptools python3-devel python39 readline rsync sed tar which zip zlib git passwd wget net-tools

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

#Step 4: Create database admin user
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
    echo "存在 COORDINATOR_DATA_DIRECTORY 设置，将其注释掉..."
    sed -i "/COORDINATOR_DATA_DIRECTORY/s/^/#/" /home/${ADMIN_USER}/.bashrc
  fi
  if grep -q "greenplum_path.sh" /home/${ADMIN_USER}/.bashrc; then
    echo "存在 greenplum_path.sh 设置，将其注释掉..."
    sed -i "/greenplum_path.sh/s/^/#/" /home/${ADMIN_USER}/.bashrc
  fi
fi

#Step 5: Create folders needed for the cluster
log_time "Step 5: Create folders needed..."
rm -rf ${COORDINATOR_DIRECTORY} ${DATA_DIRECTORY}
mkdir -p ${COORDINATOR_DIRECTORY} ${DATA_DIRECTORY}
chown -R ${ADMIN_USER}:${ADMIN_USER} ${COORDINATOR_DIRECTORY} ${DATA_DIRECTORY}

if [ "${WITH_MIRROR}" = "true" ]; then
  rm -rf ${MIRROR_DATA_DIRECTORY}
  mkdir -p ${MIRROR_DATA_DIRECTORY}
  chown -R ${ADMIN_USER}:${ADMIN_USER} ${MIRROR_DATA_DIRECTORY}
fi

# 检查 INIT_ENV_ONLY 环境变量
if [ "${INIT_ENV_ONLY}" != "true" ]; then

  #Step 6: Installing database software
  log_time "Step 5: Installing database software..."
  
  rpmfile=$(ls ${CLOUDBERRY_RPM} 2>/dev/null)
    
  if [ -z "$rpmfile" ]; then  
    wget ${CLOUDBERRY_RPM_URL} -O ${CLOUDBERRY_RPM}
  fi
  
  # 清理之前安装包检查变量中是否包含"greenplum"字样  
  
  # 确保CLOUDBERRY_RPM变量已设置
  if [ -z "${CLOUDBERRY_RPM}" ]; then
      echo "错误：环境变量CLOUDBERRY_RPM未设置。"
      exit 1
  fi
  
  # 判断RPM包名称是否包含greenplum或cloudberry或hashdata
  if [[ "${CLOUDBERRY_RPM}" =~ greenplum ]]; then
      keyword="greenplum"
      soft_link="/usr/local/greenplum-db"
  elif [[ "${CLOUDBERRY_RPM}" =~ cloudberry ]]; then
      keyword="cloudberry"
      soft_link="/usr/local/cloudberry-db"
  elif [[ "${CLOUDBERRY_RPM}" =~ hashdata ]]; then
      keyword="hashdata"
      soft_link="/usr/local/hashdata-lightning"
  else
      keyword="none"
      soft_link="none"
  fi

  log_time "Currently deploy ${keyword} database."
  
  # 根据关键字处理安装和权限
  if [ "${keyword}" != "none" ]; then
      # 检查/usr/local下是否存在包含关键字的目录
    if find /usr/local -maxdepth 1 -type d -name "*${keyword}*" -print -quit | grep -q .; then
          echo "检测到${keyword}目录，强制安装RPM并修改权限..."
          # 检查软链接是否存在
          if [ -L "$soft_link" ]; then
          # 删除软链接
            rm -f "$soft_link"
            echo "软链接 $soft_link 已删除"
          else
            echo "软链接 $soft_link 不存在"
          fi
          echo "操作完成！"
          rpm -ivh ${CLOUDBERRY_RPM} --force
      else
          echo "未找到${keyword}目录，使用YUM安装..."
          yum install -y "${CLOUDBERRY_RPM}"
      fi
    # 修改目录权限  
    chown -R ${ADMIN_USER}:${ADMIN_USER} /usr/local/${keyword}*
    echo "已将 $dir 的所有者修改为 ${ADMIN_USER}:${ADMIN_USER}"
  else
      echo "未检测到相关产品关键字，尝试使用YUM安装，可能需要手工配置权限等..."
      yum install -y ${CLOUDBERRY_RPM}
  fi
fi

#Step 7: Setup user no-password access
log_time "Step 6: Setup user no-password access..."
change_hostname ${COORDINATOR_HOSTNAME}
rm -rf /home/${ADMIN_USER}/.ssh/
su ${ADMIN_USER} -l -c "ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ''"
su ${ADMIN_USER} -l -c "cat /home/${ADMIN_USER}/.ssh/id_rsa.pub | sshpass -p "${ADMIN_USER_PASSWORD}" ssh -o StrictHostKeyChecking=no ${ADMIN_USER}@${COORDINATOR_HOSTNAME} "cat >> /home/${ADMIN_USER}/.ssh/authorized_keys""
#su ${ADMIN_USER} -l -c "cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys"
#su ${ADMIN_USER} -l -c "ssh-keyscan ${COORDINATOR_HOSTNAME} >> ~/.ssh/known_hosts"
su ${ADMIN_USER} -l -c "chmod 600 ~/.ssh/authorized_keys"
su ${ADMIN_USER} -l -c "chmod 644 /home/${ADMIN_USER}/.ssh/known_hosts"
#echo "su ${ADMIN_USER} -l -c \"ssh ${COORDINATOR_HOSTNAME} 'date;exit'"\"
#su ${ADMIN_USER} -l -c "ssh ${COORDINATOR_HOSTNAME} 'date;exit'"


log_time "Finished env init setting on coordinator..."

#Step 8: Setup env on segments if needed

#set -e

if [ "$cluster_type" = "multi" ]; then
  log_time "Step 8: Setup env on segment nodes..."
  rm -rf ${working_dir}/segment_hosts.txt
  sed -n '/##Segment hosts/,/#Hashdata hosts end/p' segmenthosts.conf|sed '1d;$d'|awk '{print $2}' >> ${working_dir}/segment_hosts.txt
  
  config_hostsfile

  for i in $(cat ${working_dir}/segment_hosts.txt); do
    ssh-keyscan ${i} >> ~/.ssh/known_hosts
  done

  copyfile_segment
  init_segment

  #if [ "${SEGMENT_ACCESS_METHOD}" = "keyfile" ]; then
  #  copyfile_segment_keyfile
  #  init_segment_keyfile
  #else
  #  copyfile_segment_password
  #  init_segment_password
  #fi

  #Step 9: Setup no-password access for all nodes...
  log_time "Step 9: Setup no-password access for all nodes..."

  for i in $(cat ${working_dir}/segment_hosts.txt); do
    #echo "su ${ADMIN_USER} -l -c \"ssh ${i} 'date;exit'"\"
    su ${ADMIN_USER} -l -c "ssh-keyscan ${i} >> ~/.ssh/known_hosts"
    #su ${ADMIN_USER} -l -c "ssh ${i} 'date;exit'"
  done
  
  export COORDINATOR_HOSTNAME=$(sed -n '/##Coordinator hosts/,/##Segment hosts/p' segmenthosts.conf|sed '1d;$d'|awk '{print $2}')
  echo ${COORDINATOR_HOSTNAME} >> ${working_dir}/segment_hosts.txt
  change_hostname ${COORDINATOR_HOSTNAME}


  
  mkdir -p ${working_dir}/ssh_keys

  # 使用 sshpass 收集所有节点的公钥
  for node in $(cat ${working_dir}/segment_hosts.txt); do
    sshpass -p "${ADMIN_USER_PASSWORD}" scp -o StrictHostKeyChecking=no ${ADMIN_USER}@${node}:/home/${ADMIN_USER}/.ssh/id_rsa.pub ${working_dir}/ssh_keys/${node}.pub
  done
  
  # 分发公钥到所有节点
  for target in $(cat ${working_dir}/segment_hosts.txt); do
    # 清空目标节点的 authorized_keys 文件
    sshpass -p "${ADMIN_USER_PASSWORD}" ssh -o StrictHostKeyChecking=no ${ADMIN_USER}@${target} "echo '' > /home/${ADMIN_USER}/.ssh/authorized_keys"
    
    # 将所有节点的公钥添加到目标节点的 authorized_keys 文件中
    for keyfile in ${working_dir}/ssh_keys/*.pub; do
      cat ${keyfile} | sshpass -p "${ADMIN_USER_PASSWORD}" ssh -o StrictHostKeyChecking=no ${ADMIN_USER}@${target} "cat >> /home/${ADMIN_USER}/.ssh/authorized_keys"
    done
    
    # 复制 mdw 的 known_hosts 文件到目标节点
    cat /home/${ADMIN_USER}/.ssh/known_hosts | sshpass -p "${ADMIN_USER_PASSWORD}" ssh -o StrictHostKeyChecking=no ${ADMIN_USER}@${target} "cat > /home/${ADMIN_USER}/.ssh/known_hosts"

    # 设置正确的权限
    sshpass -p "${ADMIN_USER_PASSWORD}" ssh -o StrictHostKeyChecking=no ${ADMIN_USER}@${target} "chmod 700 /home/${ADMIN_USER}/.ssh && chmod 600 /home/${ADMIN_USER}/.ssh/authorized_keys && chmod 644 /home/${ADMIN_USER}/.ssh/known_hosts"
  done
fi

log_time "Finished env init setting on coordinator and segment nodes..."