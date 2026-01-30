#!/bin/bash

if [ "$EUID" -ne 0 ]; then 
    echo "请使用 sudo 运行: sudo ./change-password.sh"
    exit 1
fi

cd /opt/upload

echo "修改文件上传系统密码"
echo "====================="
echo ""

read -sp "请输入新密码: " NEW_PASS
echo ""
read -sp "确认新密码: " NEW_PASS2
echo ""

if [ "$NEW_PASS" != "$NEW_PASS2" ]; then
    echo "错误：两次输入的密码不一致！"
    exit 1
fi

if [ -z "$NEW_PASS" ]; then
    echo "错误：密码不能为空！"
    exit 1
fi

# 备份原配置
cp config.py config.py.bak

# 获取原端口配置
START_PORT=$(grep "START_PORT" config.py | cut -d'=' -f2 | tr -d ' ')

# 创建新配置
cat > config.py << EOF
import socket

PASSWORD = "$NEW_PASS"
START_PORT = $START_PORT

def find_available_port(start_port):
    """寻找可用端口"""
    port = start_port
    max_port = start_port + 100
    
    while port <= max_port:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(('0.0.0.0', port))
            sock.close()
            return port
        except OSError:
            port += 1
            continue
    
    return None
EOF

echo "✅ 密码修改成功！"
echo ""
echo "需要重启服务使新密码生效："
echo "cd /opt/upload && ./manage.sh restart"
