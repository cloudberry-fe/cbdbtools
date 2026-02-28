from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
import os
import re
import subprocess
import shutil
from datetime import datetime
import json
import time
import threading
from werkzeug.utils import secure_filename
import psutil

app = Flask(__name__)
app.secret_key = 'supersecretkey'

# Configuration file paths
PARAM_FILE = 'deploycluster_parameter.sh'
HOSTS_FILE = 'segmenthosts.conf'

# Deployment synchronization lock and status tracking
DEPLOYMENT_LOCK = threading.RLock()
DEPLOYMENT_STATUS = {
    'running': False,
    'log_file': None,
    'start_time': None,
    'pid': None,
    'success': None,
    'current_stage': 'idle',
    'stage_progress': 0,
    'total_stages': 0,
    'completed_stages': 0
}

# Define deployment stages for progress tracking
DEPLOYMENT_STAGES = [
    {'key': 'preparing', 'name': 'Preparing', 'description': '准备部署环境', 'weight': 5},
    {'key': 'ssh_setup', 'name': 'SSH Setup', 'description': '配置 SSH 密钥', 'weight': 10},
    {'key': 'env_init_coordinator', 'name': 'Env Coordinator', 'description': '初始化 Coordinator 节点', 'weight': 25},
    {'key': 'env_init_segments', 'name': 'Env Segments', 'description': '初始化 Segment 节点', 'weight': 25},
    {'key': 'install_db', 'name': 'Install DB', 'description': '安装数据库软件', 'weight': 15},
    {'key': 'init_cluster', 'name': 'Init Cluster', 'description': '初始化数据库集群', 'weight': 15},
    {'key': 'verifying', 'name': 'Verifying', 'description': '验证部署结果', 'weight': 5}
]

# Read configuration parameters
def read_parameters():
    params = {}
    if os.path.exists(PARAM_FILE):
        with open(PARAM_FILE, 'r') as f:
            content = f.read()
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
    if os.path.exists(PARAM_FILE):
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_file = f'{PARAM_FILE}.backup_{timestamp}'
        shutil.copy2(PARAM_FILE, backup_file)
        print(f'Parameter file backed up as: {backup_file}')

    with open('deploycluster_parameter.sh', 'r') as f:
        content = f.read()

    for key, value in params.items():
        pattern = r'(export\s+' + key + r'\s*=\s*["\'])(.*?)(["\'])'
        replacement = f'export {key}="{value}"'
        content = re.sub(pattern, replacement, content)

    with open(PARAM_FILE, 'w') as f:
        f.write(content)

# Read host configuration
def read_hosts():
    hosts = {'coordinator': [], 'segments': []}
    if os.path.exists(HOSTS_FILE):
        with open(HOSTS_FILE, 'r') as f:
            content = f.read()
            coord_match = re.search(r'##Coordinator hosts\n([\d.]+)\s+([\w-]+)', content)
            if coord_match:
                hosts['coordinator'] = [coord_match.group(1), coord_match.group(2)]

            segment_section = re.search(r'##Segment hosts\n((?:[\d.]+)\s+([\w-]+)\n?)+', content)
            if segment_section:
                segment_lines = re.findall(r'([\d.]+)\s+([\w-]+)', segment_section.group(0))
                for ip, hostname in segment_lines:
                    hosts['segments'].append([ip, hostname])
    return hosts

# Save host configuration
def save_hosts(hosts):
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

# Function to check if there's a running deployment process
def is_deployment_running():
    with DEPLOYMENT_LOCK:
        if not DEPLOYMENT_STATUS['running']:
            return False

        try:
            for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
                try:
                    cmdline = ' '.join(proc.info['cmdline'] or [])
                    if 'deploycluster.sh' in cmdline or 'run.sh' in cmdline:
                        return True
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue

            if DEPLOYMENT_STATUS['log_file'] and os.path.exists(DEPLOYMENT_STATUS['log_file']):
                mtime = os.path.getmtime(DEPLOYMENT_STATUS['log_file'])
                if time.time() - mtime < 30:
                    return True

            DEPLOYMENT_STATUS['running'] = False
            return False

        except Exception:
            DEPLOYMENT_STATUS['running'] = False
            return False

# Function to analyze log and determine current stage
def analyze_deployment_progress(log_content):
    stage_keywords = {
        'preparing': ['starting deployment', 'beginning', 'preparing', 'checking'],
        'ssh_setup': ['ssh', 'key', 'ssh-keygen', 'ssh-copy-id'],
        'env_init_coordinator': ['init_env.sh', 'coordinator', 'mdw', 'master'],
        'env_init_segments': ['init_env_segment', 'segment', 'sdw', 'segments'],
        'install_db': ['install', 'rpm', 'yum', 'software'],
        'init_cluster': ['init_cluster', 'gpinitsystem', 'initializing cluster'],
        'verifying': ['verify', 'check', 'validate', 'complete', 'success']
    }

    lines = log_content.lower().split('\n')
    current_stage = 'preparing'
    max_weight = 0

    for i, stage in enumerate(DEPLOYMENT_STAGES):
        stage_key = stage['key']
        keywords = stage_keywords.get(stage_key, [])
        for keyword in keywords:
            if any(keyword in line for line in lines):
                current_stage = stage_key
                max_weight = i

    completed_weight = sum(s['weight'] for s in DEPLOYMENT_STAGES[:max_weight])
    total_weight = sum(s['weight'] for s in DEPLOYMENT_STAGES)
    progress = int((completed_weight / total_weight) * 100) if total_weight > 0 else 0

    return current_stage, progress, max_weight

# Start background deployment
def start_background_deployment(cluster_type='single'):
    global DEPLOYMENT_STATUS

    with DEPLOYMENT_LOCK:
        if DEPLOYMENT_STATUS['running']:
            return False, "Deployment is already running. Please wait for it to complete."

        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        log_file = os.path.abspath(f'deploy_cluster_{timestamp}.log')

        DEPLOYMENT_STATUS['running'] = True
        DEPLOYMENT_STATUS['log_file'] = log_file
        DEPLOYMENT_STATUS['start_time'] = time.time()
        DEPLOYMENT_STATUS['pid'] = None
        DEPLOYMENT_STATUS['success'] = None
        DEPLOYMENT_STATUS['current_stage'] = 'preparing'
        DEPLOYMENT_STATUS['stage_progress'] = 0
        DEPLOYMENT_STATUS['total_stages'] = len(DEPLOYMENT_STAGES)
        DEPLOYMENT_STATUS['completed_stages'] = 0

    try:
        process = subprocess.Popen(
            ['sh', 'run.sh', cluster_type],
            stdout=open(log_file, 'w'),
            stderr=subprocess.STDOUT,
            preexec_fn=os.setsid
        )

        DEPLOYMENT_STATUS['pid'] = process.pid

        def monitor_process(process, log_file):
            last_update_time = time.time()

            while process.poll() is None:
                time.sleep(2)
                if os.path.exists(log_file):
                    try:
                        with open(log_file, 'r') as f:
                            log_content = f.read()
                            current_stage, progress, completed_count = analyze_deployment_progress(log_content)
                            with DEPLOYMENT_LOCK:
                                DEPLOYMENT_STATUS['current_stage'] = current_stage
                                DEPLOYMENT_STATUS['stage_progress'] = progress
                                DEPLOYMENT_STATUS['completed_stages'] = completed_count
                    except Exception:
                        pass

            with DEPLOYMENT_LOCK:
                DEPLOYMENT_STATUS['running'] = False
                DEPLOYMENT_STATUS['stage_progress'] = 100
                DEPLOYMENT_STATUS['completed_stages'] = len(DEPLOYMENT_STAGES)
                try:
                    with open(log_file, 'r') as f:
                        log_content = f.read()
                        DEPLOYMENT_STATUS['success'] = ('deployment completed successfully' in log_content.lower() or
                                                       'finished deploy cluster' in log_content.lower() or
                                                       'deployment complete' in log_content.lower())
                except:
                    DEPLOYMENT_STATUS['success'] = None

        monitor_thread = threading.Thread(target=monitor_process, args=(process, log_file))
        monitor_thread.daemon = True
        monitor_thread.start()

        return True, f"Deployment started successfully. Log file: {log_file}"

    except Exception as e:
        with DEPLOYMENT_LOCK:
            DEPLOYMENT_STATUS['running'] = False
        return False, str(e)

# Function to get deployment log content
def get_deployment_log(log_file=None, lines=200):
    if not log_file:
        with DEPLOYMENT_LOCK:
            log_file = DEPLOYMENT_STATUS['log_file']

    if not log_file:
        return "No log file specified."

    if not os.path.exists(log_file):
        return f"Log file not found: {log_file}"

    try:
        with open(log_file, 'r') as f:
            lines_content = f.readlines()
            if len(lines_content) > lines:
                lines_content = lines_content[-lines:]
            return ''.join(lines_content)
    except Exception as e:
        return f"Error reading log file: {str(e)}"

@app.route('/')
def index():
    params = read_parameters()
    hosts = read_hosts()
    deployment_info = {
        'mode': params.get('DEPLOY_TYPE', 'single'),
        'coordinator': hosts.get('coordinator', []),
        'segment_hosts': hosts.get('segments', []),
        'running': False,
        'log_file': None,
        'start_time': None
    }

    with DEPLOYMENT_LOCK:
        deployment_info['running'] = DEPLOYMENT_STATUS['running']
        deployment_info['log_file'] = DEPLOYMENT_STATUS['log_file']
        deployment_info['start_time'] = DEPLOYMENT_STATUS['start_time']

    return render_template('index.html', params=params, hosts=hosts, deployment_info=deployment_info)

@app.route('/save', methods=['POST'])
def save():
    try:
        params = request.form.to_dict()
        save_parameters(params)
        hosts = {
            'coordinator': [request.form.get('coord_ip'), request.form.get('coord_hostname')],
            'segments': []
        }
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
    if is_deployment_running():
        return jsonify({
            'success': False,
            'message': 'Deployment is already running. Please wait for it to complete or check the logs for progress.'
        })

    params = read_parameters()
    deploy_type = params.get('DEPLOY_TYPE', 'single')

    success, message = start_background_deployment(deploy_type)

    if success:
        log_file = message.split(': ')[-1] if ': ' in message else ''
        return jsonify({
            'success': True,
            'message': message,
            'log_file': log_file
        })
    else:
        return jsonify({
            'success': False,
            'message': message
        })

@app.route('/deployment_status')
def deployment_status():
    with DEPLOYMENT_LOCK:
        elapsed_time = 0
        if DEPLOYMENT_STATUS['start_time']:
            elapsed_time = int(time.time() - DEPLOYMENT_STATUS['start_time'])

        return jsonify({
            'running': DEPLOYMENT_STATUS['running'],
            'log_file': DEPLOYMENT_STATUS['log_file'],
            'start_time': DEPLOYMENT_STATUS['start_time'],
            'success': DEPLOYMENT_STATUS['success'],
            'current_stage': DEPLOYMENT_STATUS['current_stage'],
            'stage_progress': DEPLOYMENT_STATUS['stage_progress'],
            'total_stages': DEPLOYMENT_STATUS['total_stages'],
            'completed_stages': DEPLOYMENT_STATUS['completed_stages'],
            'stages': DEPLOYMENT_STAGES,
            'elapsed_time': elapsed_time
        })

@app.route('/deployment_logs')
def deployment_logs():
    log_file = request.args.get('log_file')
    lines = int(request.args.get('lines', 200))
    log_content = get_deployment_log(log_file, lines)
    return jsonify({'logs': log_content})

@app.route('/save_params', methods=['POST'])
def save_params():
    try:
        params = request.form.to_dict()

        if 'CLOUDBERRY_RPM' in params and params['CLOUDBERRY_RPM']:
            if os.path.exists(params['CLOUDBERRY_RPM']):
                print(f'Using uploaded RPM file: {params["CLOUDBERRY_RPM"]}')
            else:
                flash(f'Warning: RPM file path does not exist: {params["CLOUDBERRY_RPM"]}')

        if 'SEGMENT_ACCESS_KEYFILE' in params and params['SEGMENT_ACCESS_KEYFILE']:
            deploy_type = params.get('DEPLOY_TYPE', 'single')
            segment_access_method = params.get('SEGMENT_ACCESS_METHOD', '')
            if deploy_type == 'multi' and segment_access_method == 'keyfile':
                if os.path.exists(params['SEGMENT_ACCESS_KEYFILE']):
                    print(f'Using uploaded Key file: {params["SEGMENT_ACCESS_KEYFILE"]}')
                else:
                    flash(f'Warning: Key file path does not exist: {params["SEGMENT_ACCESS_KEYFILE"]}')
            else:
                print(f'Skipping key file check for {deploy_type} deployment with {segment_access_method} access')

        save_parameters(params)
        flash('Configuration parameters saved successfully!')

        deploy_type = params.get('DEPLOY_TYPE', 'single')
        return redirect(url_for('index_with_tab', tab='hosts' if deploy_type == 'multi' else 'deploy'))
    except Exception as e:
        flash(f'Error saving parameters: {str(e)}')
        return redirect(url_for('index'))

@app.route('/save_hosts', methods=['POST'])
def save_hosts():
    try:
        hosts = {
            'coordinator': [request.form.get('coord_ip'), request.form.get('coord_hostname')],
            'segments': []
        }
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

@app.route('/save_hosts_only', methods=['POST'])
def save_hosts_only():
    try:
        hosts = {
            'coordinator': [request.form.get('coord_ip'), request.form.get('coord_hostname')],
            'segments': []
        }
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
    deployment_info = {
        'mode': params.get('DEPLOY_TYPE', 'single'),
        'coordinator': hosts.get('coordinator', []),
        'segment_hosts': hosts.get('segments', []),
        'running': False,
        'log_file': None,
        'start_time': None
    }
    if tab == 'deploy':
        with DEPLOYMENT_LOCK:
            deployment_info['running'] = DEPLOYMENT_STATUS['running']
            deployment_info['log_file'] = DEPLOYMENT_STATUS['log_file']
            deployment_info['start_time'] = DEPLOYMENT_STATUS['start_time']

    return render_template('index.html', params=params, hosts=hosts, active_tab=tab, deployment_info=deployment_info)

@app.route('/get_deployment_params')
def get_deployment_params():
    params = read_parameters()
    hosts = read_hosts()

    data_dirs = params.get('DATA_DIRECTORY', '').split() if params.get('DATA_DIRECTORY') else []
    mirror_dirs = params.get('MIRROR_DATA_DIRECTORY', '').split() if params.get('MIRROR_DATA_DIRECTORY') else []

    return jsonify({
        'params': params,
        'hosts': hosts,
        'data_dirs': data_dirs,
        'mirror_dirs': mirror_dirs
    })

UPLOAD_FOLDER = '/tmp/uploads'
ALLOWED_RPM_EXTENSIONS = {'rpm'}

os.makedirs(UPLOAD_FOLDER, exist_ok=True)

def allowed_file(filename, file_type):
    if file_type == 'rpm':
        return '.' in filename and \
               filename.rsplit('.', 1)[1].lower() in ALLOWED_RPM_EXTENSIONS
    elif file_type == 'key':
        return True
    return False

@app.route('/upload_file', methods=['POST'])
def upload_file():
    try:
        if 'file' not in request.files:
            return jsonify({'success': False, 'message': 'No file part'})

        file = request.files['file']
        file_type = request.form.get('type', '')
        upload_path = request.form.get('upload_path', '/tmp/uploads')

        if file.filename == '':
            return jsonify({'success': False, 'message': 'No selected file'})

        if file and allowed_file(file.filename, file_type):
            os.makedirs(upload_path, exist_ok=True)
            os.chmod(upload_path, 0o755)

            filename = secure_filename(file.filename)
            file_path = os.path.join(upload_path, filename)

            try:
                file.save(file_path)
                os.chmod(file_path, 0o644)
                return jsonify({'success': True, 'file_path': file_path})
            except Exception as e:
                return jsonify({'success': False, 'message': f'Failed to save file: {str(e)}'})

        return jsonify({'success': False, 'message': f'Invalid file type for {file_type}. {"Allowed types: " + str(ALLOWED_RPM_EXTENSIONS) if file_type == "rpm" else "No restrictions for key files"}'})
    except Exception as e:
        return jsonify({'success': False, 'message': f'Server error: {str(e)}'})

@app.route('/verify_file')
def verify_file():
    file_path = request.args.get('file_path')
    if not file_path:
        return jsonify({'exists': False, 'message': 'No file path provided'})

    try:
        return jsonify({'exists': os.path.exists(file_path), 'file_path': file_path})
    except Exception as e:
        return jsonify({'exists': False, 'message': str(e)})

if __name__ == '__main__':
    if not os.path.exists('templates'):
        os.makedirs('templates')
    app.run(host='0.0.0.0', port=5000, debug=True)
