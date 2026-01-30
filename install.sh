#!/bin/bash

echo "安装文件上传系统（带端口扫描）..."
echo "=================================="

# 检查root权限
[ "$EUID" -ne 0 ] && echo "请使用 sudo 运行" && exit 1

# 安装依赖
apt-get update
apt-get install -y python3 python3-pip
pip3 install flask

# 创建目录
mkdir -p /opt/upload/uploads
cd /opt/upload

# 设置密码
read -sp "设置访问密码: " PASS
echo
read -sp "确认密码: " PASS2
echo
[ "$PASS" != "$PASS2" ] && echo "密码不一致" && exit 1

# 设置起始端口
read -p "起始端口号 (默认5000): " START_PORT
START_PORT=${START_PORT:-5000}

# 下载其他文件
echo "下载配置文件..."
curl -s https://raw.githubusercontent.com/YOUR_USERNAME/file-upload-system/main/config.py -o config.py
sed -i "s/PASSWORD = \"\"/PASSWORD = \"$PASS\"/" config.py
sed -i "s/START_PORT = 5000/START_PORT = $START_PORT/" config.py

echo "下载服务器文件..."
curl -s https://raw.githubusercontent.com/YOUR_USERNAME/file-upload-system/main/server.py -o server.py

echo "下载前端文件..."
curl -s https://raw.githubusercontent.com/YOUR_USERNAME/file-upload-system/main/index.html -o index.html

echo "下载管理脚本..."
curl -s https://raw.githubusercontent.com/YOUR_USERNAME/file-upload-system/main/manage.sh -o manage.sh
chmod +x manage.sh

curl -s https://raw.githubusercontent.com/YOUR_USERNAME/file-upload-system/main/change-password.sh -o change-password.sh
chmod +x change-password.sh

# 设置目录权限
chmod 777 /opt/upload/uploads

# 获取IP地址
IP=$(hostname -I | awk '{print $1}')

echo ""
echo "安装完成！"
echo "=========="
echo "安装目录: /opt/upload"
echo "上传目录: /opt/upload/uploads"
echo "起始端口: $START_PORT (如果被占用会自动寻找可用端口)"
echo "访问密码: $PASS"
echo ""
echo "启动命令:"
echo "cd /opt/upload && python3 server.py"
echo ""
echo "或使用管理脚本:"
echo "cd /opt/upload && ./manage.sh start"
echo ""
echo "修改密码:"
echo "cd /opt/upload && sudo ./change-password.sh"
