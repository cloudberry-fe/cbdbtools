// Tab switching
function openTab(evt, tabName) {
    var i, tabcontent, tablinks;
    tabcontent = document.getElementsByClassName("tabcontent");
    for (i = 0; i < tabcontent.length; i++) {
        tabcontent[i].classList.remove("active");
    }
    tablinks = document.getElementsByClassName("tablinks");
    for (i = 0; i < tablinks.length; i++) {
        tablinks[i].classList.remove("active");
    }
    document.getElementById(tabName).classList.add("active");
    evt.currentTarget.classList.add("active");
}

// Set deployment mode
function setDeploymentMode(mode, event) {
    document.getElementById('DEPLOY_TYPE').value = mode;

    // Update UI
    document.querySelectorAll('.mode-option').forEach(option => {
        option.classList.remove('selected');
    });
    event.currentTarget.classList.add('selected');

    // Show/hide multi-node parameters
    const multiNodeParams = document.getElementById('multiNodeParams');
    if (mode === 'multi') {
        multiNodeParams.classList.remove('hidden');
    } else {
        multiNodeParams.classList.add('hidden');
    }

    // Show/hide hosts tab based on deployment mode
    const hostsTabButton = document.getElementById('hostsTabButton');
    if (mode === 'multi') {
        hostsTabButton.classList.remove('hidden');
    } else {
        hostsTabButton.classList.add('hidden');
        // If hosts tab is active and we switch to single mode, switch to configuration tab
        if (document.getElementById('hosts').classList.contains('active')) {
            document.getElementById('configuration').classList.add('active');
            document.querySelector('.tablinks').classList.add('active');
            document.getElementById('hosts').classList.remove('active');
            hostsTabButton.classList.remove('active');
        }
    }

    // Check if Mirror Data Directories should be shown
    toggleMirrorDataDir();
}

// Segment access method toggle
function setupSegmentAccessToggle() {
    const selector = document.getElementById('SEGMENT_ACCESS_METHOD');
    if (selector) {
        selector.addEventListener('change', function() {
            const method = this.value;
            document.getElementById('keyfilePathGroup').style.display = method === 'keyfile' ? 'block' : 'none';
            document.getElementById('passwordGroup').style.display = method === 'keyfile' ? 'none' : 'block';
        });
    }
}

// Control Mirror Data Directories visibility
function toggleMirrorDataDir() {
    const withMirror = document.getElementById('WITH_MIRROR');
    const mirrorDataDirGroup = document.getElementById('mirrorParams');

    if (withMirror && mirrorDataDirGroup) {
        if (withMirror.value === 'true') {
            mirrorDataDirGroup.classList.remove('hidden');
        } else {
            mirrorDataDirGroup.classList.add('hidden');
        }
    }
}

// Add segment host
function addSegmentHost() {
    var container = document.getElementById("segments_container");
    var countInput = document.getElementById("segment_count_input");
    var currentCount = parseInt(countInput.value);
    var newCount = currentCount + 1;

    var newSegment = document.createElement("div");
    newSegment.className = "segment-host";
    newSegment.id = "segment_" + currentCount;
    newSegment.innerHTML = 
        '<div class="segment-host-header">' +
        '    <h4>Segment Host ' + newCount + '</h4>' +
        '    <button type="button" class="remove-host" onclick="removeSegmentHost(' + currentCount + ')">✕</button>' +
        '</div>' +
        '<div class="form-row">' +
        '    <div class="form-col">' +
        '        <div class="form-group">' +
        '            <label>IP Address:</label>' +
        '            <input type="text" name="segment_ip_' + currentCount + '" required>' +
        '        </div>' +
        '    </div>' +
        '    <div class="form-col">' +
        '        <div class="form-group">' +
        '            <label>Hostname:</label>' +
        '            <input type="text" name="segment_hostname_' + currentCount + '" required>' +
        '        </div>' +
        '    </div>' +
        '</div>';

    container.appendChild(newSegment);
    countInput.value = newCount;
}

// Remove segment host
function removeSegmentHost(index) {
    var segment = document.getElementById("segment_" + index);
    if (segment) {
        segment.remove();

        // Update segment count
        var countInput = document.getElementById("segment_count_input");
        var currentCount = parseInt(countInput.value);
        countInput.value = currentCount - 1;
    }
}

// Check deployment status periodically
function checkDeploymentStatus() {
    fetch('/deployment_status')
        .then(response => response.json())
        .then(data => {
            const deployButton = document.getElementById('deployButton');
            const deploymentStatus = document.getElementById('deploymentStatus');

            if (data.running) {
                deployButton.disabled = true;
                deployButton.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Deployment running...';
                deploymentStatus.classList.remove('hidden');
                deploymentStatus.classList.add('deployment-running');
                deploymentStatus.classList.remove('deployment-completed');
                refreshLogs();
            } else {
                deployButton.disabled = false;
                deployButton.innerHTML = '<i class="fas fa-rocket"></i> Deploy Cluster';
                deploymentStatus.classList.add('deployment-completed');
                deploymentStatus.classList.remove('deployment-running');

                // Add completion message
                if (!deploymentStatus.querySelector('.completion-message')) {
                    const msg = document.createElement('div');
                    msg.className = 'completion-message';
                    msg.style.cssText = 'color: var(--success-color); font-weight: bold; margin: 10px 0;';
                    msg.innerHTML = '<i class="fas fa-check-circle"></i> Deployment completed! Please check the log details.';
                    deploymentStatus.insertBefore(msg, deploymentStatus.firstChild.nextSibling);
                }
            }
        })
        .catch(error => console.error('Error checking deployment status:', error));
}

// Refresh deployment logs
function refreshLogs() {
    fetch('/deployment_logs')
        .then(response => response.json())
        .then(data => {
            const logContainer = document.getElementById('deploymentLog');
            if (logContainer) {
                logContainer.textContent = data.logs || 'No log content yet...';
                logContainer.scrollTop = logContainer.scrollHeight;
            }
        })
        .catch(error => {
            console.error('Error retrieving logs:', error);
            const logContainer = document.getElementById('deploymentLog');
            logContainer.textContent = 'Failed to retrieve logs. Please refresh the page to try again.';
        });
}

// Start deployment with confirmation
function startDeployment() {
    // Check for warnings before proceeding
    const warningItems = document.querySelectorAll('.warning-item');
    if (warningItems.length > 0) {
        alert('Please resolve all warnings before deploying the cluster.');
        return false;
    }
    
    if (confirm('Are you sure you want to deploy the cluster? This may take several minutes.')) {
        // Show deployment status area
        document.getElementById('deploymentStatus').classList.remove('hidden');
        
        // Start checking deployment status
        checkDeploymentStatus();
        
        // Set up periodic status checking
        setInterval(checkDeploymentStatus, 5000); // Check every 5 seconds
        
        return true;
    }
    return false;
}

// Initialize the page
function initializePage() {
    // Set up segment access toggle
    setupSegmentAccessToggle();

    // Listen for Enable Mirrors changes
    const withMirror = document.getElementById('WITH_MIRROR');
    if (withMirror) {
        withMirror.addEventListener('change', toggleMirrorDataDir);
        // Initialize on load
        toggleMirrorDataDir();
    }

    // Initialize form based on deployment mode
    const deployType = document.getElementById('DEPLOY_TYPE').value;
    if (deployType === 'multi') {
        document.getElementById('multiNodeParams').classList.remove('hidden');
    }

    // Handle configuration form submission
    const configForm = document.getElementById('configForm');
    if (configForm) {
        configForm.addEventListener('submit', function(e) {
            // Prevent default submission to avoid page reload
            e.preventDefault();
            
            // Get deployment mode
            const deployType = document.getElementById('DEPLOY_TYPE').value;
            
            // Submit form data asynchronously
            fetch(configForm.action, {{
                method: configForm.method,
                body: new FormData(configForm)
            }})
            .then(response => response.ok ? response : Promise.reject(response))
            .then(() => {{
                // 调用刷新部署信息函数
                refreshDeploymentInfo();
                
                // Determine target tab based on deployment mode
                if (deployType === 'multi') {{
                    // Multi-node mode: navigate to hosts tab
                    const hostsButton = document.querySelector('button[onclick="openTab(event, \'hosts\')"]');
                    if (hostsButton) {{
                        hostsButton.click();
                    }}
                }} else {{
                    // Single node mode: navigate directly to deploy tab
                    const deployButton = document.querySelector('button[onclick="openTab(event, \'deploy\')"]');
                    if (deployButton) {{
                        deployButton.click();
                    }}
                }}
            }})
            .catch(error => {{
                console.error('Form submission failed:', error);
                alert('Failed to save configuration. Please try again.');
            }});
        });
    }

    // Handle hosts form submission
    const hostsForm = document.getElementById('hostsForm');
    if (hostsForm) {
        hostsForm.addEventListener('submit', function(e) {
            // Prevent default submission to avoid page reload
            e.preventDefault();
            
            // Submit form data asynchronously
            fetch(hostsForm.action, {{
                method: hostsForm.method,
                body: new FormData(hostsForm)
            }})
            .then(response => response.ok ? response : Promise.reject(response))
            .then(() => {{
                // 调用刷新部署信息函数
                refreshDeploymentInfo();
                
                // Navigate to deploy tab after saving hosts configuration
                const deployButton = document.querySelector('button[onclick="openTab(event, \'deploy\')"]');
                if (deployButton) {{
                    deployButton.click();
                }}
            }})
            .catch(error => {{
                console.error('Form submission failed:', error);
                alert('Failed to save hosts configuration. Please try again.');
            }});
        });
    }

    // Set initial active tab based on URL parameter
    const urlParams = new URLSearchParams(window.location.search);
    const tabParam = urlParams.get('tab');
    
    // 明确设置默认选项卡
    let activeTab = 'configuration';
    
    if (tabParam) {
        activeTab = tabParam;
    }
    
    // 确保选择有效的选项卡
    const validTabs = ['configuration', 'hosts', 'deploy'];
    if (!validTabs.includes(activeTab)) {
        activeTab = 'configuration';
    }
    
    // 移除所有选项卡的active类
    document.querySelectorAll('.tablinks, .tabcontent').forEach(el => {
        el.classList.remove('active');
    });
    
    // 添加active类到目标选项卡
    const tabButton = document.querySelector(`button[onclick="openTab(event, '${activeTab}')"]`);
    const tabContent = document.getElementById(activeTab);
    
    if (tabButton && tabContent) {
        tabButton.classList.add('active');
        tabContent.classList.add('active');
    } else {
        // 如果找不到目标选项卡，回退到configuration选项卡
        document.querySelector('button[onclick="openTab(event, \'configuration\')"]').classList.add('active');
        document.getElementById('configuration').classList.add('active');
    }

    // Check deployment status immediately
    checkDeploymentStatus();

    // Set up periodic status checking
    setInterval(checkDeploymentStatus, 5000); // Check every 5 seconds
}

// Initialize the page when DOM is fully loaded
document.addEventListener('DOMContentLoaded', function() {
    initializePage();
    // Check warnings and update deploy button status
    updateDeployButtonStatus();
});

// Function to check warnings and update deploy button status
function updateDeployButtonStatus() {
    // Use the correct selector to find the button
    const deployButton = document.getElementById('deployButton');
    // Check for warning items
    const warningItems = document.querySelectorAll('.warning-item');

    if (deployButton) {
        if (warningItems.length > 0) {
            // There are warnings, disable the button
            deployButton.disabled = true;
            deployButton.classList.add('disabled');
            deployButton.title = 'Please resolve all warnings before deploying';
        } else {
            // No warnings, enable the button
            deployButton.disabled = false;
            deployButton.classList.remove('disabled');
            deployButton.title = 'Start cluster deployment';
        }
    } else {
        console.error('Deploy button not found');
    }
}

// Ensure warnings are checked when the page loads
window.addEventListener('load', function() {
    // Delay slightly to ensure warning elements have rendered
    setTimeout(updateDeployButtonStatus, 100);
});

// Also call this function after refreshing deployment info
// (We'll modify the refreshDeploymentInfo function to call it at the end)
// Improved function to refresh deployment information
function refreshDeploymentInfo() {
    console.log('Refreshing deployment information...');
    
    // Fetch latest deployment parameters from server
    fetch('/get_deployment_params')
        .then(response => response.json())
        .then(data => {
            const params = data.params;
            const hosts = data.hosts;
            
            // Update deployment mode display
            const deployModeElement = document.querySelector('.dashboard-card.info-card .info-grid .info-item:nth-child(1) .info-value span');
            if (deployModeElement) {
                if (params.DEPLOY_TYPE === 'single') {
                    deployModeElement.textContent = 'Single Node';
                    deployModeElement.className = 'badge badge-blue';
                } else {
                    deployModeElement.textContent = 'Multi Node';
                    deployModeElement.className = 'badge badge-green';
                }
            }
            
            // Update coordinator host information
            const coordinatorElement = document.querySelector('.dashboard-card.info-card .info-grid .info-item:nth-child(2) .info-value');
            if (coordinatorElement) {
                if (params.DEPLOY_TYPE === 'single') {
                    // Single mode: always use configuration from params
                    coordinatorElement.innerHTML = '<strong>' + (params.COORDINATOR_HOSTNAME || 'Not configured') + '</strong> (' + (params.COORDINATOR_IP || 'Not configured') + ')';
                } else {
                    // Multi mode: use hosts configuration but check consistency with params
                    if (hosts.coordinator && hosts.coordinator.length >= 2) {
                        const hostname = hosts.coordinator[1];
                        const ip = hosts.coordinator[0];
                        let html = '<strong>' + hostname + '</strong> (' + ip + ')';
                        
                        // Check for consistency
                        if (hostname !== (params.COORDINATOR_HOSTNAME || '') || ip !== (params.COORDINATOR_IP || '')) {
                            html += ' <span class="warning-icon" title="Coordinator configuration mismatch detected!">⚠️</span>';
                        }
                        
                        coordinatorElement.innerHTML = html;
                    } else {
                        coordinatorElement.innerHTML = 'Not configured';
                    }
                }
            }
            
            // Update mirror status display
            const mirrorStatusElement = document.querySelector('.dashboard-card.info-card .info-grid .info-item:nth-child(3) .info-value');
            if (mirrorStatusElement) {
                if (params.WITH_MIRROR === 'true') {
                    const primaryCount = data.data_dirs ? data.data_dirs.length : 0;
                    const mirrorCount = data.mirror_dirs ? data.mirror_dirs.length : 0;
                    
                    let html = '<span class="badge badge-purple">Enabled</span>' +
                        '<span class="mirror-count-info">' +
                        ' (Primary: ' + primaryCount +
                        ', Mirror: ' + mirrorCount + ')';
                        
                    // Check for count consistency
                    if (primaryCount !== mirrorCount) {
                        html += ' <span class="warning-icon" title="Primary and mirror count mismatch detected!">⚠️</span>';
                    }
                    
                    html += '</span>';
                    mirrorStatusElement.innerHTML = html;
                } else {
                    mirrorStatusElement.innerHTML = '<span class="badge badge-gray">Disabled</span>';
                }
            }
            
            // Update detailed configuration sections
            // Coordinator details
            const coordPortElement = document.querySelector('#coordinator-details .detail-item:nth-child(1) .detail-value');
            if (coordPortElement) coordPortElement.textContent = params.COORDINATOR_PORT || 'Not configured';
            
            const coordDirElement = document.querySelector('#coordinator-details .detail-item:nth-child(2) .detail-value');
            if (coordDirElement) coordDirElement.textContent = params.COORDINATOR_DIRECTORY || 'Not configured';
            
            // Segment details
            const segDirElement = document.querySelector('#segment-details .detail-item:nth-child(1) .detail-value');
            if (segDirElement) segDirElement.textContent = params.DATA_DIRECTORY || 'Not configured';
            
            const segPortElement = document.querySelector('#segment-details .detail-item:nth-child(2) .detail-value');
            if (segPortElement) segPortElement.textContent = params.PORT_BASE || 'Not configured';
            
            const segCountElement = document.querySelector('#segment-details .detail-item:nth-child(3) .detail-value');
            const segCount = data.data_dirs ? data.data_dirs.length : 0;
            if (segCountElement) segCountElement.textContent = segCount;
            
            // Mirror details (if enabled)
            if (params.WITH_MIRROR === 'true') {
                const mirrorPortElement = document.querySelector('#mirror-details .detail-item:nth-child(1) .detail-value');
                if (mirrorPortElement) mirrorPortElement.textContent = params.MIRROR_PORT_BASE || 'Not configured';
                
                const mirrorDirElement = document.querySelector('#mirror-details .detail-item:nth-child(2) .detail-value');
                if (mirrorDirElement) mirrorDirElement.textContent = params.MIRROR_DATA_DIRECTORY || 'Not configured';
                
                const mirrorCountElement = document.querySelector('#mirror-details .detail-item:nth-child(3) .detail-value');
                const mirrorCount = data.mirror_dirs ? data.mirror_dirs.length : 0;
                if (mirrorCountElement) mirrorCountElement.textContent = mirrorCount;
            }
            
            // Multi-node details (if in multi-node mode)
            if (params.DEPLOY_TYPE === 'multi') {
                const segmentHostsElement = document.querySelector('#multi-node-details .detail-item .detail-value');
                if (segmentHostsElement) segmentHostsElement.textContent = (hosts.segments ? hosts.segments.length : 0) + ' configured';
                
                // Update segment hosts list
                const segmentHostsList = document.querySelector('.segment-hosts-list ul');
                if (segmentHostsList) {
                    segmentHostsList.innerHTML = '';
                    if (hosts.segments && hosts.segments.length > 0) {
                        hosts.segments.forEach(segment => {
                            const listItem = document.createElement('li');
                            listItem.textContent = segment[1] + ' (' + segment[0] + ')';
                            segmentHostsList.appendChild(listItem);
                        });
                    }
                }
            }
            
            // Update deploy button status after refreshing info
            updateDeployButtonStatus();
        })
        .catch(error => {
            console.error('Error refreshing deployment information:', error);
            alert('Failed to refresh deployment information. Please try again.');
            // Update deploy button status even if there's an error
            updateDeployButtonStatus();
        });
}

// After refreshing deployment info, update deploy button status
updateDeployButtonStatus();
}