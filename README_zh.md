# CBDBTools

CBDBTools 是一套 MPP 数据库集群自动化部署工具，支持 Cloudberry、Greenplum、HashData Lightning 和 SynxDB。

提供两种部署方式：
1. **Web UI 部署** - 4 步向导式界面引导部署
2. **命令行部署** - 传统 Shell 脚本方式

两种方式都在 **Coordinator 节点**上运行，调用同一套底层部署脚本。

---

## 支持平台

### 操作系统

| 操作系统 | 版本 | 包格式 |
|----------|------|--------|
| CentOS / RHEL | 7, 8, 9 | RPM |
| Rocky Linux | 8, 9 | RPM |
| Oracle Linux | 8 | RPM |
| Ubuntu | 20.04, 22.04, 24.04 | DEB |

### 数据库

| 数据库 | 版本 | 安装路径 |
|--------|------|----------|
| Cloudberry DB | 1.x, 2.x | `/usr/local/cloudberry-db` |
| Greenplum | 5.x, 6.x, 7.x | `/usr/local/greenplum-db` |
| HashData Lightning | 1.x, 2.x | `/usr/local/hashdata-lightning` |
| SynxDB | 1.x, 2.x, 4.x | `/usr/local/synxdb` 或 `/usr/local/synxdb4` |

---

## 前置条件

1. **环境要求：**
   - 工具必须在 **Coordinator** 服务器上执行
   - 需要 `root` 用户权限（支持密码和密钥认证）
   - 磁盘建议使用 XFS 文件系统，挂载选项 `noatime,inode64`

2. **依赖（自动安装）：**
   - `sshpass`（通过包管理器或编译内置源码包）
   - `python3`, `pip`, `flask`, `gunicorn`（Web UI 需要）
   - `chrony` 或 `ntpd`（时间同步）

---

## 部署方式

### Web UI 部署

在 Coordinator 上启动 Web 服务：

```bash
bash start_web.sh
```

> **注意：** 请始终使用 `bash`（而非 `sh`）运行脚本。Ubuntu 上 `/bin/sh` 是 dash，不支持脚本中使用的 bash 特性。

然后在浏览器中打开 `http://<coordinator-ip>:5000`。

Web UI 采用 4 步向导模式：

1. **环境配置** - 选择操作系统（自动检测）、部署模式（单机/多机）、数据库安装包。支持从浏览器拖拽上传安装包
2. **集群配置** - 设置管理员用户、Coordinator 信息、Segment 主机（多机模式）、数据目录等。点击**保存配置**后继续
3. **确认部署** - 查看完整部署配置摘要，包含 Mirror/Standby 未启用等警告信息
4. **执行部署** - 实时日志流输出，带阶段进度指示器。成功后显示连接信息

界面支持中英文切换（右上角切换按钮）。

### 命令行部署

#### 1. 配置参数

编辑 `deploycluster_parameter.sh`：

```bash
## 必填参数
export ADMIN_USER="gpadmin"
export ADMIN_USER_PASSWORD="Cbdb@1234"
export CLOUDBERRY_RPM="/root/hashdata-lightning-2.4.0-1.x86_64.rpm"  # 或 .deb
export COORDINATOR_HOSTNAME="mdw"
export COORDINATOR_IP="192.168.1.100"
export DEPLOY_TYPE="single"   # 或 "multi"
```

| 参数 | 说明 |
|------|------|
| `ADMIN_USER` | 数据库操作系统用户（默认 gpadmin）|
| `ADMIN_USER_PASSWORD` | 操作系统用户和数据库管理员密码 |
| `CLOUDBERRY_RPM` | RPM 或 DEB 安装包的绝对路径，工具通过文件名自动检测数据库类型和版本 |
| `COORDINATOR_HOSTNAME` | Coordinator 主机名（工具会自动设置）|
| `COORDINATOR_IP` | Coordinator IP 地址 |
| `DEPLOY_TYPE` | `single`（单机）或 `multi`（多机）|

#### 多机部署额外参数：

```bash
export SEGMENT_ACCESS_METHOD="keyfile"    # 或 "password"
export SEGMENT_ACCESS_USER="root"
export SEGMENT_ACCESS_KEYFILE="/root/.ssh/id_rsa"
```

#### 2. 配置主机（仅多机模式）

编辑 `segmenthosts.conf`：

```
##Define hosts used for Hashdata
#Hashdata hosts begin
##Coordinator hosts
10.14.3.217 mdw
##Segment hosts
10.14.5.184 sdw1
10.14.5.177 sdw2
#Hashdata hosts end
```

#### 3. 启动部署

```bash
bash run.sh            # 使用配置文件中的 DEPLOY_TYPE
bash run.sh single     # 强制单机部署
bash run.sh multi      # 强制多机部署
```

---

## 系统调优

部署过程自动应用以下优化（遵循 Greenplum 7.7 最佳实践）：

| 类别 | 配置内容 |
|------|----------|
| **内核参数** | 共享内存、信号量、网络缓冲、IP 碎片 |
| **脏页内存** | ≤64GB 使用 ratio 模式，>64GB 使用 bytes 模式 |
| **透明大页 (THP)** | 运行时禁用 + 持久化（rc.local / systemd）|
| **时间同步** | 安装并启用 chrony |
| **安全限制** | nofile=524288, nproc=131072（含 limits.d 覆盖）|
| **SSH** | 优化 MaxStartups/MaxSessions/ClientAliveInterval |
| **systemd-logind** | RemoveIPC=no |
| **防火墙/SELinux** | 禁用 |

---

## 常见问题

| 问题 | 解决方案 |
|------|----------|
| SSH 连接 Segment 超时 | 检查网络连通性，确认 Segment 防火墙已关闭 |
| `set: Illegal option -o pipefail` | 使用 `bash` 而非 `sh` 运行脚本 |
| Ubuntu 上 `source: not found` | gpadmin 的 shell 必须是 `/bin/bash`，运行 `usermod -s /bin/bash gpadmin` |
| `gpinitsystem` FATAL 错误 | 检查 Segment 网络连通性，确认 segmenthosts.conf 配置 |
| Web UI "Save request failed" | 刷新浏览器（Ctrl+F5），确认 gunicorn 正在运行 |
| Web UI 部署时无日志显示 | 确认 gunicorn 使用 `--workers 1`（不能多 worker）|

**日志位置：**
- CLI 部署：项目目录下 `deploy_cluster_YYYYMMDD_HHMMSS.log`
- Web UI：通过 SSE 实时推送 + 同一日志文件
- gpinitsystem：`/home/gpadmin/gpAdminLogs/gpinitsystem_*.log`

---

## 支持

如有问题，请在本仓库提交 Issue。
