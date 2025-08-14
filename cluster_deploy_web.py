from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
import os
import re
import subprocess
import shutil
from datetime import datetime
import json
import time
import threading
from werkzeug.utils import secure_filename  # 添加这行导入

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
            coord_match = re.search(r'##Coordinator hosts
([\d.]+)\s+([\w-]+)', content)
            if coord_match:
                hosts['coordinator'] = [coord_match.group(1), coord_match.group(2)]
            
            # Extract segment hosts - 新的实现
            segment_section = re.search(r'##Segment hosts
((?:[\d.]+)\s+([\w-]+)
?)+', content)
            if segment_section:
                # 提取所有的segment host行
                segment_lines = re.findall(r'([\d.]+)\s+([\w-]+)', segment_section.group(0))
                for ip, hostname in segment_lines:
                    hosts['segments'].append([ip, hostname])
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
    # Add deployment_info to be passed to the template
    deployment_info = {
        'mode': params.get('DEPLOY_TYPE', 'single'),
        'coordinator': hosts.get('coordinator', []),
        'segment_hosts': hosts.get('segments', []),
        'running': False,
        'log_file': None,
        'start_time': None
    }
    
    # 获取当前部署状态
    with DEPLOYMENT_LOCK:
        deployment_info['running'] = DEPLOYMENT_STATUS['running']
        deployment_info['log_file'] = DEPLOYMENT_STATUS['log_file']
        deployment_info['start_time'] = DEPLOYMENT_STATUS['start_time']
    
    return render_template('index.html', params=params, hosts=hosts, deployment_info=deployment_info)

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
        return jsonify({
            'success': False,
            'message': 'Deployment is already running. Please wait for it to complete or check the logs for progress.'
        })
    
    # Get deployment type
    params = read_parameters()
    deploy_type = params.get('DEPLOY_TYPE', 'single')
    
    # Start background deployment
    success, message = start_background_deployment(deploy_type)
    
    if success:
        # 从message中提取日志文件名
        log_file = message.split(': ')[-1] if ': ' in message else ''
        # 返回JSON响应包含日志文件绝对路径
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

    if deployment_success:
        flash(f'Deployment started successfully!')
        # 移除错误的函数调用
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
            'start_time': DEPLOYMENT_STATUS['start_time'],
            'success': DEPLOYMENT_STATUS['success']  # 返回成功状态
        })

# New route to get deployment logs
@app.route('/deployment_logs')
def deployment_logs():
    log_content = get_deployment_log()
    return jsonify({'logs': log_content})

@app.route('/save_params', methods=['POST'])
def save_params():
    try:
        # 获取表单数据
        params = request.form.to_dict()

        # 如果有上传的RPM文件路径，使用上传的路径
        if 'CLOUDBERRY_RPM' in params and params['CLOUDBERRY_RPM']:
            # 确保路径存在
            if os.path.exists(params['CLOUDBERRY_RPM']):
                print(f'Using uploaded RPM file: {params["CLOUDBERRY_RPM"]}')
            else:
                flash(f'Warning: RPM file path does not exist: {params["CLOUDBERRY_RPM"]}')

        # 如果有上传的Key文件路径，使用上传的路径
        if 'SEGMENT_ACCESS_KEYFILE' in params and params['SEGMENT_ACCESS_KEYFILE']:
            # 只在多机模式且Segment Access Method为KeyFile时检查keyfile
            deploy_type = params.get('DEPLOY_TYPE', 'single')
            segment_access_method = params.get('SEGMENT_ACCESS_METHOD', '')
            if deploy_type == 'multi' and segment_access_method == 'keyfile':
                # 确保路径存在
                if os.path.exists(params['SEGMENT_ACCESS_KEYFILE']):
                    print(f'Using uploaded Key file: {params["SEGMENT_ACCESS_KEYFILE"]}')
                else:
                    flash(f'Warning: Key file path does not exist: {params["SEGMENT_ACCESS_KEYFILE"]}')
            else:
                print(f'Skipping key file check for {deploy_type} deployment with {segment_access_method} access')

        # 保存参数
        save_parameters(params)
        flash('Configuration parameters saved successfully!')

        # 获取部署类型以确定重定向目标
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

# New route to get deployment parameters
@app.route('/get_deployment_params')
def get_deployment_params():
    params = read_parameters()
    hosts = read_hosts()
    
    # Process data directories for mirror information
    data_dirs = params.get('DATA_DIRECTORY', '').split() if params.get('DATA_DIRECTORY') else []
    mirror_dirs = params.get('MIRROR_DATA_DIRECTORY', '').split() if params.get('MIRROR_DATA_DIRECTORY') else []
    
    return jsonify({
        'params': params,
        'hosts': hosts,
        'data_dirs': data_dirs,
        'mirror_dirs': mirror_dirs
    })

# 文件上传配置
UPLOAD_FOLDER = '/tmp/uploads'
ALLOWED_RPM_EXTENSIONS = {'rpm'}

# 确保上传目录存在
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# 检查文件扩展名
def allowed_file(filename, file_type):
    if file_type == 'rpm':
        return '.' in filename and \
               filename.rsplit('.', 1)[1].lower() in ALLOWED_RPM_EXTENSIONS
    elif file_type == 'key':
        # 移除key文件的扩展名验证，允许任何格式的文件
        return True
    return False

# 文件上传路由
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
            # 确保上传目录存在且有正确权限
            os.makedirs(upload_path, exist_ok=True)
            os.chmod(upload_path, 0o755)
            
            filename = secure_filename(file.filename)
            file_path = os.path.join(upload_path, filename)
            
            # 保存文件并捕获可能的错误
            try:
                file.save(file_path)
                # 确保文件有正确权限
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
    # Ensure templates directory exists
    if not os.path.exists('templates'):
        os.makedirs('templates')
    # Start application
    app.run(host='0.0.0.0', port=5000, debug=True)


# Global variable to track deployment status
DEPLOYMENT_STATUS = {
    'running': False,
    'log_file': None,
    'start_time': None,
    'pid': None,
    'success': None  # 新增：跟踪部署是否成功
}

# Lock for thread safety
DEPLOYMENT_LOCK = threading.Lock()

# Function to check if there's a running deployment process
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

# 修改start_background_deployment函数，使用绝对路径
def start_background_deployment(cluster_type='single'):
    global DEPLOYMENT_STATUS
    
    with DEPLOYMENT_LOCK:
        if DEPLOYMENT_STATUS['running']:
            return False, "Deployment is already running. Please wait for it to complete."
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        # 使用绝对路径生成日志文件
        log_file = os.path.abspath(f'deploy_cluster_{timestamp}.log')
        
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
        
        def monitor_process(process, log_file):
            process.wait()
            with DEPLOYMENT_LOCK:
                DEPLOYMENT_STATUS['running'] = False
                # 检查部署是否成功
                try:
                    with open(log_file, 'r') as f:
                        log_content = f.read()
                        # 根据日志内容判断部署是否成功
                        # 更新判断条件以匹配实际日志输出
                        DEPLOYMENT_STATUS['success'] = ('deployment completed successfully' in log_content.lower() or 
                                                       'finished deploy cluster' in log_content.lower())
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
def get_deployment_log(log_file=None, lines=100):
    if not log_file:
        with DEPLOYMENT_LOCK:
            log_file = DEPLOYMENT_STATUS['log_file']
    
    # 检查日志文件是否存在
    if not log_file:
        return "No log file specified."
    
    if not os.path.exists(log_file):
        return f"Log file not found: {log_file}"
    
    try:
        with open(log_file, 'r') as f:
            # Read last N lines
            lines_content = f.readlines()
            if len(lines_content) > lines:
                lines_content = lines_content[-lines:]
            return ''.join(lines_content)
    except Exception as e:
        return f"Error reading log file: {str(e)}"