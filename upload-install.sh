#!/bin/bash

echo "========================================"
echo "文件上传系统安装脚本 (UUID版本)"
echo "========================================"

# 0. 清理旧服务
echo "0. 清理可能存在的旧服务..."
systemctl stop file-upload-uuid 2>/dev/null || true
systemctl disable file-upload-uuid 2>/dev/null || true
rm -f /etc/systemd/system/file-upload-uuid.service
systemctl daemon-reload

# 1. 安装系统依赖
echo "1. 更新系统并安装基础软件..."
apt-get update -y
apt-get install -y python3 python3-pip curl wget net-tools ufw

# 2. 安装 Flask 和 python-magic（使用 apt，避免 pip 冲突）
echo "2. 安装 Python 依赖..."
apt-get install -y python3-flask python3-magic

# 3. 创建项目目录
echo "3. 创建项目目录..."
mkdir -p /opt/file-upload-uuid/uploads
cd /opt/file-upload-uuid

# 4. 下载核心文件（每次都从仓库拉取最新，确保干净）
echo "4. 下载核心文件..."
curl -fsSL -o server.py https://raw.githubusercontent.com/maifeijihao/file-upload-system/main/server.py
curl -fsSL -o config.py https://raw.githubusercontent.com/maifeijihao/file-upload-system/main/config.py
curl -fsSL -o index.html https://raw.githubusercontent.com/maifeijihao/file-upload-system/main/index.html

# 5. 设置密码和端口
echo "5. 设置访问密码..."
read -s -p "请输入访问密码: " PASSWORD
echo
read -s -p "请再次确认密码: " PASSWORD2
echo
if [ "$PASSWORD" != "$PASSWORD2" ]; then
    echo "密码不一致，退出"
    exit 1
fi

echo "6. 设置服务器端口..."
read -p "请输入端口号（默认5555）: " PORT
PORT=${PORT:-5555}

# 6. 配置防火墙
echo "7. 配置防火墙..."
if command -v ufw &>/dev/null; then
    ufw allow "$PORT"/tcp
    echo "y" | ufw enable
    echo "✅ 端口 $PORT 已开放"
fi

# 7. 创建本地配置文件
echo "8. 生成配置文件..."
cat > config_local.py <<EOF
PASSWORD = "$PASSWORD"
PORT = $PORT
UPLOAD_DIR = "/opt/file-upload-uuid/uploads"
HOST = "0.0.0.0"
EOF

# 8. 在 server.py 开头插入导入语句（不破坏 shebang）
if [[ $(head -1 server.py) == "#!/usr/bin/env python3" ]]; then
    # 有 shebang：在第二行插入
    sed -i '2i from config_local import *' server.py
else
    # 无 shebang：在第一行插入
    sed -i '1i from config_local import *' server.py
fi

# 9. 创建 systemd 服务
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

# 10. 启动服务
echo "10. 启动服务..."
chmod -R 755 /opt/file-upload-uuid
systemctl daemon-reload
systemctl enable file-upload-uuid
systemctl start file-upload-uuid

sleep 2
if systemctl is-active --quiet file-upload-uuid; then
    IP=$(curl -s ifconfig.me)
    echo "========================================"
    echo "✅ 安装成功！"
    echo "访问地址: http://$IP:$PORT"
    echo "密码: $PASSWORD"
    echo "========================================"
else
    echo "❌ 服务启动失败，查看日志: journalctl -u file-upload-uuid -n 30"
    exit 1
fi
