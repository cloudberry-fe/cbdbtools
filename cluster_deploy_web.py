from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, Response
import os
import re
import subprocess
import shutil
from datetime import datetime
import json
import time
import threading
import psutil
from werkzeug.utils import secure_filename  # 添加这行导入

app = Flask(__name__, static_folder='static')
app.secret_key = 'supersecretkey'

# 确保static目录存在
if not os.path.exists('static'):
    os.makedirs('static')
if not os.path.exists('static/js'):
    os.makedirs('static/js')

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

# New route to get deployment status
@app.route('/deployment_status')
def deployment_status():
    with DEPLOYMENT_LOCK:
        status = {
            'running': DEPLOYMENT_STATUS['running'],
            'log_file': DEPLOYMENT_STATUS['log_file'],
            'start_time': DEPLOYMENT_STATUS['start_time'],
            'success': DEPLOYMENT_STATUS.get('success', None)
        }
    return jsonify(status)

@app.route('/get_log_content')
def get_latest_log_file():
    """获取最新的日志文件"""
    log_files = [f for f in os.listdir('.') if f.startswith('deploy_cluster_') and f.endswith('.log')]
    if not log_files:
        return None
    return max(log_files, key=lambda f: os.path.getctime(f))

def get_log_content():
    last_position = request.args.get('last_position', '0')
    try:
        last_position = int(last_position)
    except ValueError:
        last_position = 0
    
    log_file = None
    with DEPLOYMENT_LOCK:
        # 如果当前没有正在运行的部署，尝试获取最新的日志文件
        if not DEPLOYMENT_STATUS['running']:
            latest_log = get_latest_log_file()
            if latest_log:
                log_file = os.path.abspath(latest_log)
        else:
            log_file = DEPLOYMENT_STATUS.get('log_file')

        # ✅ 统一调用 is_deployment_running()
        is_running = is_deployment_running()
        DEPLOYMENT_STATUS['running'] = is_running
    
    if not log_file or not os.path.exists(log_file):
        return jsonify({
            'content': 'Waiting for deployment to start...',
            'position': last_position,
            'eof': not is_running
        })
    
    try:
        with open(log_file, 'r') as f:
            f.seek(0, os.SEEK_END)
            file_size = f.tell()
            
            if last_position > file_size:
                last_position = 0
            
            f.seek(last_position)
            content = f.read()
            new_position = f.tell()
            
            app.logger.debug(f"Log read: position={last_position}, new_position={new_position}, content_length={len(content)}, is_running={is_running}")
            
            if not content and is_running:
                content = 'Waiting for new output...\n'
            
            return jsonify({
                'content': content,
                'position': new_position,
                'eof': not is_running,
                'file_size': file_size,
                'is_running': is_running
            })
    except Exception as e:
        app.logger.error(f"Error reading log file: {str(e)}")
        return jsonify({
            'error': f'Error reading log file: {str(e)}',
            'position': last_position,
            'eof': not is_running
        })

# New route for SSE log streaming
@app.route('/stream_logs')
def stream_logs():
    def generate():
        position = 0
        current_log_file = None

        while True:
            log_file = None
            is_running = is_deployment_running()
            with DEPLOYMENT_LOCK:
                # 优先使用当前部署的 log_file
                log_file = DEPLOYMENT_STATUS.get('log_file')
            
                # 如果没有正在运行的部署，也没有记录 log_file，再 fallback 到最新日志
                if not log_file and not DEPLOYMENT_STATUS['running']:
                    latest_log = get_latest_log_file()
                    log_file = os.path.abspath(latest_log) if latest_log else None

            if log_file != current_log_file:
                position = 0
                current_log_file = log_file
                app.logger.info(f"Switching to log file: {log_file}")

            # 没有日志文件
            if not log_file or not os.path.exists(log_file):
                yield 'data: {"content": "", "is_running": false}\n\n'
                break

            try:
                with open(log_file, 'r', encoding='utf-8', errors='replace') as f:
                    f.seek(0, os.SEEK_END)
                    file_size = f.tell()

                    if position > file_size:
                        position = 0

                    if file_size > position:
                        f.seek(position)
                        content = f.read()
                        position = f.tell()
                        if content:
                            yield f'data: {{"content": {json.dumps(content)}, "is_running": {str(is_running).lower()}, "position": {position}, "file_size": {file_size}}}\n\n'
                            continue

                if is_running:
                    # 部署中，继续等待新日志
                    yield f'data: {{"content": "", "is_running": true, "position": {position}, "file_size": {file_size}}}\n\n'
                    time.sleep(0.5)
                else:
                    # ✅ 额外确认：只有出现完成标志才真正结束
                    with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                        content_all = f.read()

                    if "Finished deploy cluster" in content_all:
                        yield f'data: {{"content": "", "is_running": false, "position": {position}, "file_size": {file_size}}}\n\n'
                        break
                    else:
                        # 没有完成标志 → 继续保持连接，避免误判
                        yield f'data: {{"content": "", "is_running": true, "position": {position}, "file_size": {file_size}}}\n\n'
                        time.sleep(0.5)

            except Exception as e:
                app.logger.error(f"Error reading log file: {e}")
                yield f'data: {{"content": "", "error": "Error reading log file", "is_running": {str(is_running).lower()}}}\n\n'
                if not is_running:
                    break
                time.sleep(1)

    return Response(generate(), mimetype='text/event-stream')

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
            # 确保路径存在
            if os.path.exists(params['SEGMENT_ACCESS_KEYFILE']):
                print(f'Using uploaded Key file: {params["SEGMENT_ACCESS_KEYFILE"]}')
            else:
                flash(f'Warning: Key file path does not exist: {params["SEGMENT_ACCESS_KEYFILE"]}')

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
        log_file = DEPLOYMENT_STATUS.get('log_file')

        try:
            for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
                try:
                    cmdline = ' '.join(proc.info['cmdline'] or [])
                    if 'deploycluster.sh' in cmdline or 'run.sh' in cmdline:
                        return True
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
    
            # 1. 检查完成标记（唯一可靠的成功信号）
            if log_file and os.path.exists(log_file):
                with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                if "Finished deploy cluster" in content:
                    DEPLOYMENT_STATUS['running'] = False
                    DEPLOYMENT_STATUS['success'] = True
                    return False

            # 2. 检查日志更新时间（主要依据）
            if log_file and os.path.exists(log_file):
                mtime = os.path.getmtime(log_file)
                if time.time() - mtime < 300:  # 5 分钟内更新
                    DEPLOYMENT_STATUS['running'] = True
                    return True

            # 3. 检查进程（辅助依据）
            for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
                try:
                    cmdline = ' '.join(proc.info['cmdline'] or [])
                    if 'deploycluster.sh' in cmdline or 'run.sh' in cmdline:
                        return True
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue

            # 4. 超过 5 分钟没更新 → 失败
            if log_file and os.path.exists(log_file):
                mtime = os.path.getmtime(log_file)
                if time.time() - mtime >= 300:
                    DEPLOYMENT_STATUS['running'] = False
                    DEPLOYMENT_STATUS['success'] = False
                    return False

            # ✅ 默认兜底：既没有完成标志，也没有日志更新/进程 → 认为不在运行
            DEPLOYMENT_STATUS['running'] = False
            return False

        except Exception as e:
            app.logger.error(f"Error checking deployment status: {e}")
            DEPLOYMENT_STATUS['running'] = False
            DEPLOYMENT_STATUS['success'] = False
            return False

# 修改start_background_deployment函数，使用绝对路径
def start_background_deployment(cluster_type='single'):
    global DEPLOYMENT_STATUS
    
    with DEPLOYMENT_LOCK:
#        _ = is_deployment_running()
        if DEPLOYMENT_STATUS['running']:
            return False, "Deployment is already running. Please wait for it to complete."
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        log_file = os.path.abspath(f'deploy_cluster_{timestamp}.log')
        
        # 创建日志文件并设置权限
        with open(log_file, 'w') as f:
            f.write(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Starting deployment...\n")
            f.flush()  # 确保内容被写入
        os.chmod(log_file, 0o666)
        
        DEPLOYMENT_STATUS.update({
            'running': True,
            'log_file': log_file,
            'start_time': time.time(),
            'pid': None,
            'success': None  # 重置成功状态
        })
    
    try:
        # 使用当前工作目录启动进程
        process = subprocess.Popen(
            ['sh', 'run.sh', cluster_type],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1,
            universal_newlines=True,
            cwd=os.getcwd()
        )
        
        if not process:
            raise Exception("Failed to start deployment process")
            
        # 更新进程PID
        with DEPLOYMENT_LOCK:
            DEPLOYMENT_STATUS['pid'] = process.pid
            app.logger.info(f"Started deployment process with PID: {process.pid}")
        
        def read_output(proc, log_path):
            app.logger.info(f"Starting to read output for process {proc.pid}")
            try:
                while True:
                    line = proc.stdout.readline()
                    if not line and proc.poll() is not None:
                        app.logger.info(f"Process {proc.pid} has ended, no more output")
                        break
                    if line:
                        try:
                            with open(log_path, 'a', encoding='utf-8', errors='ignore') as log:
                                timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                                log.write(f"[{timestamp}] {line}")
                                log.flush()
                                app.logger.debug(f"Wrote line to log: {line.strip()}")
                        except Exception as e:
                            app.logger.error(f"Error writing to log file: {str(e)}")

                # 写入退出码（仅日志记录，不改变状态）
                try:
                    with open(log_path, 'a', encoding='utf-8', errors='ignore') as log:
                        exit_code = proc.returncode
                        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                        log.write(f"\n[{timestamp}] Process exited with code: {exit_code}\n")
                        log.flush()
                        app.logger.info(f"Process {proc.pid} exited with code {exit_code}")
                except Exception as e:
                    app.logger.error(f"Error writing final status: {str(e)}")

            except Exception as e:
                app.logger.error(f"Error in read_output: {str(e)}")
        
        # 在新线程中读取输出
        output_thread = threading.Thread(
            target=read_output,
            args=(process, log_file),
            daemon=True
        )
        
        # 启动输出读取线程
        output_thread.start()
        
        # 返回成功信息
        return True, f"Deployment started successfully. Log file: {log_file}"
        
    except Exception as e:
        error_msg = f"Failed to start deployment: {str(e)}"
        app.logger.error(error_msg)
        
        # 更新状态为非运行
        with DEPLOYMENT_LOCK:
            DEPLOYMENT_STATUS['running'] = False
        
        # 记录错误到日志文件
        try:
            with open(log_file, 'a') as f:
                f.write(f"\n[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ERROR: {error_msg}\n")
        except:
            pass
        
        return False, error_msg

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