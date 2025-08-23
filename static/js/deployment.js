// Deployment state management
const deployment = {
    lastPosition: 0,
    updateTimer: null,
    isDeploying: false, // 新增：跟踪部署状态
    eventSource: null, // 添加 eventSource 属性
    retryCount: 0,  // 添加重试计数器
    hasCompleted: false, // ✅ 新增：是否已完成标志（避免重复关闭）
    verifyingCompletion: false, // ✅ 新增：避免并发重复二次确认

    showError: function(message) {
        const errorDiv = document.getElementById('deployment-error');
        if (errorDiv) {
            errorDiv.textContent = message;
            errorDiv.style.display = 'block';
        }
        console.error(message);
    },

    hideError: function() {
        const errorDiv = document.getElementById('deployment-error');
        if (errorDiv) {
            errorDiv.style.display = 'none';
            errorDiv.textContent = '';
        }
    },

    appendLog: function(content) {
        const logContent = document.getElementById('log-content');
        if (logContent) {
            logContent.textContent += content;

            // Auto-scroll
            const container = document.getElementById('deploymentLog');
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        }
    },

    startLogStream: function() {
        console.log('Starting log stream...'); // 调试日志

        if (this.eventSource) {
            console.log('Closing existing event source...'); // 调试日志
            this.eventSource.close();
            this.eventSource = null;
        }

        // ✅ 仅创建一次 EventSource（移除重复创建）
        this.eventSource = new EventSource('/stream_logs');
        this.eventSource.reconnectInterval = 2000;

        // 设置事件处理器
        this.setupEventHandlers();
    },

    // ✅ 新增：稳健的完成二次确认
    verifyAndCloseIfCompleted: function(sseData) {
        if (this.hasCompleted || this.verifyingCompletion) return;

        this.verifyingCompletion = true;

        fetch('/deployment_status')
            .then(response => response.json())
            .then(status => {
                // 判断"完成"的条件更稳健：
                // 1) 服务端状态已不在运行
                // 2) 且（包含完成关键字 或 SSE 报告 position >= file_size）
                const notRunning = status && status.running === false;

                // 关键字判定（防止早期 is_running:false 的误报）
                const c = (sseData && sseData.content) ? sseData.content : '';
                const hasFinishMarker =
                    c.includes('Finished deploy cluster') ||
                    c.includes('Process exited with code');

                const reachedEOF = typeof sseData?.position === 'number' &&
                                   typeof sseData?.file_size === 'number' &&
                                   sseData.position >= sseData.file_size;

                if (notRunning && (hasFinishMarker || reachedEOF)) {
                    console.log('Deployment confirmed completed ✅, closing connection');
                    this.closeConnection();
                } else {
                    // 仍在运行或者未到文件末尾：不关闭，保持监听
                    // console.log('Completion check: still running or not at EOF, keep streaming.');
                }
            })
            .catch(err => {
                console.error('Error verifying completion status:', err);
            })
            .finally(() => {
                this.verifyingCompletion = false;
            });
    },

    setupEventHandlers: function() {
        if (!this.eventSource) {
            console.error('No EventSource available to setup handlers');
            return;
        }

        this.eventSource.onopen = () => {
            console.log('EventSource connection opened'); // 调试日志
        };

        this.eventSource.onmessage = (event) => {
            console.log('Raw event data:', event.data); // 调试日志

            try {
                let data;
                try {
                    data = JSON.parse(event.data);
                } catch (parseError) {
                    console.warn('Failed to parse event data as JSON:', parseError);
                    // 如果不是JSON，直接作为普通文本处理
                    this.appendLog(event.data + '\n');
                    return;
                }
                console.log('Parsed SSE data:', data); // 调试日志

                // 处理错误信息
                if (data.error) {
                    console.error('Server reported error:', data.error);
                    this.showError(data.error);
                    if (data.error.includes('Multiple errors')) {
                        this.closeConnection();
                    }
                    return;
                }

                // 如果收到初始等待消息，不做特殊处理
                if (data.content === "Waiting for deployment to start...") {
                    console.log('Received waiting message');
                    return;
                }

                // 处理实际内容
                if (data.content) {
                    console.log('Processing content:', {
                        contentLength: data.content.length,
                        position: data.position,
                        fileSize: data.file_size,
                        isRunning: data.is_running
                    });

                    this.appendLog(data.content);
                    // 记录最后一次位置（便于必要时使用）
                    if (typeof data.position === 'number') {
                        this.lastPosition = data.position;
                    }
                }

                // ✅ 完成判断：不再单凭一次 is_running:false 立即关闭，改为"二次确认"
                if (data.is_running === false) {
                    this.verifyAndCloseIfCompleted(data);
                }
            } catch (error) {
                console.error('Error processing event:', error);
                this.showError('Error processing log data: ' + error.message);
            }
        };

        this.eventSource.onerror = (error) => {
            const state = this.eventSource ? this.eventSource.readyState : null;

            // 如果我们已经确认完成了，不做任何重连动作
            if (this.hasCompleted) {
                console.log('SSE error after completion, ignoring.');
                return;
            }

            // 如果连接已关闭
            if (state === EventSource.CLOSED) {
                // 检查部署状态
                fetch('/deployment_status')
                    .then(response => response.json())
                    .then(status => {
                        if (status.running) {
                            // 部署仍在运行，稍等后重连
                            setTimeout(() => {
                                if (this.isDeploying && !this.hasCompleted) {
                                    this.startLogStream();
                                }
                            }, 2000);
                        } else {
                            // 不在运行：再做一次稳健确认（防止 race）
                            this.verifyAndCloseIfCompleted({ position: this.lastPosition, file_size: this.lastPosition, content: '' });
                        }
                    })
                    .catch(() => {
                        // 检查失败也尝试重连（仅在未完成且处于部署中）
                        if (this.isDeploying && !this.hasCompleted) {
                            setTimeout(() => this.startLogStream(), 2000);
                        }
                    });
            }
        };
    },

    closeConnection: function() {
        console.log('Closing deployment connection');
        this.isDeploying = false;
        this.hasCompleted = true;

        if (this.eventSource) {
            this.eventSource.close();
            this.eventSource = null;
        }

        if (this.updateTimer) {
            clearTimeout(this.updateTimer);
            this.updateTimer = null;
        }

        const deployButton = document.getElementById('deployButton');
        if (deployButton) {
            deployButton.disabled = false;
            deployButton.innerHTML = '<i class="fas fa-rocket"></i> Deploy Cluster';
        }

        // ❗ 保持日志路径区域可见（你的需求是日志生成后一直显示）
        // const logPathInfo = document.getElementById('logPathInfo');
        // if (logPathInfo) {
        //     logPathInfo.style.display = 'none';
        // }
    },

    updateLog: function() {
        this.hideError();

        // ✅ 如果 SSE 已经连接着，就不再重复重建
        if (this.eventSource && this.eventSource.readyState === EventSource.OPEN) {
            return;
        }
        this.startLogStream();
    },

    scheduleUpdate: function(delay) {
        // ✅ 如果 SSE 已经连接着，就不再安排轮询/重连的定时器
        if (this.eventSource && this.eventSource.readyState === EventSource.OPEN) {
            if (this.updateTimer) {
                clearTimeout(this.updateTimer);
                this.updateTimer = null;
            }
            return;
        }

        if (this.updateTimer) {
            clearTimeout(this.updateTimer);
        }
        this.updateTimer = setTimeout(() => this.updateLog(), delay);
    },

    start: function() {
        // 如果已经在部署中，直接返回
        if (this.isDeploying) {
            console.log('Deployment already in progress');
            return false;
        }

        // 检查是否有警告
        const warningItems = document.querySelectorAll('.warning');
        if (warningItems.length > 0) {
            alert('Please resolve all warnings before deploying the cluster.');
            return false;
        }

        // 确认部署
        if (!confirm('Are you sure you want to deploy the cluster? This may take several minutes.')) {
            return false;
        }

        console.log('Starting deployment process...'); // 调试日志
        // 设置部署状态
        this.isDeploying = true;
        this.hasCompleted = false;
        this.verifyingCompletion = false;

        // Reset state
        this.lastPosition = 0;
        const logContent = document.getElementById('log-content');
        if (logContent) {
            logContent.textContent = 'Initializing deployment...\n';
        }

        // 获取所有需要的UI元素
        const deployButton = document.getElementById('deployButton');
        const logPathInfo = document.getElementById('logPathInfo');
        const logFilePath = document.getElementById('logFilePath');
        const deploymentStatus = document.getElementById('deploymentStatus');

        // 禁用按钮
        if (deployButton) {
            deployButton.disabled = true;
            deployButton.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Deployment in progress...';
        }

        // 显示日志路径区域（初始为空）
        if (logPathInfo) {
            logPathInfo.style.display = 'block';
            if (logFilePath) {
                logFilePath.textContent = 'Initializing...';
            }
        }

        // 显示部署状态区域
        if (deploymentStatus) {
            deploymentStatus.classList.remove('hidden');
        }

        // Clear any previous error
        this.hideError();

        // 关闭之前的事件源（如果有）
        if (this.eventSource) {
            this.eventSource.close();
            this.eventSource = null;
        }

        // Start deployment
        fetch('/deploy', {
            method: 'POST',
            body: new FormData(document.getElementById('deployForm'))
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                this.appendLog('Deployment started successfully.\n');
                // 立即开始日志流
                this.startLogStream();

                // 兼容后端返回键名（log_file / log_path）
                const pathFromBackend = data.log_path || data.log_file;
                if (logPathInfo) {
                    logPathInfo.style.display = 'block';
                    if (logFilePath && pathFromBackend) {
                        logFilePath.textContent = pathFromBackend;
                    }
                }

                // 旧逻辑保留，但在 SSE 已开时不会再次重建
                this.scheduleUpdate(2000);
            } else {
                this.isDeploying = false;
                this.showError(data.message || 'Failed to start deployment');
                if (deployButton) {
                    deployButton.disabled = false;
                    deployButton.innerHTML = '<i class="fas fa-rocket"></i> Deploy Cluster';
                }
                if (deploymentStatus) {
                    deploymentStatus.classList.add('hidden');
                }
                // 保留日志路径区域（按你的新需求：生成后就一直显示）
                // if (logPathInfo) {
                //     logPathInfo.style.display = 'none';
                // }
            }
        })
        .catch(error => {
            this.isDeploying = false;
            this.showError('Error starting deployment: ' + error.message);
            if (deployButton) {
                deployButton.disabled = false;
                deployButton.innerHTML = '<i class="fas fa-rocket"></i> Deploy Cluster';
            }
            if (deploymentStatus) {
                deploymentStatus.classList.add('hidden');
            }
            // 保留日志路径区域（按你的新需求：生成后就一直显示）
            // if (logPathInfo) {
            //     logPathInfo.style.display = 'none';
            // }
        });

        return false; // 阻止表单默认提交
    },

    // Check if deployment is already running when page loads
    checkInitialStatus: function() {
        fetch('/deployment_status')
            .then(response => response.json())
            .then(status => {
                if (status.running) {
                    this.isDeploying = true;
                    this.hasCompleted = false;
                    const deploymentStatus = document.getElementById('deploymentStatus');
                    if (deploymentStatus) {
                        deploymentStatus.classList.remove('hidden');
                    }

                    const deployButton = document.getElementById('deployButton');
                    if (deployButton) {
                        deployButton.disabled = true;
                        deployButton.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Deployment in progress...';
                    }

                    this.updateLog();
                } else {
                    // 如果不在运行，但后端记着最新日志路径，也显示（保持一直可见）
                    const logPathInfo = document.getElementById('logPathInfo');
                    const logFilePath = document.getElementById('logFilePath');
                    if (logPathInfo && status.log_file) {
                        logPathInfo.style.display = 'block';
                        if (logFilePath) {
                            logFilePath.textContent = status.log_file;
                        }
                    }
                }
            })
            .catch(error => {
                console.error('Error checking deployment status:', error);
            });
    }
};

// Initialize deployment form
document.addEventListener('DOMContentLoaded', function() {
    const deployButton = document.getElementById('deployButton');
    if (deployButton) {
        deployButton.addEventListener('click', function(e) {
            e.preventDefault();
            deployment.start();
        });
    }

    const logPathInfo = document.getElementById('logPathInfo');
    if (logPathInfo) {
        logPathInfo.style.display = 'none';
    }

    // Check initial deployment status
    deployment.checkInitialStatus();
});