#!/bin/bash

echo "========================================"
echo "文件上传系统安装脚本 (UUID版本) - 含防火墙和服务配置"
echo "========================================"

echo "0. 清理可能存在的旧服务..."
systemctl stop file-upload-uuid 2>/dev/null
systemctl disable file-upload-uuid 2>/dev/null
rm -f /etc/systemd/system/file-upload-uuid.service
systemctl daemon-reload

echo "1. 正在更新系统和安装必要软件..."
apt-get update
apt-get install -y python3 python3-pip curl wget net-tools ufw

echo "2. 安装 Python 依赖..."
pip3 install flask python-magic

echo "3. 创建项目目录..."
mkdir -p /opt/file-upload-uuid/uploads
cd /opt/file-upload-uuid

echo "4. 设置访问密码..."
read -s -p "请输入访问密码: " PASSWORD
echo
read -s -p "请再次确认密码: " PASSWORD2
echo
if [ "$PASSWORD" != "$PASSWORD2" ]; then
    echo "密码不一致，安装失败"
    exit 1
fi

echo "5. 设置服务器端口..."
read -p "请输入端口号（默认5555）: " PORT
PORT=${PORT:-5555}

echo "6. 配置系统防火墙..."
ufw allow $PORT/tcp
echo "y" | ufw enable

echo "7. 下载服务文件..."
curl -H 'Cache-Control: no-cache, no-store, must-revalidate' -s -o server.py "https://raw.githubusercontent.com/maifeijihao/file-upload-system/main/server.py"
curl -H 'Cache-Control: no-cache, no-store, must-revalidate' -s -o config.py "https://raw.githubusercontent.com/maifeijihao/file-upload-system/main/config.py"
curl -H 'Cache-Control: no-cache, no-store, must-revalidate' -s -o index.html "https://raw.githubusercontent.com/maifeijihao/file-upload-system/main/index.html"

echo "8. 生成配置文件..."
cat > config.py <<EOF
PASSWORD = "$PASSWORD"
PORT = $PORT
UPLOAD_DIR = "/opt/file-upload-uuid/uploads"
HOST = "0.0.0.0"
EOF

echo "9. 创建 systemd 服务..."
cat > /etc/systemd/system/file-upload-uuid.service <<EOF
[Unit]
Description=File Upload System
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/file-upload-uuid
ExecStart=/usr/bin/python3 /opt/file-upload-uuid/server.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "10. 启动服务..."
systemctl daemon-reload
systemctl enable file-upload-uuid
systemctl start file-upload-uuid

sleep 2
if systemctl is-active --quiet file-upload-uuid; then
    IP=$(curl -s ifconfig.me)
    echo "========================================"
    echo "✅ UUID版本文件上传系统安装完成！"
    echo "访问地址: http://$IP:$PORT"
    echo "登录密码: $PASSWORD"
    echo "========================================"
else
    echo "❌ 服务启动失败，请检查日志: journalctl -u file-upload-uuid -n 30"
fi
