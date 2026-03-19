#!/usr/bin/env python3
"""
CBDB Cluster Deployment Web UI
A web-based interface for deploying Cloudberry/Greenplum/HashData clusters
Can run on any machine and connect to remote deployment servers via SSH
"""

from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, Response, session
import os
import re
import shlex
import threading
import time
import json
from datetime import datetime
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.secret_key = os.environ.get('FLASK_SECRET_KEY', os.urandom(32))
app.config['MAX_CONTENT_LENGTH'] = 2 * 1024 * 1024 * 1024  # 2GB max upload

# Path to the local config file
CONFIG_FILE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'deploycluster_parameter.sh')


def parse_config_file(config_path=None):
    """Parse deploycluster_parameter.sh and return a dict of exported variables."""
    if config_path is None:
        config_path = CONFIG_FILE_PATH
    config = {}
    if not os.path.isfile(config_path):
        return config
    export_pattern = re.compile(r'^export\s+([A-Za-z_][A-Za-z0-9_]*)=["\']?(.*?)["\']?\s*$')
    with open(config_path, 'r') as f:
        for line in f:
            line = line.strip()
            m = export_pattern.match(line)
            if m:
                config[m.group(1)] = m.group(2)
    return config

# Remote server configuration
REMOTE_CONFIG = {
    'host': '',
    'port': 22,
    'username': 'root',
    'password': '',
    'key_file': '',
    'deploy_path': '/opt/cbdbtools'
}

# Deployment status
DEPLOYMENT_STATUS = {
    'running': False,
    'success': None,
    'log_content': '',
    'start_time': None,
    'remote_log_file': None,
    'deploy_type': 'single'
}

DEPLOYMENT_LOCK = threading.RLock()

# Input validation patterns
IP_PATTERN = re.compile(r'^(\d{1,3}\.){3}\d{1,3}$')
HOSTNAME_PATTERN = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$')
PORT_PATTERN = re.compile(r'^\d{1,5}$')
PATH_PATTERN = re.compile(r'^/[a-zA-Z0-9_./-]+$')


def validate_ip(ip):
    """Validate IP address format"""
    if not ip or not IP_PATTERN.match(ip):
        return False
    parts = ip.split('.')
    return all(0 <= int(p) <= 255 for p in parts)


def validate_hostname(hostname):
    """Validate hostname format"""
    return bool(hostname and HOSTNAME_PATTERN.match(hostname))


def validate_port(port):
    """Validate port number"""
    try:
        p = int(port)
        return 1 <= p <= 65535
    except (ValueError, TypeError):
        return False


def validate_path(path):
    """Validate file path (basic safety check)"""
    if not path:
        return False
    # Block path traversal
    if '..' in path or '\0' in path:
        return False
    return PATH_PATTERN.match(path) is not None


def get_remote_connection():
    """Create SSH connection to remote server"""
    import paramiko

    if not REMOTE_CONFIG.get('host'):
        raise ValueError("Remote host not configured")

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    try:
        connect_kwargs = {
            'hostname': REMOTE_CONFIG['host'],
            'port': int(REMOTE_CONFIG['port']),
            'username': REMOTE_CONFIG['username'],
            'timeout': 30,
        }

        if REMOTE_CONFIG.get('key_file') and os.path.isfile(REMOTE_CONFIG['key_file']):
            import paramiko
            key = paramiko.RSAKey.from_private_key_file(REMOTE_CONFIG['key_file'])
            connect_kwargs['pkey'] = key
        else:
            connect_kwargs['password'] = REMOTE_CONFIG.get('password', '')

        ssh.connect(**connect_kwargs)
        return ssh
    except Exception as e:
        raise ConnectionError(f"SSH connection failed: {str(e)}")


def remote_exec(ssh, command, get_pty=False):
    """Execute command on remote server"""
    stdin, stdout, stderr = ssh.exec_command(command, get_pty=get_pty)
    return stdin, stdout, stderr


def check_remote_connection():
    """Check if remote connection is working"""
    try:
        ssh = get_remote_connection()
        stdin, stdout, stderr = remote_exec(ssh, 'echo "connected"')
        result = stdout.read().decode().strip()
        ssh.close()
        return result == "connected"
    except Exception:
        return False


def execute_remote_deployment():
    """Execute deployment on remote server in background thread"""
    global DEPLOYMENT_STATUS

    with DEPLOYMENT_LOCK:
        if DEPLOYMENT_STATUS['running']:
            return

        DEPLOYMENT_STATUS['running'] = True
        DEPLOYMENT_STATUS['success'] = None
        DEPLOYMENT_STATUS['log_content'] = ''
        DEPLOYMENT_STATUS['start_time'] = time.time()
        DEPLOYMENT_STATUS['remote_log_file'] = f'/tmp/cbdb_deploy_{int(time.time())}.log'

    log_file = DEPLOYMENT_STATUS['remote_log_file']

    try:
        ssh = get_remote_connection()

        deploy_type = DEPLOYMENT_STATUS.get('deploy_type', 'single')
        # Sanitize deploy_type to prevent command injection
        if deploy_type not in ('single', 'multi'):
            deploy_type = 'single'

        deploy_path = shlex.quote(REMOTE_CONFIG['deploy_path'])
        safe_log = shlex.quote(log_file)

        deploy_cmd = f'cd {deploy_path} && sh deploycluster.sh {deploy_type} >> {safe_log} 2>&1'

        log_msg = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Starting deployment on {REMOTE_CONFIG['host']}...\n"
        remote_exec(ssh, f'echo {shlex.quote(log_msg)} >> {safe_log}')

        # Run deployment in background
        remote_exec(ssh, f'nohup sh -c {shlex.quote(deploy_cmd)} > /dev/null 2>&1 &')

        # Monitor deployment
        monitor_deployment(ssh, log_file)

        ssh.close()

    except Exception as e:
        with DEPLOYMENT_LOCK:
            DEPLOYMENT_STATUS['log_content'] += f"\n[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Error: {str(e)}\n"
            DEPLOYMENT_STATUS['success'] = False
    finally:
        with DEPLOYMENT_LOCK:
            DEPLOYMENT_STATUS['running'] = False


def monitor_deployment(ssh, log_file):
    """Monitor deployment progress"""
    global DEPLOYMENT_STATUS

    check_count = 0
    max_checks = 3600  # 1 hour max
    safe_log = shlex.quote(log_file)

    while check_count < max_checks:
        check_count += 1

        try:
            # Check if deployment process is still running
            stdin, stdout, stderr = remote_exec(ssh, 'pgrep -f "deploycluster\\.sh" || true')
            process_output = stdout.read().decode().strip()

            # Get log content
            stdin2, stdout2, stderr2 = remote_exec(ssh, f'cat {safe_log} 2>/dev/null || echo ""')
            log_content = stdout2.read().decode()

            with DEPLOYMENT_LOCK:
                DEPLOYMENT_STATUS['log_content'] = log_content

            # If no process running, deployment finished
            if not process_output:
                time.sleep(2)  # Brief wait for final log writes

                # Read final log content
                stdin3, stdout3, stderr3 = remote_exec(ssh, f'cat {safe_log} 2>/dev/null || echo ""')
                log_content = stdout3.read().decode()

                with DEPLOYMENT_LOCK:
                    DEPLOYMENT_STATUS['log_content'] = log_content
                    if 'Finished deploy' in log_content or 'gpinitsystem completed' in log_content:
                        DEPLOYMENT_STATUS['success'] = True
                    elif 'Error' in log_content or 'FAILED' in log_content:
                        DEPLOYMENT_STATUS['success'] = False
                    else:
                        DEPLOYMENT_STATUS['success'] = True

                break

            time.sleep(2)

        except Exception as e:
            with DEPLOYMENT_LOCK:
                DEPLOYMENT_STATUS['log_content'] += f"\nError monitoring: {str(e)}\n"
            break

    with DEPLOYMENT_LOCK:
        DEPLOYMENT_STATUS['running'] = False


# ==================== Flask Routes ====================

def parse_segment_hosts(hosts_path=None):
    """Parse segmenthosts.conf and return list of (ip, hostname) tuples for segment hosts."""
    if hosts_path is None:
        hosts_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'segmenthosts.conf')
    segments = []
    if not os.path.isfile(hosts_path):
        return segments
    in_segment_section = False
    with open(hosts_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('##Segment hosts'):
                in_segment_section = True
                continue
            if line.startswith('#') or not line:
                if in_segment_section and line.startswith('#'):
                    break
                continue
            if in_segment_section:
                parts = line.split()
                if len(parts) >= 2:
                    segments.append((parts[0], parts[1]))
                elif len(parts) == 1:
                    segments.append((parts[0], ''))
    return segments


@app.route('/')
def index():
    """Main page"""
    file_config = parse_config_file()
    segment_hosts = parse_segment_hosts()
    return render_template('index.html',
                           remote_config=REMOTE_CONFIG,
                           deployment_status=DEPLOYMENT_STATUS,
                           file_config=file_config,
                           segment_hosts=segment_hosts)


@app.route('/test_connection', methods=['POST'])
def test_connection():
    """Test SSH connection to remote server"""
    global REMOTE_CONFIG

    host = request.form.get('host', '').strip()
    port = request.form.get('port', '22').strip()

    if not validate_ip(host) and not validate_hostname(host):
        return jsonify({'success': False, 'message': 'Invalid host address'})
    if not validate_port(port):
        return jsonify({'success': False, 'message': 'Invalid port number'})

    REMOTE_CONFIG['host'] = host
    REMOTE_CONFIG['port'] = int(port)
    REMOTE_CONFIG['username'] = request.form.get('username', 'root').strip()
    REMOTE_CONFIG['password'] = request.form.get('password', '')
    REMOTE_CONFIG['key_file'] = request.form.get('key_file', '').strip()

    # Handle key file upload
    key_file = request.files.get('key_file_upload')
    if key_file and key_file.filename:
        key_path = os.path.join('/tmp', secure_filename(key_file.filename))
        key_file.save(key_path)
        os.chmod(key_path, 0o600)
        REMOTE_CONFIG['key_file'] = key_path

    try:
        if check_remote_connection():
            return jsonify({'success': True, 'message': 'Connection successful!'})
        else:
            return jsonify({'success': False, 'message': 'Connection failed'})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)})


@app.route('/validate_rpm_path', methods=['POST'])
def validate_rpm_path():
    """Validate RPM file path on Coordinator server"""
    global REMOTE_CONFIG

    REMOTE_CONFIG['host'] = request.form.get('host', '').strip()
    REMOTE_CONFIG['port'] = int(request.form.get('port', 22))
    REMOTE_CONFIG['username'] = request.form.get('username', 'root').strip()
    REMOTE_CONFIG['password'] = request.form.get('password', '')

    key_file_text = request.form.get('key_file', '').strip()
    if key_file_text:
        REMOTE_CONFIG['key_file'] = key_file_text

    # Handle key file upload
    key_file = request.files.get('key_file_upload')
    if key_file and key_file.filename:
        key_path = os.path.join('/tmp', secure_filename(key_file.filename))
        key_file.save(key_path)
        os.chmod(key_path, 0o600)
        REMOTE_CONFIG['key_file'] = key_path

    rpm_path = request.form.get('rpm_path', '').strip()

    if not rpm_path:
        return jsonify({'valid': False, 'message': 'Please enter RPM path'})

    if not validate_path(rpm_path):
        return jsonify({'valid': False, 'message': 'Invalid path format'})

    try:
        ssh = get_remote_connection()
        safe_path = shlex.quote(rpm_path)

        stdin, stdout, stderr = remote_exec(ssh, f'test -f {safe_path} && echo "exists"')
        result = stdout.read().decode().strip()

        if result == 'exists':
            stdin, stdout, stderr = remote_exec(ssh, f'ls -lh {safe_path} 2>/dev/null')
            file_info = stdout.read().decode().strip()

            stdin, stdout, stderr = remote_exec(ssh, f'stat -c %s {safe_path} 2>/dev/null')
            file_size = stdout.read().decode().strip()

            ssh.close()

            return jsonify({
                'valid': True,
                'message': 'File exists',
                'file_info': file_info,
                'file_size': file_size
            })
        else:
            ssh.close()
            return jsonify({'valid': False, 'message': f'File not found: {rpm_path}'})

    except Exception as e:
        return jsonify({'valid': False, 'message': f'Validation failed: {str(e)}'})


@app.route('/save_config', methods=['POST'])
def save_config():
    """Save deployment configuration"""
    global REMOTE_CONFIG

    REMOTE_CONFIG['host'] = request.form.get('host', '').strip()
    REMOTE_CONFIG['port'] = int(request.form.get('port', 22))
    REMOTE_CONFIG['username'] = request.form.get('username', 'root').strip()
    REMOTE_CONFIG['password'] = request.form.get('password', '')
    REMOTE_CONFIG['key_file'] = request.form.get('key_file', '').strip()

    deploy_type = request.form.get('deploy_type', 'single')
    if deploy_type not in ('single', 'multi'):
        return jsonify({'success': False, 'message': 'Invalid deploy type'})

    session['deploy_type'] = deploy_type

    # Collect segment hosts for multi-node deployment
    segment_ips = []
    segment_hostnames = []

    if deploy_type == 'multi':
        for key, value in request.form.items():
            if key.startswith('SEGMENT_IP_'):
                idx = key.replace('SEGMENT_IP_', '')
                ip = value.strip()
                hostname = request.form.get(f'SEGMENT_HOSTNAME_{idx}', '').strip()
                if ip:
                    if not validate_ip(ip):
                        return jsonify({'success': False, 'message': f'Invalid segment IP: {ip}'})
                    if hostname and not validate_hostname(hostname):
                        return jsonify({'success': False, 'message': f'Invalid hostname: {hostname}'})
                    segment_ips.append(ip)
                    segment_hostnames.append(hostname or f'sdw{int(idx) + 1}')

    # Save deployment params
    deploy_params = {
        'ADMIN_USER': request.form.get('ADMIN_USER', 'gpadmin').strip(),
        'ADMIN_USER_PASSWORD': request.form.get('ADMIN_USER_PASSWORD', ''),
        'CLOUDBERRY_RPM': request.form.get('CLOUDBERRY_RPM', '').strip(),
        'COORDINATOR_HOSTNAME': request.form.get('COORDINATOR_HOSTNAME', 'mdw').strip(),
        'COORDINATOR_IP': request.form.get('COORDINATOR_IP', '').strip(),
        'COORDINATOR_PORT': request.form.get('COORDINATOR_PORT', '5432').strip(),
        'COORDINATOR_DIRECTORY': request.form.get('COORDINATOR_DIRECTORY', '/data0/database/coordinator').strip(),
        'DATA_DIRECTORY': request.form.get('DATA_DIRECTORY', '/data0/database/primary').strip(),
        'DEPLOY_TYPE': deploy_type,
        'WITH_MIRROR': request.form.get('WITH_MIRROR', 'false'),
    }

    if deploy_type == 'multi' and segment_ips:
        deploy_params['SEGMENT_IPS'] = ','.join(segment_ips)
        deploy_params['SEGMENT_HOSTNAMES'] = ','.join(segment_hostnames)
        deploy_params['SEGMENT_COUNT'] = str(len(segment_ips))
        deploy_params['SEGMENT_ACCESS_METHOD'] = request.form.get('SEGMENT_ACCESS_METHOD', 'password')
        deploy_params['SEGMENT_ACCESS_USER'] = request.form.get('SEGMENT_ACCESS_USER', 'root').strip()
        deploy_params['SEGMENT_ACCESS_PASSWORD'] = request.form.get('SEGMENT_ACCESS_PASSWORD', '')
        deploy_params['SEGMENT_ACCESS_KEYFILE'] = request.form.get('SEGMENT_ACCESS_KEYFILE', '').strip()

    session['deploy_params'] = deploy_params
    return jsonify({'success': True, 'message': 'Configuration saved!'})


@app.route('/upload_files', methods=['POST'])
def upload_files():
    """Upload RPM and key files to remote server"""
    global REMOTE_CONFIG

    host = request.form.get('host') or REMOTE_CONFIG.get('host')
    port = int(request.form.get('port') or REMOTE_CONFIG.get('port', 22))
    username = request.form.get('username') or REMOTE_CONFIG.get('username', 'root')
    password = request.form.get('password') or REMOTE_CONFIG.get('password', '')
    key_file = request.form.get('key_file') or REMOTE_CONFIG.get('key_file', '')

    REMOTE_CONFIG['host'] = host
    REMOTE_CONFIG['port'] = port
    REMOTE_CONFIG['username'] = username
    REMOTE_CONFIG['password'] = password
    REMOTE_CONFIG['key_file'] = key_file

    rpm_source = request.form.get('rpm_source', 'local')
    files_uploaded = []
    upload_errors = []

    if 'deploy_params' not in session:
        session['deploy_params'] = {}

    try:
        ssh = get_remote_connection()

        if rpm_source == 'upload':
            rpm_file = request.files.get('rpm_file')
            if rpm_file and rpm_file.filename:
                filename = secure_filename(rpm_file.filename)
                local_path = os.path.join('/tmp', filename)
                rpm_file.save(local_path)

                upload_dir = request.form.get('RPM_UPLOAD_PATH', '/root/').strip()
                if not validate_path(upload_dir.rstrip('/')):
                    ssh.close()
                    return jsonify({'success': False, 'message': 'Invalid upload path'})

                if upload_dir.endswith('/'):
                    remote_path = upload_dir + filename
                else:
                    remote_path = upload_dir

                sftp = ssh.open_sftp()
                sftp.put(local_path, remote_path)
                sftp.close()

                files_uploaded.append(f'RPM: {remote_path}')
                session['deploy_params']['CLOUDBERRY_RPM'] = remote_path

                os.remove(local_path)
            else:
                upload_errors.append('No RPM file selected')
        else:
            rpm_path = request.form.get('CLOUDBERRY_RPM', '').strip()
            if rpm_path:
                session['deploy_params']['CLOUDBERRY_RPM'] = rpm_path
                files_uploaded.append(f'RPM (local): {rpm_path}')

        # Handle SSH key file for coordinator access
        key_file_upload = request.files.get('key_file_upload')
        if key_file_upload and key_file_upload.filename:
            key_path = os.path.join('/tmp', secure_filename(key_file_upload.filename))
            key_file_upload.save(key_path)
            os.chmod(key_path, 0o600)
            files_uploaded.append(f'SSH key: {key_path}')

        # Handle Segment access key file
        segment_keyfile = request.files.get('segment_keyfile_upload')
        if segment_keyfile and segment_keyfile.filename:
            segment_key_path = os.path.join('/tmp', 'segment_' + secure_filename(segment_keyfile.filename))
            segment_keyfile.save(segment_key_path)
            os.chmod(segment_key_path, 0o600)

            remote_segment_key = '/root/segment_keyfile'
            sftp = ssh.open_sftp()
            sftp.put(segment_key_path, remote_segment_key)
            sftp.close()

            files_uploaded.append(f'Segment key: {remote_segment_key}')
            session['deploy_params']['SEGMENT_ACCESS_KEYFILE'] = remote_segment_key

        ssh.close()

        if upload_errors:
            return jsonify({
                'success': False,
                'message': '; '.join(upload_errors),
                'uploaded': files_uploaded
            })

        return jsonify({
            'success': True,
            'message': 'Files processed successfully',
            'uploaded': files_uploaded
        })

    except Exception as e:
        return jsonify({'success': False, 'message': str(e)})


@app.route('/deploy', methods=['POST'])
def deploy():
    """Start deployment on remote server"""
    global DEPLOYMENT_STATUS, REMOTE_CONFIG

    host = request.form.get('host') or REMOTE_CONFIG.get('host')
    port = int(request.form.get('port') or REMOTE_CONFIG.get('port', 22))
    username = request.form.get('username') or REMOTE_CONFIG.get('username', 'root')
    password = request.form.get('password') or REMOTE_CONFIG.get('password', '')
    key_file = request.form.get('key_file') or REMOTE_CONFIG.get('key_file', '')

    # Handle key file upload
    key_file_upload = request.files.get('key_file_upload')
    if key_file_upload and key_file_upload.filename:
        key_path = os.path.join('/tmp', secure_filename(key_file_upload.filename))
        key_file_upload.save(key_path)
        os.chmod(key_path, 0o600)
        key_file = key_path

    REMOTE_CONFIG['host'] = host
    REMOTE_CONFIG['port'] = port
    REMOTE_CONFIG['username'] = username
    REMOTE_CONFIG['password'] = password
    REMOTE_CONFIG['key_file'] = key_file

    if not host:
        return jsonify({'success': False, 'message': 'Please configure remote server first'})

    if DEPLOYMENT_STATUS.get('running', False):
        return jsonify({'success': False, 'message': 'Deployment already in progress'})

    rpm_source = request.form.get('rpm_source', 'local')
    rpm_path = request.form.get('CLOUDBERRY_RPM', '').strip()

    if not rpm_path:
        return jsonify({'success': False, 'message': 'Please specify RPM path'})

    if not validate_path(rpm_path):
        return jsonify({'success': False, 'message': 'Invalid RPM path format'})

    # Verify local file exists on Coordinator
    if rpm_source != 'upload':
        try:
            ssh = get_remote_connection()
            safe_path = shlex.quote(rpm_path)
            stdin, stdout, stderr = remote_exec(ssh, f'test -f {safe_path} && echo "exists"')
            result = stdout.read().decode().strip()
            ssh.close()
            if result != 'exists':
                return jsonify({'success': False, 'message': f'RPM file not found: {rpm_path}'})
        except Exception as e:
            return jsonify({'success': False, 'message': f'RPM validation failed: {str(e)}'})

    try:
        ssh = get_remote_connection()
        deploy_path = REMOTE_CONFIG['deploy_path']
        safe_deploy_path = shlex.quote(deploy_path)

        remote_exec(ssh, f'mkdir -p {safe_deploy_path}')

        # Upload deployment scripts
        script_dir = os.path.dirname(os.path.abspath(__file__))
        scripts = [
            'deploycluster.sh',
            'deploycluster_parameter.sh',
            'common.sh',
            'init_env.sh',
            'init_cluster.sh',
            'init_env_segment.sh',
            'run.sh',
            'multissh.sh',
            'multiscp.sh',
            'segmenthosts.conf',
            'sshpass-1.10.tar.gz',
        ]

        sftp = ssh.open_sftp()
        for script in scripts:
            local_path = os.path.join(script_dir, script)
            if os.path.exists(local_path):
                remote_path = f'{deploy_path}/{script}'
                sftp.put(local_path, remote_path)
        sftp.close()

        # Get config from session or form
        config_params = session.get('deploy_params', {})

        if not config_params:
            deploy_type = request.form.get('deploy_type', 'single')
            if deploy_type not in ('single', 'multi'):
                deploy_type = 'single'

            config_params = {
                'ADMIN_USER': request.form.get('ADMIN_USER', 'gpadmin').strip(),
                'ADMIN_USER_PASSWORD': request.form.get('ADMIN_USER_PASSWORD', ''),
                'CLOUDBERRY_RPM': rpm_path,
                'COORDINATOR_HOSTNAME': request.form.get('COORDINATOR_HOSTNAME', 'mdw').strip(),
                'COORDINATOR_IP': request.form.get('COORDINATOR_IP', '').strip(),
                'COORDINATOR_PORT': request.form.get('COORDINATOR_PORT', '5432').strip(),
                'COORDINATOR_DIRECTORY': request.form.get('COORDINATOR_DIRECTORY', '/data0/database/coordinator').strip(),
                'DATA_DIRECTORY': request.form.get('DATA_DIRECTORY', '/data0/database/primary').strip(),
                'DEPLOY_TYPE': deploy_type,
                'WITH_MIRROR': request.form.get('WITH_MIRROR', 'false'),
            }

            if deploy_type == 'multi':
                segment_ips = []
                segment_hostnames = []
                for key, value in request.form.items():
                    if key.startswith('SEGMENT_IP_'):
                        idx = key.replace('SEGMENT_IP_', '')
                        ip = value.strip()
                        hostname = request.form.get(f'SEGMENT_HOSTNAME_{idx}', '').strip()
                        if ip:
                            segment_ips.append(ip)
                            segment_hostnames.append(hostname or f'sdw{int(idx) + 1}')
                if segment_ips:
                    config_params['SEGMENT_IPS'] = ','.join(segment_ips)
                    config_params['SEGMENT_HOSTNAMES'] = ','.join(segment_hostnames)
                    config_params['SEGMENT_COUNT'] = str(len(segment_ips))

                config_params['SEGMENT_ACCESS_METHOD'] = request.form.get('SEGMENT_ACCESS_METHOD', 'password')
                config_params['SEGMENT_ACCESS_USER'] = request.form.get('SEGMENT_ACCESS_USER', 'root').strip()
                config_params['SEGMENT_ACCESS_PASSWORD'] = request.form.get('SEGMENT_ACCESS_PASSWORD', '')
                config_params['SEGMENT_ACCESS_KEYFILE'] = request.form.get('SEGMENT_ACCESS_KEYFILE', '').strip()
        else:
            config_params['CLOUDBERRY_RPM'] = rpm_path

        DEPLOYMENT_STATUS['deploy_type'] = config_params.get('DEPLOY_TYPE', 'single')
        DEPLOYMENT_STATUS['deploy_params'] = config_params

        config_content = generate_config_file(config_params)
        remote_config_path = f'{deploy_path}/deploycluster_parameter.sh'

        sftp = ssh.open_sftp()
        with sftp.file(remote_config_path, 'w') as remote_file:
            remote_file.write(config_content)

        # Upload hosts file if multi-node
        if config_params.get('DEPLOY_TYPE') == 'multi':
            hosts_content = generate_hosts_file(config_params)
            remote_hosts_path = f'{deploy_path}/segmenthosts.conf'
            with sftp.file(remote_hosts_path, 'w') as remote_file:
                remote_file.write(hosts_content)

        sftp.close()
        ssh.close()

        # Start deployment in background thread
        thread = threading.Thread(target=execute_remote_deployment)
        thread.daemon = True
        thread.start()

        return jsonify({
            'success': True,
            'log_file': DEPLOYMENT_STATUS.get('remote_log_file', '/tmp/cbdb_deploy.log')
        })

    except Exception as e:
        return jsonify({'success': False, 'message': str(e)})


def generate_config_file(params):
    """Generate configuration file content"""
    # Read the original config file to preserve defaults for variables not set by the web UI
    original_config = parse_config_file()

    # Defaults for internal variables required by init_cluster.sh and other scripts
    defaults = {
        'INIT_CONFIGFILE': '/tmp/gpinitsystem_config',
        'MACHINE_LIST_FILE': '/tmp/hostfile_gpinitsystem',
        'ARRAY_NAME': 'CBDB_SANDBOX',
        'SEG_PREFIX': 'gpseg',
        'PORT_BASE': '6000',
        'TRUSTED_SHELL': 'ssh',
        'CHECK_POINT_SEGMENTS': '8',
        'ENCODING': 'UNICODE',
        'DATABASE_NAME': 'gpadmin',
        'MIRROR_PORT_BASE': '7000',
        'MIRROR_DATA_DIRECTORY': '/data0/database/mirror /data0/database/mirror',
        'INSTALL_DB_SOFTWARE': 'true',
        'INIT_ENV_ONLY': 'false',
        'WITH_STANDBY': 'false',
        'MAUNAL_YUM_REPO': 'false',
        'TIMEZONE': 'Asia/Shanghai',
    }

    # Merge: defaults < original config file < web UI params
    merged = {}
    merged.update(defaults)
    merged.update(original_config)
    merged.update({k: v for k, v in params.items() if v})

    lines = [
        '#!/bin/bash',
        '# Auto-generated configuration file',
        f'# Generated at: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}',
        '',
    ]

    # Keys that should not be exported directly
    skip_keys = {'SEGMENT_IPS', 'SEGMENT_HOSTNAMES', 'SEGMENT_COUNT'}

    for key, value in merged.items():
        if value and key not in skip_keys:
            # Escape double quotes in values
            safe_value = str(value).replace('"', '\\"')
            lines.append(f'export {key}="{safe_value}"')

    deploy_type = merged.get('DEPLOY_TYPE', 'single')
    if deploy_type == 'multi':
        segment_ips = params.get('SEGMENT_IPS', '')
        segment_hostnames = params.get('SEGMENT_HOSTNAMES', '')

        if segment_ips:
            hostname_list = [h.strip() for h in segment_hostnames.split(',') if h.strip()]
            ip_list = [ip.strip() for ip in segment_ips.split(',') if ip.strip()]

            if not hostname_list:
                hostname_list = [f'sdw{i+1}' for i in range(len(ip_list))]

            segment_hosts = ','.join(hostname_list)
            lines.append(f'\n# Segment hosts for gpinitsystem')
            lines.append(f'export SEGMENT_HOSTS="{segment_hosts}"')

    # log_time function MUST be at the end - deploycluster.sh truncates
    # the file after "export -f log_time" and appends detected DB values
    lines.append('')
    lines.append('# Utility function for logging with timestamps')
    lines.append('function log_time() {')
    lines.append('  printf "[%s] %b\\n" "$(date \'+%Y-%m-%d %H:%M:%S\')" "$1"')
    lines.append('}')
    lines.append('export -f log_time')

    return '\n'.join(lines) + '\n'


def generate_hosts_file(params):
    """Generate hosts file content for multi-node deployment"""
    lines = [
        '##Define hosts used for Hashdata',
        '#Hashdata hosts begin',
    ]

    coord_ip = params.get('COORDINATOR_IP', '')
    coord_host = params.get('COORDINATOR_HOSTNAME', 'mdw')
    if coord_ip:
        lines.append(f'##Coordinator hosts')
        lines.append(f'{coord_ip} {coord_host}')

    lines.append('##Segment hosts')
    segment_ips = params.get('SEGMENT_IPS', '')
    segment_hostnames = params.get('SEGMENT_HOSTNAMES', '')

    ip_list = [ip.strip() for ip in segment_ips.split(',') if ip.strip()]
    hostname_list = [host.strip() for host in segment_hostnames.split(',') if host.strip()]

    for i, ip in enumerate(ip_list):
        hostname = hostname_list[i] if i < len(hostname_list) else f'sdw{i + 1}'
        lines.append(f'{ip} {hostname}')

    lines.append('#Hashdata hosts end')
    return '\n'.join(lines) + '\n'


@app.route('/deployment_status')
def deployment_status():
    """Get current deployment status"""
    with DEPLOYMENT_LOCK:
        return jsonify({
            'running': DEPLOYMENT_STATUS.get('running', False),
            'success': DEPLOYMENT_STATUS.get('success'),
            'log': DEPLOYMENT_STATUS.get('log_content', '')
        })


@app.route('/deployment_logs')
def deployment_logs():
    """Get deployment logs"""
    with DEPLOYMENT_LOCK:
        return jsonify({
            'logs': DEPLOYMENT_STATUS.get('log_content', ''),
            'running': DEPLOYMENT_STATUS.get('running', False),
            'success': DEPLOYMENT_STATUS.get('success')
        })


@app.route('/reset', methods=['POST'])
def reset():
    """Reset deployment status"""
    global DEPLOYMENT_STATUS

    with DEPLOYMENT_LOCK:
        DEPLOYMENT_STATUS = {
            'running': False,
            'success': None,
            'log_content': '',
            'start_time': None,
            'remote_log_file': None,
            'deploy_type': 'single',
            'deploy_params': {}
        }

    return jsonify({'success': True})


@app.route('/stream_logs')
def stream_logs():
    """Server-sent events for real-time log streaming"""
    def generate():
        last_pos = 0
        while True:
            with DEPLOYMENT_LOCK:
                log_content = DEPLOYMENT_STATUS.get('log_content', '')
                running = DEPLOYMENT_STATUS.get('running', False)

            if log_content and len(log_content) > last_pos:
                new_content = log_content[last_pos:]
                last_pos = len(log_content)
                yield f"data: {new_content}\n\n"

            if not running:
                yield f"data: [DONE]\n\n"
                break

            time.sleep(1)

    return Response(generate(), mimetype='text/event-stream')


if __name__ == '__main__':
    try:
        import paramiko
    except ImportError:
        print("Installing required package: paramiko")
        import subprocess
        subprocess.run(['pip', 'install', 'paramiko'], check=True)

    app.run(host='0.0.0.0', port=5000, debug=True, threaded=True)
