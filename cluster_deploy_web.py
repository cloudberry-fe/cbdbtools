from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
import os
import re
import subprocess

app = Flask(__name__)
app.secret_key = 'supersecretkey'

# 配置文件路径
PARAM_FILE = 'deploycluster_parameter.sh'
HOSTS_FILE = 'segmenthosts.conf'

# 读取配置参数
def read_parameters():
    params = {}
    if os.path.exists(PARAM_FILE):
        with open(PARAM_FILE, 'r') as f:
            content = f.read()
            # 提取export变量
            for line in content.split('\n'):
                if line.startswith('export '):
                    parts = line[7:].split('=', 1)
                    if len(parts) == 2:
                        key = parts[0].strip()
                        value = parts[1].strip().strip('"\'')
                        params[key] = value
    return params

# 保存配置参数
def save_parameters(params):
    with open(PARAM_FILE, 'w') as f:
        f.write('## Mandatory options\n')
        for key, value in params.items():
            f.write(f'export {key}="{value}"\n')
        # 添加日志函数
        f.write('\n# Utility function for logging with timestamps\n')
        f.write('function log_time() {\n')
        f.write('  printf "[%s] %b\n" "$(date \'+%Y-%m-%d %H:%M:%S\')" "$1"\n')
        f.write('}\n')
        f.write('export -f log_time\n')

# 读取主机配置
def read_hosts():
    hosts = {'coordinator': [], 'segments': []}
    if os.path.exists(HOSTS_FILE):
        with open(HOSTS_FILE, 'r') as f:
            content = f.read()
            # 提取协调器主机
            coord_match = re.search(r'##Coordinator hosts\n([\d.]+)\s+([\w-]+)', content)
            if coord_match:
                hosts['coordinator'] = [coord_match.group(1), coord_match.group(2)]
            # 提取段主机
            segment_matches = re.findall(r'##Segment hosts\n([\d.]+)\s+([\w-]+)\n([\d.]+)\s+([\w-]+)', content)
            if segment_matches:
                for match in segment_matches:
                    hosts['segments'].append([match[0], match[1]])
                    hosts['segments'].append([match[2], match[3]])
            else:
                # 尝试匹配单个段主机
                single_segment = re.search(r'##Segment hosts\n([\d.]+)\s+([\w-]+)', content)
                if single_segment:
                    hosts['segments'].append([single_segment.group(1), single_segment.group(2)])
    return hosts

# 保存主机配置
def save_hosts(hosts):
    with open(HOSTS_FILE, 'w') as f:
        f.write('##Define hosts used for Hashdata

')
        f.write('#Hashdata hosts begin
')
        f.write('##Coordinator hosts
')
        if hosts['coordinator']:
            f.write(f"{hosts['coordinator'][0]} {hosts['coordinator'][1]}\n")
        f.write('##Segment hosts
')
        for segment in hosts['segments']:
            f.write(f"{segment[0]} {segment[1]}\n")
        f.write('#Hashdata hosts end
')

# 部署集群
def deploy_cluster():
    try:
        # 运行部署脚本
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
        # 保存参数
        params = request.form.to_dict()
        save_parameters(params)
        # 保存主机
        hosts = {
            'coordinator': [request.form.get('coord_ip'), request.form.get('coord_hostname')],
            'segments': []
        }
        # 提取段主机
        segment_count = int(request.form.get('segment_count', 0))
        for i in range(segment_count):
            ip = request.form.get(f'segment_ip_{i}')
            hostname = request.form.get(f'segment_hostname_{i}')
            if ip and hostname:
                hosts['segments'].append([ip, hostname])
        save_hosts(hosts)
        flash('配置已保存成功！')
        return redirect(url_for('index'))
    except Exception as e:
        flash(f'保存配置时出错: {str(e)}')
        return redirect(url_for('index'))

@app.route('/deploy', methods=['POST'])
def deploy():
    result = deploy_cluster()
    if result['success']:
        flash('集群部署成功！')
    else:
        flash(f'集群部署失败: {result.get('error', result.get('stderr', '未知错误'))}')
    return redirect(url_for('index'))

if __name__ == '__main__':
    # 确保templates目录存在
    if not os.path.exists('templates'):
        os.makedirs('templates')
    # 启动应用
    app.run(host='0.0.0.0', port=5000, debug=True)