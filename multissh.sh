#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Usage help
function show_help() {
    echo "Usage: $0 [options] <command>"
    echo "Execute commands on multiple servers via SSH"
    echo ""
    echo "Options:"
    echo "  -h, --help            Show this help message"
    echo "  -f, --hosts-file      Specify file containing server list (default: segment_hosts.txt)"
    echo "  -u, --user            Specify SSH username (default: current user)"
    echo "  -p, --password        Specify SSH password (for password authentication)"
    echo "  -k, --key-file        Specify SSH private key file (for key authentication)"
    echo "  -P, --port            Specify SSH port (default: 22)"
    echo "  -t, --timeout         Specify SSH timeout in seconds (default: 30)"
    echo "  -v, --verbose         Enable verbose output"
    echo "  -o, --output          Specify output results file"
    echo "  -c, --concurrency     Specify maximum number of concurrent executions (default: 5, 0 means unlimited)"
    echo ""
    echo "Server list file format:"
    echo "  One server per line, can be IP address or hostname"
    echo "  Example:"
    echo "    192.168.1.1"
    echo "    server2.example.com"
}

# Default parameters
HOSTS_FILE="segment_hosts.txt"
USER=$(whoami)
PASSWORD=""
KEY_FILE=""
PORT=22
TIMEOUT=30
VERBOSE=0
OUTPUT_FILE=""
CONCURRENCY=5

# Create lock file
LOCK_FILE="/tmp/multissh_lock.$$"
touch "$LOCK_FILE"

# Array to store background process IDs
BACKGROUND_PIDS=()

# Cleanup function
function cleanup() {
    rm -f "$LOCK_FILE"
    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
    
    # Iterate and kill all background processes
    for pid in "${BACKGROUND_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
        fi
    done
}

# Register cleanup function
trap cleanup EXIT

# Output locking function
function output_lock() {
    while ! ln "$LOCK_FILE" "$LOCK_FILE.lock" 2>/dev/null; do
        sleep 0.1
    done
}

# Output unlocking function
function output_unlock() {
    rm -f "$LOCK_FILE.lock"
}

# Parse command line arguments
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
            # Remaining arguments as the command to execute
            COMMAND="$*"
            break
            ;;
    esac
done

# Check if command is provided
if [ -z "$COMMAND" ]; then
    echo -e "${RED}Error: No command specified${NC}" >&2
    show_help
    exit 1
fi

# Check if hosts file exists
if [ ! -f "$HOSTS_FILE" ]; then
    echo -e "${RED}Error: Server list file '$HOSTS_FILE' does not exist${NC}" >&2
    exit 1
fi

# Check authentication method
if [ -z "$PASSWORD" ] && [ -z "$KEY_FILE" ]; then
    echo -e "${RED}Error: Must specify either password (-p) or key file (-k)${NC}" >&2
    exit 1
fi

if [ -n "$PASSWORD" ] && [ -n "$KEY_FILE" ]; then
    echo -e "${YELLOW}Warning: Both password and key file specified, key file will be used first${NC}" >&2
fi

# Create temporary directory
TMP_DIR="/tmp/multissh_$(date +%s)"
mkdir -p "$TMP_DIR"

# Read server list
HOSTS=()
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    if [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    HOSTS+=("$line")
done < "$HOSTS_FILE"

# Check if there are any servers
if [ ${#HOSTS[@]} -eq 0 ]; then
    echo -e "${RED}Error: No valid servers in file '$HOSTS_FILE'${NC}" >&2
    rm -rf "$TMP_DIR"
    exit 1
fi

# Output execution information
echo -e "${GREEN}Execution Information:${NC}"
echo -e "${GREEN}  Number of servers: ${#HOSTS[@]}${NC}"
if [ "$CONCURRENCY" -eq 0 ]; then
    echo -e "${GREEN}  Concurrency: Unlimited${NC}"
else
    echo -e "${GREEN}  Concurrency: ${CONCURRENCY}${NC}"
fi
echo -e "${GREEN}  Command: ${COMMAND}${NC}"
if [ -n "$OUTPUT_FILE" ]; then
    echo -e "${GREEN}  Output file: ${OUTPUT_FILE}${NC}"
fi
echo ""

# Define execution function
function execute_on_host() {
    local host=$1
    local output_file="$TMP_DIR/${host}.log"
    local status_file="$TMP_DIR/${host}.status"
    local exit_code=0
    
    output_lock
    echo -e "${YELLOW}[$host] Executing command...${NC}"
    output_unlock
    
    if [ -n "$KEY_FILE" ]; then
        # Use key file authentication
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$TIMEOUT -p $PORT -i "$KEY_FILE" "$USER@$host" "$COMMAND" > "$output_file" 2>&1
        exit_code=$?
    else
        # Use password authentication (requires sshpass)
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$TIMEOUT -p $PORT "$USER@$host" "$COMMAND" > "$output_file" 2>&1
        exit_code=$?
    fi
    
    # Save status
    echo "$exit_code" > "$status_file"
    
    # Output results, ensuring complete output
    output_lock
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}[$host] Success (Exit code: $exit_code)${NC}"
    else
        echo -e "${RED}[$host] Failed (Exit code: $exit_code)${NC}"
    fi
    
    # Output results
    if [ $VERBOSE -eq 1 ] || [ $exit_code -ne 0 ]; then
        echo -e "${YELLOW}[$host] Output:${NC}"
        cat "$output_file"
        echo ""
    fi
    
    # Append to total output file
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

# Execute commands concurrently
echo -e "${GREEN}Starting command execution...${NC}"
echo ""

SUCCESS_COUNT=0
FAILED_HOSTS=()

for host in "${HOSTS[@]}"; do
    # When concurrency is 0, do not limit concurrency
    if [ "$CONCURRENCY" -ne 0 ]; then
        # Control concurrency
        while [ $(jobs -r | wc -l) -ge "$CONCURRENCY" ]; do
            sleep 0.1
        done
    fi
    
    execute_on_host "$host" &
    BACKGROUND_PIDS+=($!)  # Record background process ID
done

# Wait for all jobs to complete
wait

# Summarize results
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
        # If status file does not exist, consider it failed
        FAILED_HOSTS+=("$host")
    fi
done

# Summarize results
echo ""
echo -e "${GREEN}Execution Results Summary:${NC}"
echo -e "${GREEN}  Success: ${SUCCESS_COUNT}/${#HOSTS[@]}${NC}"
echo -e "${RED}  Failed: ${#FAILED_HOSTS[@]}${NC}"

if [ ${#FAILED_HOSTS[@]} -gt 0 ]; then
    echo -e "${RED}  Failed servers:${NC}"
    for host in "${FAILED_HOSTS[@]}"; do
        echo -e "${RED}    - $host${NC}"
    done
fi

# Clean up temporary files
rm -rf "$TMP_DIR"

exit ${#FAILED_HOSTS[@]}