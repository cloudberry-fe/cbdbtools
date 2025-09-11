#!/bin/bash

VARS_FILE="deploycluster_parameter.sh"

source ./${VARS_FILE}

## Turn off firewalls
log_time "Step 1: Turn off firewalls..."

systemctl stop firewalld.service
systemctl disable firewalld.service

sed s/^SELINUX=.*$/SELINUX=disabled/ -i /etc/selinux/config
setenforce 0

## Configure OS parameters
log_time "Step 2: Configure OS parameters..."

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

sysctl -p

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


## Install docker
dnf -y install dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker


## Install minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-latest.x86_64.rpm
rpm -Uvh minikube-latest.x86_64.rpm

## Install Kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

##Install helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

## Create minikube user and start minikube
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
useradd -m -G wheel minikube
echo "1qaz2wsx"|passwd --stdin minikube
usermod -aG docker minikube
newgrp docker