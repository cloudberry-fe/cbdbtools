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
    echo "  -c, --concurrency     指定并发执行的服务器数量 (默认为 5)"
    echo "  -v, --verbose         启用详细输出"
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
CONCURRENCY=5
VERBOSE=0

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
        -c|--concurrency)
            CONCURRENCY="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift 1
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
echo -e "${GREEN}  并发数: ${CONCURRENCY}${NC}"
echo -e "${GREEN}  命令: ${COMMAND}${NC}"
echo ""

# 定义执行函数
function execute_on_host() {
    local host=$1
    local output_file="$TMP_DIR/${host}.log"
    
    if [ -n "$KEY_FILE" ]; then
        # 使用密钥文件认证
        if [ $VERBOSE -eq 1 ]; then
            echo -e "${YELLOW}[$host] 正在使用密钥文件连接...${NC}"
        fi
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$TIMEOUT -p $PORT -i "$KEY_FILE" "$USER@$host" "$COMMAND" > "$output_file" 2>&1
    else
        # 使用密码认证 (需要 sshpass)
        if [ $VERBOSE -eq 1 ]; then
            echo -e "${YELLOW}[$host] 正在使用密码连接...${NC}"
        fi
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$TIMEOUT -p $PORT "$USER@$host" "$COMMAND" > "$output_file" 2>&1
    fi
    
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}[$host] 成功 (退出码: $exit_code)${NC}"
    else
        echo -e "${RED}[$host] 失败 (退出码: $exit_code)${NC}"
    fi
    
    if [ $VERBOSE -eq 1 ]; then
        echo -e "${YELLOW}[$host] 输出:${NC}"
        cat "$output_file"
        echo ""
    fi
    
    return $exit_code
}

# 并发执行命令
echo -e "${GREEN}开始执行命令...${NC}"
echo ""

# 使用进程池控制并发
ACTIVE_JOBS=5
EXIT_CODES=()

for host in "${HOSTS[@]}"; do
    # 控制并发数
    while [ $ACTIVE_JOBS -ge $CONCURRENCY ]; do
        sleep 1
        ACTIVE_JOBS=$(jobs -r | wc -l)
    done
    
    execute_on_host "$host" &
    EXIT_CODES[$!]=$host
    ACTIVE_JOBS=$(jobs -r | wc -l)
done

# 等待所有作业完成
wait

# 汇总结果
echo ""
echo -e "${GREEN}执行结果汇总:${NC}"

SUCCESS_COUNT=0
FAILED_HOSTS=()

for pid in "${!EXIT_CODES[@]}"; do
    wait $pid
    exit_code=$?
    host=${EXIT_CODES[$pid]}
    
    if [ $exit_code -eq 0 ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAILED_HOSTS+=("$host")
    fi
done

echo -e "${GREEN}  成功: ${SUCCESS_COUNT}/${#HOSTS[@]}${NC}"
echo -e "${RED}  失败: ${#FAILED_HOSTS[@]}${NC}"

if [ ${#FAILED_HOSTS[@]} -gt 0 ]; then
    echo -e "${RED}  失败的服务器:${NC}"
    for host in "${FAILED_HOSTS[@]}"; do
        echo -e "${RED}    - $host${NC}"
    done
fi

# 清理临时文件
if [ $VERBOSE -eq 0 ]; then
    rm -rf "$TMP_DIR"
fi

exit ${#FAILED_HOSTS[@]}