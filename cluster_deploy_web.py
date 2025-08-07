from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
import os
import re
import subprocess
import shutil
from datetime import datetime
import json
import time
import threading

app = Flask(__name__)
app.secret_key = 'supersecretkey'

# Configuration file paths
PARAM_FILE = 'deploycluster_parameter.sh'
HOSTS_FILE = 'segmenthosts.conf'

# Read configuration parameters
def read_parameters():
    params = {}
    if os.path.exists(PARAM_FILE):
        with open(PARAM_FILE, 'r') as f:
            content = f.read()
            # Extract export variables
            for line in content.split('\n'):
                if line.startswith('export '):
                    parts = line[7:].split('=', 1)
                    if len(parts) == 2:
                        key = parts[0].strip()
                        value = parts[1].strip().strip('"\'')
                        params[key] = value
    return params

# Save configuration parameters
def save_parameters(params):
    # If parameter file exists, backup it first
    if os.path.exists(PARAM_FILE):
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_file = f'{PARAM_FILE}.backup_{timestamp}'
        shutil.copy2(PARAM_FILE, backup_file)
        print(f'Parameter file backed up as: {backup_file}')
    
    # Read the default parameter file as template
    with open('deploycluster_parameter.sh', 'r') as f:
        content = f.read()
    
    # Replace parameters in the content
    for key, value in params.items():
        # Use regex to replace export statements
        pattern = r'(export\s+' + key + r'\s*=\s*["\'])(.*?)(["\'])'
        replacement = f'export {key}="{value}"'
        content = re.sub(pattern, replacement, content)
    
    # Write the updated content to file
    with open(PARAM_FILE, 'w') as f:
        f.write(content)

# Read host configuration
def read_hosts():
    hosts = {'coordinator': [], 'segments': []}
    if os.path.exists(HOSTS_FILE):
        with open(HOSTS_FILE, 'r') as f:
            content = f.read()
            # Extract coordinator host
            coord_match = re.search(r'##Coordinator hosts\n([\d.]+)\s+([\w-]+)', content)
            if coord_match:
                hosts['coordinator'] = [coord_match.group(1), coord_match.group(2)]
            # Extract segment hosts
            segment_matches = re.findall(r'##Segment hosts\n([\d.]+)\s+([\w-]+)\n([\d.]+)\s+([\w-]+)', content)
            if segment_matches:
                for match in segment_matches:
                    hosts['segments'].append([match[0], match[1]])
                    hosts['segments'].append([match[2], match[3]])
            else:
                # Try to match single segment host
                single_segment = re.search(r'##Segment hosts\n([\d.]+)\s+([\w-]+)', content)
                if single_segment:
                    hosts['segments'].append([single_segment.group(1), single_segment.group(2)])
    return hosts

# Save host configuration
def save_hosts(hosts):
    # If hosts file exists, backup it first
    if os.path.exists(HOSTS_FILE):
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_file = f'{HOSTS_FILE}.backup_{timestamp}'
        shutil.copy2(HOSTS_FILE, backup_file)
        print(f'Hosts file backed up as: {backup_file}')
    
    with open(HOSTS_FILE, 'w') as f:
        f.write('##Define hosts used for Hashdata\n')
        f.write('#Hashdata hosts begin\n')
        f.write('##Coordinator hosts\n')
        if hosts['coordinator']:
            f.write(f"{hosts['coordinator'][0]} {hosts['coordinator'][1]}\n")
        f.write('##Segment hosts\n')
        for segment in hosts['segments']:
            f.write(f"{segment[0]} {segment[1]}\n")
        f.write('#Hashdata hosts end\n')

# Deploy cluster
def deploy_cluster():
    try:
        # Run deployment script
        process = subprocess.Popen(['sh', 'deploycluster.sh'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = process.communicate()
        return {'success': process.returncode == 0, 'stdout': stdout.decode(), 'stderr': stderr.decode()}
    except Exception as e:
        return {'success': False, 'error': str(e)}

@app.route('/')
def index():
    params = read_parameters()
    hosts = read_hosts()
    return render_template('index.html', params=params, hosts=hosts)

@app.route('/save', methods=['POST'])
def save():
    try:
        # Save parameters
        params = request.form.to_dict()
        save_parameters(params)
        # Save hosts
        hosts = {
            'coordinator': [request.form.get('coord_ip'), request.form.get('coord_hostname')],
            'segments': []
        }
        # Extract segment hosts
        segment_count = int(request.form.get('segment_count', 0))
        for i in range(segment_count):
            ip = request.form.get(f'segment_ip_{i}')
            hostname = request.form.get(f'segment_hostname_{i}')
            if ip and hostname:
                hosts['segments'].append([ip, hostname])
        save_hosts(hosts)
        flash('Configuration saved successfully!')
        return redirect(url_for('index'))
    except Exception as e:
        flash(f'Error saving configuration: {str(e)}')
        return redirect(url_for('index'))

@app.route('/deploy', methods=['POST'])
def deploy():
    # Check if deployment is already running
    if is_deployment_running():
        flash('Deployment is already running. Please wait for it to complete or check the logs for progress.')
        return redirect(url_for('index_with_tab', tab='deploy'))
    
    # Get deployment type
    params = read_parameters()
    deploy_type = params.get('DEPLOY_TYPE', 'single')
    
    # Start background deployment
    success, message = start_background_deployment(deploy_type)
    
    if success:
        flash(f'Deployment started successfully! Log file: {DEPLOYMENT_STATUS["log_file"]}')
    else:
        flash(f'Failed to start deployment: {message}')
    
    return redirect(url_for('index_with_tab', tab='deploy'))

# New route to get deployment status
@app.route('/deployment_status')
def deployment_status():
    with DEPLOYMENT_LOCK:
        return jsonify({
            'running': DEPLOYMENT_STATUS['running'],
            'log_file': DEPLOYMENT_STATUS['log_file'],
            'start_time': DEPLOYMENT_STATUS['start_time']
        })

# New route to get deployment logs
@app.route('/deployment_logs')
def deployment_logs():
    log_content = get_deployment_log()
    return jsonify({'logs': log_content})

@app.route('/save_params', methods=['POST'])
def save_params():
    try:
        params = request.form.to_dict()
        save_parameters(params)
        flash('Configuration parameters saved successfully!')
        # Get deployment type to determine redirect target
        deploy_type = params.get('DEPLOY_TYPE', 'single')
        return redirect(url_for('index_with_tab', tab='hosts' if deploy_type == 'multi' else 'deploy'))
    except Exception as e:
        flash(f'Error saving parameters: {str(e)}')
        return redirect(url_for('index'))

@app.route('/save_hosts', methods=['POST'])
def save_hosts_only():
    try:
        hosts = {
            'coordinator': [request.form.get('coord_ip'), request.form.get('coord_hostname')],
            'segments': []
        }
        # Extract segment hosts
        segment_count = int(request.form.get('segment_count', 0))
        for i in range(segment_count):
            ip = request.form.get(f'segment_ip_{i}')
            hostname = request.form.get(f'segment_hostname_{i}')
            if ip and hostname:
                hosts['segments'].append([ip, hostname])
        save_hosts(hosts)
        flash('Host configuration saved successfully!')
        return redirect(url_for('index_with_tab', tab='deploy'))
    except Exception as e:
        flash(f'Error saving hosts: {str(e)}')
        return redirect(url_for('index'))

@app.route('/<tab>')
def index_with_tab(tab):
    params = read_parameters()
    hosts = read_hosts()
    # Add deployment_info to be passed to the template
    deployment_info = {
        'mode': params.get('DEPLOY_TYPE', 'single'),
        'coordinator': hosts.get('coordinator', []),
        'segment_hosts': hosts.get('segments', []),
        'running': False,
        'log_file': None,
        'start_time': None
    }
    # If we're on the deploy tab, get actual deployment status
    if tab == 'deploy':
        with DEPLOYMENT_LOCK:
            deployment_info['running'] = DEPLOYMENT_STATUS['running']
            deployment_info['log_file'] = DEPLOYMENT_STATUS['log_file']
            deployment_info['start_time'] = DEPLOYMENT_STATUS['start_time']
    
    return render_template('index.html', params=params, hosts=hosts, active_tab=tab, deployment_info=deployment_info)

if __name__ == '__main__':
    # Ensure templates directory exists
    if not os.path.exists('templates'):
        os.makedirs('templates')
    # Start application
    app.run(host='0.0.0.0', port=5000, debug=True)


# Global variable to track deployment status
DEPLOYMENT_STATUS = {
    'running': False,
    'log_file': None,
    'start_time': None
}

# Lock for thread safety
DEPLOYMENT_LOCK = threading.Lock()

# Function to check if there's a running deployment process
# 在文件顶部添加导入
import psutil
import signal

# 修改is_deployment_running函数
def is_deployment_running():
    with DEPLOYMENT_LOCK:
        if not DEPLOYMENT_STATUS['running']:
            return False
        
        # 检查进程是否实际存在
        try:
            # 获取当前所有python相关进程
            for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
                try:
                    cmdline = ' '.join(proc.info['cmdline'] or [])
                    if 'deploycluster.sh' in cmdline or 'run.sh' in cmdline:
                        return True
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
            
            # 如果找不到进程，检查日志文件是否最近更新
            if DEPLOYMENT_STATUS['log_file'] and os.path.exists(DEPLOYMENT_STATUS['log_file']):
                mtime = os.path.getmtime(DEPLOYMENT_STATUS['log_file'])
                if time.time() - mtime < 30:  # 30秒内更新过认为仍在运行
                    return True
            
            DEPLOYMENT_STATUS['running'] = False
            return False
            
        except Exception:
            DEPLOYMENT_STATUS['running'] = False
            return False

# 修改start_background_deployment函数，保存进程PID
def start_background_deployment(cluster_type='single'):
    global DEPLOYMENT_STATUS
    
    with DEPLOYMENT_LOCK:
        if DEPLOYMENT_STATUS['running']:
            return False, "Deployment is already running. Please wait for it to complete."
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        log_file = f'deploy_cluster_{timestamp}.log'
        
        DEPLOYMENT_STATUS['running'] = True
        DEPLOYMENT_STATUS['log_file'] = log_file
        DEPLOYMENT_STATUS['start_time'] = time.time()
        DEPLOYMENT_STATUS['pid'] = None  # 新增：保存进程PID
    
    try:
        # 使用Popen启动进程并获取PID
        process = subprocess.Popen(
            ['sh', 'run.sh', cluster_type],
            stdout=open(log_file, 'w'),
            stderr=subprocess.STDOUT,
            preexec_fn=os.setsid
        )
        
        DEPLOYMENT_STATUS['pid'] = process.pid
        
        def monitor_process():
            process.wait()
            with DEPLOYMENT_LOCK:
                DEPLOYMENT_STATUS['running'] = False
        
        monitor_thread = threading.Thread(target=monitor_process)
        monitor_thread.daemon = True
        monitor_thread.start()
        
        return True, f"Deployment started successfully. Log file: {log_file}"
    
    except Exception as e:
        with DEPLOYMENT_LOCK:
            DEPLOYMENT_STATUS['running'] = False
        return False, str(e)

# Function to get deployment log content
def get_deployment_log(log_file=None, lines=100):
    if not log_file:
        with DEPLOYMENT_LOCK:
            log_file = DEPLOYMENT_STATUS['log_file']
    
    if not log_file or not os.path.exists(log_file):
        return "Log file not found."
    
    try:
        with open(log_file, 'r') as f:
            # Read last N lines
            lines_content = f.readlines()
            if len(lines_content) > lines:
                lines_content = lines_content[-lines:]
            return ''.join(lines_content)
    except Exception as e:
        return f"Error reading log file: {str(e)}"