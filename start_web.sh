#!/bin/bash

# 检查是否安装了Python和Flask
if ! command -v python3 &> /dev/null
then
    echo "未找到Python3，请先安装Python3。"
    exit 1
fi

# 检查是否安装了pip
if ! command -v pip3 &> /dev/null
then
    echo "未找到pip3，请先安装pip3。"
    exit 1
fi

# 安装Flask
pip3 install -i https://mirrors.aliyun.com/pypi/simple flask --user

# 启动Web应用
python3 cluster_deploy_web.py