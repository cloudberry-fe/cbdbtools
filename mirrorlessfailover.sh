#!/bin/bash

# Configure database connection information
#MASTER_HOST="master_host"  # Replace with your Greenplum Master node hostname or IP address
#MASTER_PORT="5432"         # Replace with your Greenplum Master node port
#DB_NAME="your_db_name"     # Replace with your database name
#USER="your_username"       # Replace with your username

# Get list of Primary Segment IP addresses or hostnames
#PRIMARY_SEGMENTS=("segment1_host" "segment2_host" "segment3_host") # Replace with actual Primary Segment hostnames or IP addresses


function start_primary_segment() {

  echo "ssh -n $1 \"bash -c 'cd ~/; $GPHOME/bin/pg_ctl -D $2 -l $2/log/startup.log -w -t 600 -o \\\" -p $3 -c gp_role=execute \\\" start 2>&1' \""
  
  ssh -n $1 "bash -c 'cd ~/; $GPHOME/bin/pg_ctl -D $2 -l $2/log/startup.log -w -t 600 -o \" -p $3 -c gp_role=execute \" start 2>&1' "
}

# Check database status every 5 seconds
while true; do
  # Check if database is working normally
  FailedNum=$(gpstate | grep "Total number postmaster processes missing" | awk -F '=' '{print $2}'| sed 's/[^0-9]//g')
  
  echo "$FailedNum failed segments detected."
  
  if [ "${FailedNum}" -gt "0" ]; then
    echo "ERROR: $FailedNum failed segments detected"
    break
  fi

  # Wait for 5 seconds
  sleep 5
done

SQL_QUERY_HOSTS="SELECT DISTINCT hostname,address FROM gp_segment_configuration WHERE role = 'p' AND content >= 0 order by hostname"

echo "PGOPTIONS='-c gp_role=utility' psql -v ON_ERROR_STOP=1 -t -A -F ' ' -c \"${SQL_QUERY_HOSTS}\" -o all_segment_hosts.txt"

PGOPTIONS='-c gp_role=utility' psql -v ON_ERROR_STOP=1 -t -A -F ' ' -c "${SQL_QUERY_HOSTS}" -o all_segment_hosts.txt
  
SQL_QUERY="select dbid,content,port,hostname,address,datadir from gp_segment_configuration g where role='p' and g.content >= 0 order by 1, 4, 5"

rm -rf failed_segments.txt
rm -rf all_segments.txt
rm -rf failed_segment_hosts.txt
rm -rf recovered_segments.txt



for i in $(psql -v ON_ERROR_STOP=1 -q -A -t -c "${SQL_QUERY}"); do
  dbid=$(echo ${i} | awk -F '|' '{print $1}')
  content=$(echo ${i} | awk -F '|' '{print $2}')
  port=$(echo ${i} | awk -F '|' '{print $3}')
  seghostname=$(echo ${i} | awk -F '|' '{print $4}')
  address=$(echo ${i} | awk -F '|' '{print $5}')
  datadir=$(echo ${i} | awk -F '|' '{print $6}' | sed 's#//#/#g')

  echo "${dbid} ${content} ${port} ${seghostname} ${address} ${datadir}" >> all_segments.txt
  
  echo "PGOPTIONS='-c gp_role=utility' psql -h ${seghostname} -p ${port} -c \"SELECT 1\" >/dev/null 2>&1"
  PGOPTIONS='-c gp_role=utility' psql -h ${seghostname} -p ${port} -c "SELECT 1;" >/dev/null 2>&1
  
  if [ $? -ne 0 ]; then
  
    echo "Segment ${dbid} on ${seghostname} with port ${port} is not accessible."
    echo "${dbid} ${content} ${port} ${seghostname} ${address} ${datadir}" >> failed_segments.txt
    echo "${seghostname} ${address}" >> failed_segment_hosts.txt
    
  fi
done

set -e

grep -v -F -f failed_segment_hosts.txt all_segment_hosts.txt > remain_segment_hosts.txt


# Read remain_segment_hosts.txt into arrays for the first and second columns
while read -r col1 col2; do
    hosts_col1+=("$col1")
    hosts_col2+=("$col2")
done < remain_segment_hosts.txt

# Initialize counters for the arrays
host_count=${#hosts_col1[@]}
i=0

# Process failed_segments.txt
while read -r line; do
  # Split the line into an array
  line_array=($line)
  
  # Replace the 4th and 5th elements with the corresponding values from the hosts arrays
  line_array[3]=${hosts_col1[i]}
  line_array[4]=${hosts_col2[i]}
  
  # Print the modified line to new_failed_segments.txt
  echo "${line_array[@]}" >> recovered_segments.txt
  
  # Increment the counter, reset if it reaches the end of the hosts arrays
  i=$(( (i + 1) % host_count ))
done < failed_segments.txt


# Read the new_failed_segments.txt file and process each line
while read -r line; do
  # Split the line into an array by spaces
  line_array=($line)
  
  # Extract the necessary parameters
  dbid=${line_array[0]}
  port=${line_array[2]}
  host=${line_array[3]}
  address=${line_array[4]}
  data_dir=${line_array[5]}

  port=$((port + 100))
  
  # Call the function with extracted parameters
  # start_primary_segment "$host" "$data_dir" "$port"

  echo "UPDATE_QUERY=\"set allow_system_table_mods = true;update gp_segment_configuration set hostname='$host',address='$address',port='$port' where dbid='$dbid';\""
  
  UPDATE_QUERY="set allow_system_table_mods = true;update gp_segment_configuration set hostname='$host',address='$address',port='$port' where dbid='$dbid';"
  
  PGOPTIONS='-c gp_role=utility' psql -v ON_ERROR_STOP=1 -t -A -c "${UPDATE_QUERY}"

  gpstop -af
  
  gpstart -a

done < recovered_segments.txt

