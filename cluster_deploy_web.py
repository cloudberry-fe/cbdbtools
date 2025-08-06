from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
import os
import re
import subprocess
import shutil
from datetime import datetime
import json

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
    result = deploy_cluster()
    if result['success']:
        flash('Cluster deployed successfully!')
    else:
        flash(f"Cluster deployment failed: {result.get('error', result.get('stderr', 'Unknown error'))}")
    return redirect(url_for('index'))

if __name__ == '__main__':
    # Ensure templates directory exists
    if not os.path.exists('templates'):
        os.makedirs('templates')
    # Start application
    app.run(host='0.0.0.0', port=5000, debug=True)