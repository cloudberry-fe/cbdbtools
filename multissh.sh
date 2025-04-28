#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 使用帮助
function show_help() {
    echo "用法: $0 [选项] <命令>"
    echo "通过 SSH 连接到多个服务器执行命令"
    echo ""
    echo "选项:"
    echo "  -h, --help            显示此帮助信息"
    echo "  -f, --hosts-file      指定包含服务器列表的文件 (默认为 segment_hosts.txt)"
    echo "  -u, --user            指定 SSH 用户名 (默认为当前用户)"
    echo "  -p, --password        指定 SSH 密码 (用于密码认证)"
    echo "  -k, --key-file        指定 SSH 私钥文件 (用于密钥认证)"
    echo "  -P, --port            指定 SSH 端口 (默认为 22)"
    echo "  -t, --timeout         指定 SSH 超时时间 (秒, 默认为 30)"
    echo "  -v, --verbose         启用详细输出"
    echo "  -o, --output          指定输出结果文件"
    echo "  -c, --concurrency     指定并发执行的最大数量 (默认为 5, 0表示不限制)"
    echo ""
    echo "服务器列表文件格式:"
    echo "  每行一个服务器，可以是 IP 地址或主机名"
    echo "  示例:"
    echo "    192.168.1.1"
    echo "    server2.example.com"
}

# 默认参数
HOSTS_FILE="segment_hosts.txt"
USER=$(whoami)
PASSWORD=""
KEY_FILE=""
PORT=22
TIMEOUT=30
VERBOSE=0
OUTPUT_FILE=""
CONCURRENCY=5

# 创建锁文件
LOCK_FILE="/tmp/multissh_lock.$$"
touch "$LOCK_FILE"

# 存储后台进程ID的数组
BACKGROUND_PIDS=()

# 清理函数
function cleanup() {
    rm -f "$LOCK_FILE"
    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
    # 遍历并杀死所有后台进程
    for pid in "${BACKGROUND_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
        fi
    done
}

# 注册清理函数
trap cleanup EXIT

# 输出锁定函数
function output_lock() {
    while ! ln "$LOCK_FILE" "$LOCK_FILE.lock" 2>/dev/null; do
        sleep 0.1
    done
}

# 输出解锁函数
function output_unlock() {
    rm -f "$LOCK_FILE.lock"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--hosts-file)
            HOSTS_FILE="$2"
            shift 2
            ;;
        -u|--user)
            USER="$2"
            shift 2
            ;;
        -p|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -k|--key-file)
            KEY_FILE="$2"
            shift 2
            ;;
        -P|--port)
            PORT="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift 1
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -c|--concurrency)
            CONCURRENCY="$2"
            shift 2
            ;;
        *)
            # 剩余参数作为要执行的命令
            COMMAND="$*"
            break
            ;;
    esac
done

# 检查是否提供了命令
if [ -z "$COMMAND" ]; then
    echo -e "${RED}错误: 未指定要执行的命令${NC}" >&2
    show_help
    exit 1
fi

# 检查服务器列表文件是否存在
if [ ! -f "$HOSTS_FILE" ]; then
    echo -e "${RED}错误: 服务器列表文件 '$HOSTS_FILE' 不存在${NC}" >&2
    exit 1
fi

# 检查认证方式
if [ -z "$PASSWORD" ] && [ -z "$KEY_FILE" ]; then
    echo -e "${RED}错误: 必须指定密码 (-p) 或密钥文件 (-k)${NC}" >&2
    exit 1
fi

if [ -n "$PASSWORD" ] && [ -n "$KEY_FILE" ]; then
    echo -e "${YELLOW}警告: 同时指定了密码和密钥文件，将优先使用密钥文件${NC}" >&2
fi

# 创建临时目录
TMP_DIR="/tmp/multissh_$(date +%s)"
mkdir -p "$TMP_DIR"

# 读取服务器列表
HOSTS=()
while IFS= read -r line || [ -n "$line" ]; do
    # 跳过空行和注释
    if [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    HOSTS+=("$line")
done < "$HOSTS_FILE"

# 检查是否有服务器
if [ ${#HOSTS[@]} -eq 0 ]; then
    echo -e "${RED}错误: 服务器列表文件 '$HOSTS_FILE' 中没有有效服务器${NC}" >&2
    rm -rf "$TMP_DIR"
    exit 1
fi

# 输出执行信息
echo -e "${GREEN}执行信息:${NC}"
echo -e "${GREEN}  服务器数量: ${#HOSTS[@]}${NC}"
if [ "$CONCURRENCY" -eq 0 ]; then
    echo -e "${GREEN}  并发数: 不限制${NC}"
else
    echo -e "${GREEN}  并发数: ${CONCURRENCY}${NC}"
fi
echo -e "${GREEN}  命令: ${COMMAND}${NC}"
if [ -n "$OUTPUT_FILE" ]; then
    echo -e "${GREEN}  输出文件: ${OUTPUT_FILE}${NC}"
fi
echo ""

# 定义执行函数
function execute_on_host() {
    local host=$1
    local output_file="$TMP_DIR/${host}.log"
    local status_file="$TMP_DIR/${host}.status"
    local exit_code=0
    
    output_lock
    echo -e "${YELLOW}[$host] 正在执行命令...${NC}"
    output_unlock
    
    if [ -n "$KEY_FILE" ]; then
        # 使用密钥文件认证
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$TIMEOUT -p $PORT -i "$KEY_FILE" "$USER@$host" "$COMMAND" > "$output_file" 2>&1
        exit_code=$?
    else
        # 使用密码认证 (需要 sshpass)
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$TIMEOUT -p $PORT "$USER@$host" "$COMMAND" > "$output_file" 2>&1
        exit_code=$?
    fi
    
    # 保存状态
    echo "$exit_code" > "$status_file"
    
    # 输出结果，确保完整输出
    output_lock
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}[$host] 成功 (退出码: $exit_code)${NC}"
    else
        echo -e "${RED}[$host] 失败 (退出码: $exit_code)${NC}"
    fi
    
    # 输出结果
    if [ $VERBOSE -eq 1 ] || [ $exit_code -ne 0 ]; then
        echo -e "${YELLOW}[$host] 输出:${NC}"
        cat "$output_file"
        echo ""
    fi
    
    # 追加到总输出文件
    if [ -n "$OUTPUT_FILE" ]; then
        {
            echo ">>>>>>>>>> $host <<<<<<<<<<"
            cat "$output_file"
            echo ""
        } >> "$OUTPUT_FILE"
    fi
    output_unlock
    
    return $exit_code
}

# 并发执行命令
echo -e "${GREEN}开始执行命令...${NC}"
echo ""

SUCCESS_COUNT=0
FAILED_HOSTS=()

for host in "${HOSTS[@]}"; do
    # 当并发数为0时，不限制并发
    if [ "$CONCURRENCY" -ne 0 ]; then
        # 控制并发数
        while [ $(jobs -r | wc -l) -ge "$CONCURRENCY" ]; do
            sleep 0.1
        done
    fi
    
    execute_on_host "$host" &
    BACKGROUND_PIDS+=($!)  # 记录后台进程ID
done

# 等待所有作业完成
wait

# 汇总结果
for host in "${HOSTS[@]}"; do
    status_file="$TMP_DIR/${host}.status"
    if [ -f "$status_file" ]; then
        exit_code=$(cat "$status_file")
        if [ "$exit_code" -eq 0 ]; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAILED_HOSTS+=("$host")
        fi
    else
        # 如果状态文件不存在，视为失败
        FAILED_HOSTS+=("$host")
    fi
done

# 汇总结果
echo ""
echo -e "${GREEN}执行结果汇总:${NC}"
echo -e "${GREEN}  成功: ${SUCCESS_COUNT}/${#HOSTS[@]}${NC}"
echo -e "${RED}  失败: ${#FAILED_HOSTS[@]}${NC}"

if [ ${#FAILED_HOSTS[@]} -gt 0 ]; then
    echo -e "${RED}  失败的服务器:${NC}"
    for host in "${FAILED_HOSTS[@]}"; do
        echo -e "${RED}    - $host${NC}"
    done
fi

# 清理临时文件
rm -rf "$TMP_DIR"

exit ${#FAILED_HOSTS[@]}