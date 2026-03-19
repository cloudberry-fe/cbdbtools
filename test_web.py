#!/usr/bin/env python3
"""
Tests for cluster_deploy_web.py
Covers: input validation, config generation, config parsing, hosts file generation,
        route behavior, and tab workflow logic.
"""

import os
import sys
import json
import tempfile
import textwrap

import pytest

# Ensure project root is on path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cluster_deploy_web import (
    app,
    parse_config_file,
    generate_config_file,
    generate_hosts_file,
    parse_segment_hosts,
    validate_ip,
    validate_hostname,
    validate_port,
    validate_path,
    REMOTE_CONFIG,
    DEPLOYMENT_STATUS,
)


# ====================== Fixtures ======================

@pytest.fixture
def client():
    """Flask test client with session support."""
    app.config['TESTING'] = True
    app.config['SECRET_KEY'] = 'test-secret'
    with app.test_client() as c:
        yield c


@pytest.fixture
def sample_params():
    """Minimal valid deployment parameters from web UI."""
    return {
        'ADMIN_USER': 'gpadmin',
        'ADMIN_USER_PASSWORD': 'Test@1234',
        'CLOUDBERRY_RPM': '/root/cloudberry-db-1.6.0.rpm',
        'COORDINATOR_HOSTNAME': 'mdw',
        'COORDINATOR_IP': '192.168.1.100',
        'COORDINATOR_PORT': '5432',
        'COORDINATOR_DIRECTORY': '/data0/database/coordinator',
        'DATA_DIRECTORY': '/data0/database/primary',
        'DEPLOY_TYPE': 'single',
        'WITH_MIRROR': 'false',
    }


@pytest.fixture
def multi_params(sample_params):
    """Multi-node deployment parameters."""
    sample_params.update({
        'DEPLOY_TYPE': 'multi',
        'SEGMENT_IPS': '192.168.1.101,192.168.1.102',
        'SEGMENT_HOSTNAMES': 'sdw1,sdw2',
        'SEGMENT_ACCESS_METHOD': 'password',
        'SEGMENT_ACCESS_USER': 'root',
        'SEGMENT_ACCESS_PASSWORD': 'SegPass@123',
    })
    return sample_params


@pytest.fixture
def tmp_config_file():
    """Create a temporary deploycluster_parameter.sh for testing."""
    content = textwrap.dedent("""\
        export ADMIN_USER="gpadmin"
        export ADMIN_USER_PASSWORD="FromFile@123"
        export CLOUDBERRY_RPM="/root/test.rpm"
        export COORDINATOR_HOSTNAME="mdw"
        export COORDINATOR_IP="10.0.0.1"
        export DEPLOY_TYPE="single"
        export COORDINATOR_PORT="5432"
        export COORDINATOR_DIRECTORY="/data0/coordinator"
        export DATA_DIRECTORY="/data0/primary /data0/primary"
        export INIT_CONFIGFILE="/tmp/gpinitsystem_config"
        export MACHINE_LIST_FILE="/tmp/hostfile_gpinitsystem"
        export ARRAY_NAME="TEST_CLUSTER"
        export SEG_PREFIX="gpseg"
        export PORT_BASE="6000"
        export TRUSTED_SHELL="ssh"
        export CHECK_POINT_SEGMENTS="8"
        export ENCODING="UNICODE"
        export DATABASE_NAME="gpadmin"

        # Utility function for logging with timestamps
        function log_time() {
          printf "[%s] %b\\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
        }
        export -f log_time
    """)
    fd, path = tempfile.mkstemp(suffix='.sh')
    with os.fdopen(fd, 'w') as f:
        f.write(content)
    yield path
    os.unlink(path)


@pytest.fixture
def tmp_hosts_file():
    """Create a temporary segmenthosts.conf for testing."""
    content = textwrap.dedent("""\
        ##Define hosts used for Hashdata
        #Hashdata hosts begin
        ##Coordinator hosts
        10.0.0.1 mdw
        ##Segment hosts
        10.0.0.2 sdw1
        10.0.0.3 sdw2
        10.0.0.4 sdw3
        #Hashdata hosts end
    """)
    fd, path = tempfile.mkstemp(suffix='.conf')
    with os.fdopen(fd, 'w') as f:
        f.write(content)
    yield path
    os.unlink(path)


# ====================== 1. Input Validation ======================

class TestValidateIP:
    def test_valid_ips(self):
        assert validate_ip('192.168.1.1')
        assert validate_ip('10.0.0.1')
        assert validate_ip('255.255.255.255')
        assert validate_ip('0.0.0.0')

    def test_invalid_ips(self):
        assert not validate_ip('')
        assert not validate_ip('256.1.1.1')
        assert not validate_ip('192.168.1')
        assert not validate_ip('abc.def.ghi.jkl')
        assert not validate_ip('192.168.1.1.1')
        assert not validate_ip(None)


class TestValidateHostname:
    def test_valid_hostnames(self):
        assert validate_hostname('mdw')
        assert validate_hostname('sdw1')
        assert validate_hostname('my-host.domain.com')
        assert validate_hostname('a')

    def test_invalid_hostnames(self):
        assert not validate_hostname('')
        assert not validate_hostname(None)
        assert not validate_hostname('-starts-with-dash')
        assert not validate_hostname('a' * 64)  # too long


class TestValidatePort:
    def test_valid_ports(self):
        assert validate_port(22)
        assert validate_port('5432')
        assert validate_port(1)
        assert validate_port(65535)

    def test_invalid_ports(self):
        assert not validate_port(0)
        assert not validate_port(65536)
        assert not validate_port('abc')
        assert not validate_port('')
        assert not validate_port(None)


class TestValidatePath:
    def test_valid_paths(self):
        assert validate_path('/root/test.rpm')
        assert validate_path('/data0/database/primary')
        assert validate_path('/usr/local/cloudberry-db')

    def test_invalid_paths(self):
        assert not validate_path('')
        assert not validate_path(None)
        assert not validate_path('../etc/passwd')
        assert not validate_path('/root/../etc/passwd')
        assert not validate_path('relative/path')
        assert not validate_path('/path/with spaces')  # blocked by pattern


# ====================== 2. Config File Parsing ======================

class TestParseConfigFile:
    def test_parse_valid_config(self, tmp_config_file):
        config = parse_config_file(tmp_config_file)
        assert config['ADMIN_USER'] == 'gpadmin'
        assert config['ADMIN_USER_PASSWORD'] == 'FromFile@123'
        assert config['COORDINATOR_PORT'] == '5432'
        assert config['ARRAY_NAME'] == 'TEST_CLUSTER'

    def test_parse_nonexistent_file(self):
        config = parse_config_file('/nonexistent/path.sh')
        assert config == {}

    def test_parse_ignores_comments_and_functions(self, tmp_config_file):
        config = parse_config_file(tmp_config_file)
        # Should not parse function definitions or non-export lines
        assert 'log_time' not in config
        assert 'printf' not in str(config.keys())


class TestParseSegmentHosts:
    def test_parse_valid_hosts(self, tmp_hosts_file):
        segments = parse_segment_hosts(tmp_hosts_file)
        assert len(segments) == 3
        assert segments[0] == ('10.0.0.2', 'sdw1')
        assert segments[1] == ('10.0.0.3', 'sdw2')
        assert segments[2] == ('10.0.0.4', 'sdw3')

    def test_parse_nonexistent_file(self):
        segments = parse_segment_hosts('/nonexistent/path.conf')
        assert segments == []


# ====================== 3. Config File Generation ======================

class TestGenerateConfigFile:
    def test_contains_all_required_variables(self, sample_params):
        """The generated config must include all variables needed by init_cluster.sh."""
        content = generate_config_file(sample_params)
        required_vars = [
            'INIT_CONFIGFILE', 'MACHINE_LIST_FILE', 'ARRAY_NAME',
            'SEG_PREFIX', 'PORT_BASE', 'TRUSTED_SHELL',
            'CHECK_POINT_SEGMENTS', 'ENCODING', 'DATABASE_NAME',
        ]
        for var in required_vars:
            assert f'export {var}=' in content, f'Missing required variable: {var}'

    def test_log_time_at_end(self, sample_params):
        """log_time function MUST be at the end; deploycluster.sh truncates after it."""
        content = generate_config_file(sample_params)
        lines = content.strip().split('\n')

        # Find position of export -f log_time
        log_time_idx = None
        for i, line in enumerate(lines):
            if line.strip() == 'export -f log_time':
                log_time_idx = i
                break

        assert log_time_idx is not None, 'export -f log_time not found'

        # All export KEY=VALUE lines must be before export -f log_time
        for i, line in enumerate(lines):
            if line.startswith('export ') and '=' in line and i > log_time_idx:
                pytest.fail(f'Export line after log_time at line {i}: {line}')

    def test_user_params_override_defaults(self, sample_params):
        """Web UI params should override built-in defaults."""
        content = generate_config_file(sample_params)
        assert 'export COORDINATOR_PORT="5432"' in content
        assert 'export ADMIN_USER="gpadmin"' in content

    def test_multi_node_generates_segment_hosts(self, multi_params):
        """Multi-node config should include SEGMENT_HOSTS."""
        content = generate_config_file(multi_params)
        assert 'export SEGMENT_HOSTS="sdw1,sdw2"' in content

    def test_multi_node_auto_generates_hostnames(self, sample_params):
        """When hostnames are empty, auto-generate sdw1, sdw2, etc."""
        sample_params['DEPLOY_TYPE'] = 'multi'
        sample_params['SEGMENT_IPS'] = '10.0.0.2,10.0.0.3,10.0.0.4'
        sample_params['SEGMENT_HOSTNAMES'] = ''
        content = generate_config_file(sample_params)
        assert 'export SEGMENT_HOSTS="sdw1,sdw2,sdw3"' in content

    def test_single_node_no_segment_hosts(self, sample_params):
        """Single-node config should not have SEGMENT_HOSTS."""
        content = generate_config_file(sample_params)
        assert 'SEGMENT_HOSTS' not in content

    def test_skip_keys_not_exported(self, multi_params):
        """SEGMENT_IPS, SEGMENT_HOSTNAMES, SEGMENT_COUNT should not be exported."""
        content = generate_config_file(multi_params)
        assert 'export SEGMENT_IPS=' not in content
        assert 'export SEGMENT_HOSTNAMES=' not in content
        assert 'export SEGMENT_COUNT=' not in content

    def test_empty_values_not_exported(self, sample_params):
        """Parameters with empty values should be skipped."""
        sample_params['EMPTY_PARAM'] = ''
        content = generate_config_file(sample_params)
        assert 'EMPTY_PARAM' not in content

    def test_special_characters_escaped(self, sample_params):
        """Double quotes in values should be escaped."""
        sample_params['ADMIN_USER_PASSWORD'] = 'pass"word'
        content = generate_config_file(sample_params)
        assert 'pass\\"word' in content

    def test_valid_bash_syntax(self, sample_params):
        """Generated file must start with shebang and be valid structure."""
        content = generate_config_file(sample_params)
        assert content.startswith('#!/bin/bash\n')


# ====================== 4. Hosts File Generation ======================

class TestGenerateHostsFile:
    def test_basic_structure(self, multi_params):
        content = generate_hosts_file(multi_params)
        assert '##Coordinator hosts' in content
        assert '##Segment hosts' in content
        assert '#Hashdata hosts end' in content

    def test_coordinator_entry(self, multi_params):
        content = generate_hosts_file(multi_params)
        assert '192.168.1.100 mdw' in content

    def test_segment_entries(self, multi_params):
        content = generate_hosts_file(multi_params)
        assert '192.168.1.101 sdw1' in content
        assert '192.168.1.102 sdw2' in content

    def test_auto_hostnames_when_empty(self):
        params = {
            'COORDINATOR_IP': '10.0.0.1',
            'COORDINATOR_HOSTNAME': 'mdw',
            'SEGMENT_IPS': '10.0.0.2,10.0.0.3',
            'SEGMENT_HOSTNAMES': '',
        }
        content = generate_hosts_file(params)
        assert '10.0.0.2 sdw1' in content
        assert '10.0.0.3 sdw2' in content


# ====================== 5. Route Tests ======================

class TestIndexRoute:
    def test_index_returns_200(self, client):
        resp = client.get('/')
        assert resp.status_code == 200

    def test_index_contains_tabs(self, client):
        resp = client.get('/')
        html = resp.data.decode()
        assert 'data-tab="connection"' in html
        assert 'data-tab="config"' in html
        assert 'data-tab="deploy"' in html

    def test_index_tab_names(self, client):
        """Tab names should match the designed workflow."""
        resp = client.get('/')
        html = resp.data.decode()
        assert 'Coordinator' in html  # Tab 1
        assert '集群配置' in html       # Tab 2
        assert '执行部署' in html       # Tab 3


class TestTestConnectionRoute:
    def test_invalid_host_rejected(self, client):
        resp = client.post('/test_connection', data={
            'host': 'not a valid host!!!',
            'port': '22',
            'username': 'root',
            'password': 'pass',
        })
        data = json.loads(resp.data)
        assert not data['success']
        assert 'Invalid' in data['message']

    def test_invalid_port_rejected(self, client):
        resp = client.post('/test_connection', data={
            'host': '192.168.1.1',
            'port': '99999',
            'username': 'root',
            'password': 'pass',
        })
        data = json.loads(resp.data)
        assert not data['success']
        assert 'Invalid port' in data['message']


class TestValidateRpmPathRoute:
    def test_empty_path_rejected(self, client):
        resp = client.post('/validate_rpm_path', data={
            'host': '192.168.1.1',
            'port': '22',
            'username': 'root',
            'password': 'pass',
            'rpm_path': '',
        })
        data = json.loads(resp.data)
        assert not data['valid']

    def test_path_traversal_rejected(self, client):
        resp = client.post('/validate_rpm_path', data={
            'host': '192.168.1.1',
            'port': '22',
            'username': 'root',
            'password': 'pass',
            'rpm_path': '/root/../etc/shadow',
        })
        data = json.loads(resp.data)
        assert not data['valid']
        assert 'Invalid' in data['message']


class TestSaveConfigRoute:
    def test_save_config_returns_json(self, client):
        resp = client.post('/save_config', data={
            'host': '192.168.1.1',
            'port': '22',
            'username': 'root',
            'password': 'pass',
            'deploy_type': 'single',
            'ADMIN_USER': 'gpadmin',
            'ADMIN_USER_PASSWORD': 'Test@123',
            'CLOUDBERRY_RPM': '/root/test.rpm',
            'COORDINATOR_HOSTNAME': 'mdw',
            'COORDINATOR_IP': '192.168.1.1',
            'COORDINATOR_PORT': '5432',
            'COORDINATOR_DIRECTORY': '/data0/coordinator',
            'DATA_DIRECTORY': '/data0/primary',
            'WITH_MIRROR': 'false',
        })
        data = json.loads(resp.data)
        assert data['success']

    def test_invalid_deploy_type_rejected(self, client):
        resp = client.post('/save_config', data={
            'host': '192.168.1.1',
            'port': '22',
            'username': 'root',
            'password': 'pass',
            'deploy_type': 'invalid_type',
        })
        data = json.loads(resp.data)
        assert not data['success']
        assert 'Invalid' in data['message']

    def test_invalid_segment_ip_rejected(self, client):
        resp = client.post('/save_config', data={
            'host': '192.168.1.1',
            'port': '22',
            'username': 'root',
            'password': 'pass',
            'deploy_type': 'multi',
            'SEGMENT_IP_0': '999.999.999.999',
            'SEGMENT_HOSTNAME_0': 'sdw1',
        })
        data = json.loads(resp.data)
        assert not data['success']
        assert 'Invalid segment IP' in data['message']


class TestDeployRoute:
    def test_deploy_without_host_rejected(self, client):
        """Deploy should fail if no remote host configured."""
        # Reset REMOTE_CONFIG
        REMOTE_CONFIG['host'] = ''
        resp = client.post('/deploy', data={
            'CLOUDBERRY_RPM': '/root/test.rpm',
            'rpm_source': 'local',
        })
        data = json.loads(resp.data)
        assert not data['success']
        assert 'configure' in data['message'].lower() or 'server' in data['message'].lower()

    def test_deploy_without_rpm_rejected(self, client):
        resp = client.post('/deploy', data={
            'host': '192.168.1.1',
            'port': '22',
            'username': 'root',
            'password': 'pass',
            'CLOUDBERRY_RPM': '',
        })
        data = json.loads(resp.data)
        assert not data['success']
        assert 'RPM' in data['message']

    def test_deploy_invalid_rpm_path_rejected(self, client):
        resp = client.post('/deploy', data={
            'host': '192.168.1.1',
            'port': '22',
            'username': 'root',
            'password': 'pass',
            'CLOUDBERRY_RPM': '../etc/shadow',
            'rpm_source': 'local',
        })
        data = json.loads(resp.data)
        assert not data['success']


class TestDeploymentStatusRoute:
    def test_deployment_status_returns_json(self, client):
        resp = client.get('/deployment_status')
        data = json.loads(resp.data)
        assert 'running' in data
        assert 'success' in data

    def test_deployment_logs_returns_json(self, client):
        resp = client.get('/deployment_logs')
        data = json.loads(resp.data)
        assert 'logs' in data
        assert 'running' in data


class TestResetRoute:
    def test_reset_clears_status(self, client):
        resp = client.post('/reset')
        data = json.loads(resp.data)
        assert data['success']

        status_resp = client.get('/deployment_status')
        status = json.loads(status_resp.data)
        assert not status['running']
        assert status['success'] is None


# ====================== 6. Config Merge Priority ======================

class TestConfigMergePriority:
    """Verify: built-in defaults < original config file < web UI params."""

    def test_defaults_used_when_no_file_and_no_param(self, sample_params, tmp_path):
        """When a variable is not in the file or params, use built-in default."""
        # Use empty config file
        empty = tmp_path / 'empty.sh'
        empty.write_text('')

        import cluster_deploy_web
        orig = cluster_deploy_web.CONFIG_FILE_PATH
        cluster_deploy_web.CONFIG_FILE_PATH = str(empty)
        try:
            content = generate_config_file(sample_params)
            assert 'export ARRAY_NAME="CBDB_SANDBOX"' in content  # default
            assert 'export SEG_PREFIX="gpseg"' in content          # default
        finally:
            cluster_deploy_web.CONFIG_FILE_PATH = orig

    def test_file_overrides_defaults(self, sample_params, tmp_path):
        """Original config file values should override built-in defaults."""
        config = tmp_path / 'config.sh'
        config.write_text('export ARRAY_NAME="MY_CUSTOM_CLUSTER"\n')

        import cluster_deploy_web
        orig = cluster_deploy_web.CONFIG_FILE_PATH
        cluster_deploy_web.CONFIG_FILE_PATH = str(config)
        try:
            content = generate_config_file(sample_params)
            assert 'export ARRAY_NAME="MY_CUSTOM_CLUSTER"' in content
        finally:
            cluster_deploy_web.CONFIG_FILE_PATH = orig

    def test_ui_params_override_file(self, tmp_path):
        """Web UI params should override values from config file."""
        config = tmp_path / 'config.sh'
        config.write_text('export COORDINATOR_PORT="15432"\n')

        import cluster_deploy_web
        orig = cluster_deploy_web.CONFIG_FILE_PATH
        cluster_deploy_web.CONFIG_FILE_PATH = str(config)
        try:
            params = {
                'COORDINATOR_PORT': '7777',
                'DEPLOY_TYPE': 'single',
            }
            content = generate_config_file(params)
            assert 'export COORDINATOR_PORT="7777"' in content
            assert '15432' not in content
        finally:
            cluster_deploy_web.CONFIG_FILE_PATH = orig


# ====================== 7. Deploycluster.sh Compatibility ======================

class TestDeployclusterCompatibility:
    """Simulate what deploycluster.sh does to the generated config file."""

    def test_truncation_preserves_all_params(self, sample_params):
        """Simulate: sed -i '/^export -f log_time$/q' config.sh
        All export params must survive the truncation."""
        content = generate_config_file(sample_params)

        # Simulate sed truncation
        truncated_lines = []
        for line in content.split('\n'):
            truncated_lines.append(line)
            if line.strip() == 'export -f log_time':
                break

        truncated = '\n'.join(truncated_lines)

        # Verify all critical variables survived
        critical_vars = [
            'ADMIN_USER', 'CLOUDBERRY_RPM', 'COORDINATOR_HOSTNAME',
            'COORDINATOR_PORT', 'COORDINATOR_DIRECTORY', 'DATA_DIRECTORY',
            'INIT_CONFIGFILE', 'MACHINE_LIST_FILE', 'ARRAY_NAME',
            'SEG_PREFIX', 'PORT_BASE', 'DATABASE_NAME',
        ]
        for var in critical_vars:
            assert f'export {var}=' in truncated, \
                f'{var} lost after deploycluster.sh truncation!'

    def test_init_cluster_variables_present(self, sample_params):
        """init_cluster.sh sources the config - all its variables must exist."""
        content = generate_config_file(sample_params)
        # Variables used in init_cluster.sh
        assert 'INIT_CONFIGFILE' in content
        assert 'MACHINE_LIST_FILE' in content
        assert 'COORDINATOR_HOSTNAME' in content
        assert 'COORDINATOR_DIRECTORY' in content
        assert 'COORDINATOR_PORT' in content
        assert 'SEG_PREFIX' in content
        assert 'ADMIN_USER' in content
        assert 'DATABASE_NAME' in content
