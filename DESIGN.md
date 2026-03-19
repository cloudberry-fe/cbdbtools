# CBDBTools 产品设计文档

> 版本: v1.0 | 日期: 2026-03-18 | 状态: Draft

---

## 1. 产品概述

### 1.1 产品定位

CBDBTools 是一套面向 MPP 数据库集群的**自动化部署工具**，支持通过命令行(CLI)或 Web UI 两种方式，在 CentOS/RHEL 7-9 上一键完成数据库集群的环境初始化和集群创建。

### 1.2 目标用户

- 数据库管理员(DBA)
- 运维工程师
- 需要快速搭建测试/开发环境的开发人员

### 1.3 支持的数据库

| 数据库 | 版本 | 安装路径 |
|--------|------|----------|
| Cloudberry DB | 1.x, 2.x | `/usr/local/cloudberry-db` |
| Greenplum | 5.x, 6.x, 7.x | `/usr/local/greenplum-db` |
| HashData Lightning | 1.x, 2.x | `/usr/local/hashdata-lightning` 或 `/usr/local/cloudberry-db` |
| SynxDB | 1.x, 2.x, 4.x | `/usr/local/synxdb` 或 `/usr/local/synxdb4` |

### 1.4 支持的操作系统

- CentOS/RHEL 7, 8, 9
- Oracle Linux 8 (部分支持)

---

## 2. 系统架构

### 2.1 整体架构图

```
                    +-----------------------+
                    |       用户入口         |
                    +-----------+-----------+
                                |
                    +-----------+-----------+
                    |                       |
              +-----+-----+         +------+------+
              |   CLI 模式  |         |  Web UI 模式 |
              |  (run.sh)  |         | (Flask App) |
              +-----+-----+         +------+------+
                    |                       |
                    |                  SSH/SFTP (paramiko)
                    |                       |
                    +----------+------------+
                               |
                    +----------+----------+
                    |   deploycluster.sh   |  <-- 核心编排层
                    +----------+----------+
                               |
              +----------------+----------------+
              |                                 |
    +---------+---------+            +----------+----------+
    |    init_env.sh     |            |   init_cluster.sh    |
    |  (环境初始化)       |            |  (集群初始化)         |
    +---------+---------+            +---------------------+
              |
              |  多节点场景
              |
    +---------+---------+
    | init_env_segment.sh|  <-- 通过 multissh/multiscp 并行执行
    +-------------------+
```

### 2.2 部署模式

| 模式 | 说明 | 适用场景 |
|------|------|----------|
| **单节点 (single)** | Coordinator + Segments 在同一台机器 | 开发/测试环境 |
| **多节点 (multi)** | Coordinator + 多台 Segment 主机 | 生产/准生产环境 |

### 2.3 两种使用入口

#### CLI 模式
- 直接在目标服务器上执行 `sh run.sh`
- 配置写在 `deploycluster_parameter.sh`
- 日志输出到 `deploy_cluster_YYYYMMDD_HHMMSS.log`
- 适合自动化脚本/CI 集成

#### Web UI 模式
- 在任意机器上启动 Flask 服务 (`sh start_web.sh`)
- 通过浏览器填写参数、上传 RPM、一键部署
- 通过 SSH 远程连接目标服务器执行部署
- 适合不方便登录服务器的场景

---

## 3. 核心流程设计

### 3.1 CLI 部署流程

```
run.sh
 ├─ 1. 检查是否有正在运行的部署进程 (防重复)
 ├─ 2. 确定部署类型 (参数 > 配置文件)
 └─ 3. nohup 后台启动 deploycluster.sh
      │
      ├─ 4. 从 RPM 文件名自动检测数据库类型/版本/路径
      ├─ 5. 更新 deploycluster_parameter.sh (写入检测结果)
      ├─ 6. 调用 init_env.sh (环境初始化)
      │    ├─ 配置 YUM 源
      │    ├─ 关闭防火墙/SELinux
      │    ├─ 配置内核参数 (sysctl)
      │    ├─ 配置资源限制 (limits.conf)
      │    ├─ 配置 SSH 守护进程
      │    ├─ 配置 systemd-logind (RemoveIPC=no)
      │    ├─ 创建管理员用户 + SSH 密钥
      │    ├─ 安装数据库 RPM
      │    ├─ 创建数据目录
      │    └─ [多节点] 并行初始化所有 Segment 节点
      │         ├─ multiscp: 分发脚本和 RPM
      │         ├─ multissh: 并行执行 init_env_segment.sh
      │         └─ 收集/分发 SSH 密钥 (免密登录)
      │
      └─ 7. 调用 init_cluster.sh (集群初始化, 可选跳过)
           ├─ 生成 gpinitsystem 配置文件
           ├─ 生成机器列表文件
           ├─ 执行 gpinitsystem
           ├─ 设置数据库管理员密码
           ├─ 配置 pg_hba.conf (远程访问)
           ├─ 配置 .bashrc 环境变量
           └─ gpstop -u 重载配置
```

### 3.2 Web UI 部署流程

```
用户浏览器
 │
 ├─ Step 1: 连接配置 (/test_connection)
 │    └─ 输入远程主机 IP、端口、认证方式 → 测试 SSH 连通性
 │
 ├─ Step 2: 集群配置 (/save_config)
 │    └─ 填写集群参数 (数据库 RPM、部署类型、主机名等)
 │
 ├─ Step 3: 执行部署 (/deploy)
 │    ├─ SFTP 上传所有脚本到远程服务器
 │    ├─ 生成 deploycluster_parameter.sh
 │    ├─ 生成 segmenthosts.conf (多节点)
 │    ├─ 后台线程启动远程部署
 │    └─ SSE 实时推送日志到浏览器
 │
 └─ Step 4: 监控 (/stream_logs, /deployment_status)
      └─ 每 2 秒轮询远程日志文件，直到完成或超时 (1 小时)
```

---

## 4. 模块设计

### 4.1 文件清单与职责

| 文件 | 类型 | 职责 | 行数 |
|------|------|------|------|
| `run.sh` | Shell | CLI 入口，防重复执行，后台启动部署 | ~46 |
| `deploycluster.sh` | Shell | 核心编排：数据库类型检测 + 调度 init 脚本 | ~137 |
| `deploycluster_parameter.sh` | Shell | 中央配置文件，所有参数定义 | ~50 |
| `init_env.sh` | Shell | Coordinator 环境初始化 | ~233 |
| `init_env_segment.sh` | Shell | Segment 节点环境初始化 | ~60 |
| `init_cluster.sh` | Shell | gpinitsystem 集群初始化 | ~137 |
| `common.sh` | Shell | 共享函数库 (日志/系统配置/用户管理等) | ~443 |
| `multissh.sh` | Shell | 并行远程命令执行工具 | ~200 |
| `multiscp.sh` | Shell | 并行远程文件分发工具 | ~200 |
| `segmenthosts.conf` | Conf | 主机名 ↔ IP 映射配置 | ~10 |
| `cluster_deploy_web.py` | Python | Flask Web 应用 | ~894 |
| `start_web.sh` | Shell | Web 服务启动脚本 | ~59 |
| `wsgi.py` | Python | WSGI 入口 | ~6 |
| `templates/index.html` | HTML | 前端单页应用 | ~1700 |
| `test_web.py` | Python | Web 应用单元测试 | ~500 |
| `sshpass-1.10.tar.gz` | Binary | sshpass 源码包 (离线安装用) | - |

### 4.2 common.sh 函数库

| 函数 | 功能 |
|------|------|
| `log_time()` | 带时间戳的日志输出 |
| `change_hostname()` | 修改主机名 (跨 OS 兼容) |
| `disable_firewall()` | 关闭 firewalld + SELinux |
| `configure_yum_repo()` | 配置 YUM 源 (华为镜像) |
| `configure_sysctl()` | 内核参数调优 |
| `configure_limits()` | 资源限制配置 |
| `configure_sshd()` | SSH 守护进程优化 |
| `configure_logind()` | systemd-logind 配置 |
| `configure_timezone()` | 时区设置 |
| `install_dependencies()` | 安装依赖包 |
| `install_sshpass()` | 安装 sshpass (yum 或编译) |
| `create_admin_user()` | 创建数据库管理员用户 |
| `install_db_software()` | 安装数据库 RPM |
| `create_data_directories()` | 创建数据目录 |

### 4.3 Web UI 路由设计

| 路由 | 方法 | 功能 | 返回 |
|------|------|------|------|
| `/` | GET | 主页面 | HTML |
| `/test_connection` | POST | 测试 SSH 连接 | JSON |
| `/validate_rpm_path` | POST | 验证远程 RPM 路径 | JSON |
| `/save_config` | POST | 保存配置到 Session | JSON |
| `/upload_files` | POST | SFTP 上传文件 | JSON |
| `/deploy` | POST | 启动部署 | JSON |
| `/deployment_status` | GET | 查询部署状态 | JSON |
| `/deployment_logs` | GET | 获取完整日志 | JSON |
| `/stream_logs` | GET | SSE 实时日志流 | EventStream |
| `/reset` | POST | 重置部署状态 | JSON |

### 4.4 数据库类型自动检测

`deploycluster.sh` 通过 RPM 文件名模式匹配自动识别数据库类型：

| RPM 文件名匹配 | DB_TYPE | BINARY_PATH | LEGACY |
|----------------|---------|-------------|--------|
| `*cloudberry*` | Cloudberry | `/usr/local/cloudberry-db` | false |
| `*greenplum*` v5-6 | Greenplum | `/usr/local/greenplum-db` | true |
| `*greenplum*` v7+ | Greenplum | `/usr/local/greenplum-db` | false |
| `*hashdata-lightning-2*` | HashData | `/usr/local/hashdata-lightning` | false |
| `*hashdata-lightning-1*` | HashData | `/usr/local/cloudberry-db` | false |
| `*synxdb4*` | SynxDB | `/usr/local/synxdb4` | false |
| `*synxdb-2*` | SynxDB | `/usr/local/synxdb` | true |
| `*synxdb-1*` | SynxDB | `/usr/local/synxdb` | true |

> **LEGACY_VERSION** 影响 gpinitsystem 配置：`true` 时使用 `MASTER_HOSTNAME`，`false` 时使用 `COORDINATOR_HOSTNAME`。

---

## 5. 配置设计

### 5.1 必填参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `ADMIN_USER` | gpadmin | 数据库操作系统用户 |
| `ADMIN_USER_PASSWORD` | - | 用户密码 |
| `CLOUDBERRY_RPM` | - | RPM 文件绝对路径 |
| `COORDINATOR_HOSTNAME` | - | Coordinator 主机名 |
| `COORDINATOR_IP` | - | Coordinator IP 地址 |
| `DEPLOY_TYPE` | single | 部署模式 (single/multi) |

### 5.2 可选参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `INIT_ENV_ONLY` | false | 仅初始化环境，跳过集群创建 |
| `INSTALL_DB_SOFTWARE` | true | 是否安装 RPM (重新初始化时设为 false) |
| `WITH_MIRROR` | false | 启用 Mirror Segment |
| `WITH_STANDBY` | false | 启用 Standby Coordinator |
| `MAUNAL_YUM_REPO` | false | 跳过 YUM 源自动配置 |
| `TIMEZONE` | Asia/Shanghai | 目标时区 |
| `CLOUDBERRY_RPM_URL` | - | RPM 下载 URL (文件不存在时使用) |

### 5.3 集群参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `COORDINATOR_PORT` | 5432 | 数据库端口 |
| `COORDINATOR_DIRECTORY` | /data0/coordinator/gpseg-1 | Coordinator 数据目录 |
| `ARRAY_NAME` | gp | 集群名称 |
| `SEG_PREFIX` | gpseg | Segment 前缀 |
| `PORT_BASE` | 6000 | Segment 起始端口 |
| `DATA_DIRECTORY` | /data0/primary /data0/primary | 数据目录列表 (空格分隔) |

### 5.4 多节点访问参数

| 参数 | 说明 |
|------|------|
| `SEGMENT_ACCESS_METHOD` | 认证方式: `keyfile` 或 `password` |
| `SEGMENT_ACCESS_USER` | 远程登录用户名 |
| `SEGMENT_ACCESS_KEYFILE` | 私钥文件路径 |
| `SEGMENT_ACCESS_PASSWORD` | 密码 |

### 5.5 配置优先级 (Web UI)

```
内置默认值 < 已有 deploycluster_parameter.sh < Web UI 表单输入
```

---

## 6. 安全设计

### 6.1 输入验证

| 验证项 | 方法 |
|--------|------|
| IP 地址 | 格式校验 + 每段 0-255 范围检查 |
| 主机名 | 字母数字和连字符，不以连字符开头结尾 |
| 端口 | 1-65535 范围 |
| 文件路径 | 阻止 `..` 路径穿越和 null 字节 |
| 部署类型 | 白名单: 仅 `single` 或 `multi` |
| 命令注入 | `shlex.quote()` 转义用户输入 |

### 6.2 认证与凭据

- SSH 支持密码和密钥两种认证方式
- 密钥文件保存到 `/tmp`，权限 `0o600`
- 密码仅存储在 Flask Session 中，不写入日志
- 部署完成后集群内使用 SSH 密钥免密访问

### 6.3 系统安全变更

> **注意**: 以下变更是 MPP 数据库运行的必要条件，但会降低系统安全级别。

| 变更 | 原因 |
|------|------|
| 关闭 SELinux | 数据库进程需要自由访问共享内存和文件 |
| 关闭防火墙 | 集群节点间需要大量端口通信 |
| 管理员用户 sudo 免密 | 部署过程需要频繁切换权限 |
| pg_hba.conf 信任所有 IP | 允许远程客户端连接 (生产环境应收紧) |

### 6.4 文件上传

- 使用 `secure_filename()` 处理文件名
- 最大上传大小: 2GB
- 文件保存到 `/tmp` 临时目录

---

## 7. Web UI 前端设计

### 7.1 页面结构

单页应用 (SPA)，三个选项卡分步引导:

```
┌─────────────────────────────────────────────────┐
│  CBDBTools - MPP 数据库集群部署工具               │
├──────────┬──────────┬──────────────────────────-─┤
│ 连接配置  │ 集群配置  │ 执行部署                    │
├──────────┴──────────┴──────────────────────────-─┤
│                                                   │
│  Tab 1: 远程服务器连接                             │
│  - 主机 IP / 端口                                  │
│  - 认证方式 (密码 / 密钥)                           │
│  - 测试连接按钮                                    │
│                                                   │
│  Tab 2: 集群参数配置                               │
│  - 部署类型 (单节点 / 多节点)                       │
│  - RPM 路径 / 管理员用户 / 密码                     │
│  - Coordinator 主机名 / IP                         │
│  - Segment 主机列表 (多节点)                        │
│  - 高级选项 (Mirror / Standby / 端口等)             │
│                                                   │
│  Tab 3: 部署执行与监控                             │
│  - 开始部署按钮                                    │
│  - 实时日志输出 (SSE)                              │
│  - 部署状态指示                                    │
│                                                   │
└───────────────────────────────────────────────────┘
```

### 7.2 技术栈

- **CSS**: Tailwind 风格内联样式，暗色主题，渐变背景
- **JavaScript**: 原生 JS，无框架依赖
- **实时通信**: Server-Sent Events (EventSource API)
- **布局**: 响应式设计

---

## 8. 并行执行设计

### 8.1 multissh.sh

- 并行在多台主机上执行命令
- 默认并发数: 5
- 支持密码/密钥认证
- 锁机制防止输出交错
- 彩色输出 (红色错误/绿色成功/黄色警告)

### 8.2 multiscp.sh

- 并行向多台主机分发文件
- 与 multissh.sh 相同的认证和并发控制
- 保持文件权限

### 8.3 多节点部署并行策略

```
Coordinator (串行)
 ├─ 环境初始化
 ├─ 安装数据库
 └─ 分发文件到所有 Segment
      │
      ├─ Segment 1 ─┐
      ├─ Segment 2 ─┤  并行执行 init_env_segment.sh
      ├─ Segment 3 ─┤
      └─ Segment N ─┘
      │
      └─ 收集/分发 SSH 密钥 (串行)
```

---

## 9. 错误处理与日志

### 9.1 日志策略

| 场景 | 日志方式 |
|------|----------|
| CLI 部署 | `deploy_cluster_YYYYMMDD_HHMMSS.log` 文件 |
| Web UI | SSE 实时推送 + 远程日志文件轮询 |
| 所有脚本 | `log_time()` 带时间戳输出 |

### 9.2 错误处理

| 机制 | 说明 |
|------|------|
| `set -o pipefail` | 管道中任何命令失败即终止 |
| 进程防重复 | run.sh 检查已有部署进程 |
| gpinitsystem 容错 | 退出码 1 视为警告，继续执行 |
| SSH 连接失败 | 捕获并记录，返回错误信息 |
| 部署超时 | Web UI 最长监控 1 小时 |
| 线程安全 | `threading.RLock` 保护全局状态 |

---

## 10. 辅助工具

### 10.1 mirrorlessfailover.sh

- 无 Mirror 场景下的故障转移工具
- 将 Segment 从一个节点迁移到另一个节点

### 10.2 Minikube 支持

- `init_minikube_env.sh` / `init_minikube_cluster.sh`
- 在 Minikube (Kubernetes) 环境中部署数据库集群

---

## 11. 测试设计

### 11.1 测试覆盖

`test_web.py` 使用 pytest，覆盖以下模块:

| 测试类别 | 覆盖内容 |
|----------|----------|
| **输入验证** | IP / 主机名 / 端口 / 路径 的正确和边界情况 |
| **配置解析** | deploycluster_parameter.sh 和 segmenthosts.conf 的解析 |
| **配置生成** | 参数文件生成、log_time 函数位置、特殊字符转义 |
| **主机文件生成** | Coordinator + Segment 条目格式 |
| **路由测试** | 各 API 端点的参数验证和安全检查 |

### 11.2 测试不足

- 无 Shell 脚本单元测试
- 无端到端集成测试
- 无 multissh/multiscp 测试
- Web UI 前端无自动化测试

---

## 12. 已知限制与改进建议

### 12.1 当前限制

| 编号 | 限制 | 影响 |
|------|------|------|
| L1 | pg_hba.conf 信任所有 IP | 安全风险，生产环境需手动收紧 |
| L2 | YUM 源默认使用华为镜像 | 非中国区用户需设 `MAUNAL_YUM_REPO=true` |
| L3 | 部署超时硬编码 1 小时 | 大规模集群可能不够 |
| L4 | 单一 Flask Session 存储配置 | 不支持多用户并发部署 |
| L5 | 全局 `DEPLOYMENT_STATUS` 字典 | 同一时间只能运行一个部署 |
| L6 | deploycluster.sh 修改自身参数文件 | 副作用不明显，可能导致配置混乱 |
| L7 | sshpass 源码包内嵌仓库 | 版本更新不方便 |

### 12.2 改进建议

| 优先级 | 建议 | 说明 |
|--------|------|------|
| P0 | pg_hba.conf 安全加固 | 提供配置项控制访问范围，而非默认 trust all |
| P1 | 多用户并发支持 | 使用数据库或文件存储替代 Session/全局变量 |
| P1 | Shell 脚本测试 | 使用 bats 框架为 common.sh 添加单元测试 |
| P2 | 配置文件独立 | deploycluster.sh 不应运行时修改参数文件 |
| P2 | 部署进度条 | 解析日志关键步骤，提供百分比进度 |
| P2 | 部署回滚能力 | 失败时自动清理已执行的步骤 |
| P3 | 容器化部署支持 | 扩展 Minikube 支持为完整的 K8s 方案 |
| P3 | 国际化 | Web UI 支持中英文切换 |

---

## 13. 部署拓扑示例

### 单节点

```
┌─────────────────────────┐
│     单节点服务器          │
│                         │
│  Coordinator (port 5432)│
│  Segment 1  (port 6000) │
│  Segment 2  (port 6001) │
│  ...                    │
└─────────────────────────┘
```

### 多节点

```
┌─────────────────────────┐     ┌──────────────────────┐
│   Coordinator (mdw)     │     │   Web UI 服务器       │
│   port 5432             │◄────│   port 5000          │
│   可选: Standby         │     │   (可选，远程部署用)   │
└───────────┬─────────────┘     └──────────────────────┘
            │ SSH 免密
    ┌───────┼───────┐
    │       │       │
┌───▼──┐ ┌─▼────┐ ┌▼─────┐
│ sdw1 │ │ sdw2 │ │ sdw3 │  Segment 主机
│ Seg  │ │ Seg  │ │ Seg  │
│ [Mirror]│[Mirror]│[Mirror]│
└──────┘ └──────┘ └──────┘
```

---

## 附录 A: 文件依赖关系

```
run.sh
├── deploycluster_parameter.sh (source)
└── deploycluster.sh
    ├── deploycluster_parameter.sh (source + write)
    ├── init_env.sh
    │   ├── common.sh (source)
    │   ├── deploycluster_parameter.sh (source)
    │   ├── segmenthosts.conf (read)
    │   ├── multissh.sh (exec, multi-node)
    │   └── multiscp.sh (exec, multi-node)
    └── init_cluster.sh
        ├── deploycluster_parameter.sh (source)
        └── segmenthosts.conf (read, multi-node)

cluster_deploy_web.py
├── templates/index.html (render)
├── wsgi.py (WSGI entry)
└── Remote: all shell scripts (SFTP upload)
```

## 附录 B: 关键运行时文件

| 路径 | 用途 | 生命周期 |
|------|------|----------|
| `/tmp/gpinitsystem_config` | gpinitsystem 配置文件 | 部署期间 |
| `/tmp/hostfile_gpinitsystem` | 集群机器列表 | 部署期间 |
| `/tmp/hostsfile` | /etc/hosts 追加内容 | 部署期间 |
| `/tmp/{user}/` | 多节点文件分发暂存 | 部署期间 |
| `~/deploy_cluster_*.log` | 部署日志 | 永久保留 |
