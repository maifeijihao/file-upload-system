#!/bin/bash
set -e

echo "========================================="
echo "文件上传系统 - HTTPS 自动配置脚本"
echo "========================================="

# 交互式输入域名和端口
read -p "请输入你的域名（已解析到本机 IP）: " DOMAIN
read -p "请输入文件上传服务的端口号（例如 5565）: " PORT

if [ -z "$DOMAIN" ] || [ -z "$PORT" ]; then
    echo "❌ 错误：域名和端口不能为空"
    exit 1
fi

echo ""
echo "即将为域名 $DOMAIN 配置 HTTPS，代理后端端口 $PORT"
echo "请确保："
echo "  1. 域名已解析到当前服务器的公网 IP"
echo "  2. 服务器防火墙（安全组）已开放 80 和 443 端口"
echo ""
read -p "按 Enter 继续，或按 Ctrl+C 取消..."

# 1. 安装 Nginx 和 Certbot
echo "[1/5] 安装 Nginx 和 Certbot..."
apt update
apt install -y nginx certbot python3-certbot-nginx

# 2. 创建临时 Nginx 配置（仅 HTTP，用于验证域名）
echo "[2/5] 创建 Nginx 配置..."
cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# 启用站点
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# 3. 申请 SSL 证书（Certbot 会自动修改配置，增加 HTTPS 并可选重定向）
echo "[3/5] 申请 Let's Encrypt 证书..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email "admin@$DOMAIN" --redirect

# 4. 验证证书续期定时器
echo "[4/5] 检查自动续期状态..."
systemctl enable certbot.timer
systemctl start certbot.timer
systemctl status certbot.timer --no-pager

# 5. 完成
echo "[5/5] 配置完成！"
echo "========================================="
echo "✅ 成功！访问 https://$DOMAIN 即可使用文件上传系统"
echo "证书会自动续期（每天检查两次）"
echo "========================================="
