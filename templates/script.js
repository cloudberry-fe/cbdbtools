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
            // Let the form submit normally to the server
        });
    }

    // Handle hosts form submission
    const hostsForm = document.getElementById('hostsForm');
    if (hostsForm) {
        hostsForm.addEventListener('submit', function(e) {
            // Let the form submit normally to the server
        });
    }

    // Set initial active tab based on URL parameter
    const urlParams = new URLSearchParams(window.location.search);
    const tabParam = urlParams.get('tab');
    
    if (tabParam) {
        // Find the tab button and content
        const tabButton = document.querySelector(`.tablinks[onclick*="'${tabParam}'"]`);
        const tabContent = document.getElementById(tabParam);

        if (tabButton && tabContent) {
            // Remove active class from all tabs
            document.querySelectorAll('.tablinks, .tabcontent').forEach(el => {
                el.classList.remove('active');
            });

            // Add active class to the target tab
            tabButton.classList.add('active');
            tabContent.classList.add('active');
        }
    } else {
        // Set default active tab to configuration if no URL parameter
        const defaultTabButton = document.querySelector('.tablinks[onclick*="configuration"]');
        const defaultTabContent = document.getElementById('configuration');
        
        if (defaultTabButton && defaultTabContent) {
            // Remove active class from all tabs first
            document.querySelectorAll('.tablinks, .tabcontent').forEach(el => {
                el.classList.remove('active');
            });
            
            // Add active class to default tab
            defaultTabButton.classList.add('active');
            defaultTabContent.classList.add('active');
        }
    }

    // Check deployment status immediately
    checkDeploymentStatus();

    // Set up periodic status checking
    setInterval(checkDeploymentStatus, 5000); // Check every 5 seconds
}

// Initialize the page when DOM is fully loaded
document.addEventListener('DOMContentLoaded', initializePage);