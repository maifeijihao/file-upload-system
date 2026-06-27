#!/bin/bash

echo "========================================"
echo "文件上传系统安装脚本 (UUID版本) - 含防火墙和服务配置"
echo "========================================"
echo ""

# 检查是否以root运行
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 sudo 运行此脚本: sudo $0"
    exit 1
fi

# 定义项目根目录
PROJECT_ROOT="/opt/file-upload-uuid"
SERVICE_NAME="file-upload-uuid"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# 停止并禁用可能存在的旧服务
echo "0. 清理可能存在的旧服务..."
systemctl stop $SERVICE_NAME 2>/dev/null
systemctl disable $SERVICE_NAME 2>/dev/null
pkill -f "python3 server.py" 2>/dev/null
sleep 2

# 更新系统并安装必要软件
echo "1. 正在更新系统和安装必要软件..."
apt-get update
apt-get install -y python3 python3-pip net-tools uuid-runtime
pip3 install flask

# 创建项目目录
echo "2. 正在创建项目目录..."
mkdir -p $PROJECT_ROOT/uploads
cd $PROJECT_ROOT

# 设置访问密码
echo "3. 设置访问密码..."
echo ""
read -sp "请输入访问密码: " PASSWORD
echo ""
read -sp "请再次确认密码: " PASSWORD_CONFIRM
echo ""

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "错误：两次输入的密码不一致！"
    exit 1
fi

if [ -z "$PASSWORD" ]; then
    echo "错误：密码不能为空！"
    exit 1
fi

# 设置端口
echo ""
echo "4. 设置服务器端口..."
read -p "请输入端口号（默认5555）: " INPUT_PORT
DEFAULT_PORT=${INPUT_PORT:-5555}

if ! [[ "$DEFAULT_PORT" =~ ^[0-9]+$ ]] ; then
    echo "错误：端口必须是数字！"
    exit 1
fi

if [ "$DEFAULT_PORT" -lt 1024 ] || [ "$DEFAULT_PORT" -gt 65535 ]; then
    echo "错误：端口号必须在1024-65535之间！"
    exit 1
fi

# 配置防火墙
echo "5. 配置系统防火墙..."
echo ""
echo "检测并配置防火墙规则..."

# 检查ufw防火墙
if command -v ufw >/dev/null 2>&1; then
    echo "检测到 ufw 防火墙，正在配置..."
    # 检查端口是否已开放
    if ufw status | grep -q "$DEFAULT_PORT/tcp"; then
        echo "端口 $DEFAULT_PORT 已在防火墙中开放"
    else
        echo "正在开放端口 $DEFAULT_PORT..."
        ufw allow $DEFAULT_PORT/tcp
        echo "✅ 端口 $DEFAULT_PORT 已添加到防火墙规则"
    fi
    
    # 检查ufw状态
    UFW_STATUS=$(ufw status | grep -i "status" | awk '{print $2}')
    if [ "$UFW_STATUS" = "inactive" ]; then
        echo "⚠️  ufw防火墙当前处于禁用状态"
        echo "   需要启用防火墙才能生效"
        read -p "是否立即启用ufw防火墙？(y/N): " ENABLE_UFW
        
        if [[ "$ENABLE_UFW" =~ ^[Yy]$ ]]; then
            # 启用ufw并设置默认策略
            ufw --force enable
            echo "✅ ufw防火墙已启用"
        else
            echo "跳过启用防火墙，请手动启用或使用其他防火墙管理工具"
        fi
    else
        echo "✅ ufw防火墙已启用，端口 $DEFAULT_PORT 已开放"
    fi
else
    echo "未检测到 ufw 防火墙，尝试检查 iptables..."
    
    # 检查iptables
    if command -v iptables >/dev/null 2>&1; then
        echo "检测到 iptables，尝试添加规则..."
        
        # 检查是否已有规则
        if iptables -L INPUT -n | grep -q "tcp dpt:$DEFAULT_PORT"; then
            echo "端口 $DEFAULT_PORT 已在 iptables 规则中"
        else
            echo "正在添加 iptables 规则..."
            iptables -A INPUT -p tcp --dport $DEFAULT_PORT -j ACCEPT
            echo "✅ iptables 规则已添加"
            
            # 询问是否保存iptables规则
            read -p "是否保存iptables规则？(需要iptables-persistent)(y/N): " SAVE_IPTABLES
            
            if [[ "$SAVE_IPTABLES" =~ ^[Yy]$ ]]; then
                if command -v iptables-save >/dev/null 2>&1; then
                    # 尝试保存规则
                    iptables-save > /etc/iptables/rules.v4
                    echo "✅ iptables规则已保存"
                else
                    echo "⚠️  未找到iptables-save命令，无法保存规则"
                    echo "   重启后规则将失效，请手动保存或安装iptables-persistent"
                fi
            fi
        fi
    else
        echo "未检测到 iptables，跳过防火墙配置"
    fi
fi

# 创建防火墙管理脚本
echo "6. 创建防火墙管理脚本..."
cat > $PROJECT_ROOT/firewall-setup.sh << FIREWALL_EOF
#!/bin/bash
echo "=== 防火墙配置工具 ==="
echo ""

if [ "\$EUID" -ne 0 ]; then 
    echo "请使用 sudo 运行此脚本: sudo ./firewall-setup.sh"
    exit 1
fi

PORT=\$(grep "DEFAULT_PORT = " config.py | cut -d'=' -f2 | tr -d ' ')

if [ -z "\$PORT" ]; then
    echo "错误：无法从配置文件中获取端口号"
    exit 1
fi

echo "检测到配置端口: \$PORT"
echo ""
echo "请选择操作:"
echo "1. 开放端口 \$PORT (允许外部访问)"
echo "2. 关闭端口 \$PORT (禁止外部访问)"
echo "3. 检查当前防火墙状态"
echo "4. 显示当前端口状态"
echo "5. 退出"
echo ""
read -p "请输入选择 (1-5): " CHOICE

case \$CHOICE in
    1)
        echo "正在开放端口 \$PORT..."
        
        # 检查并配置ufw
        if command -v ufw >/dev/null 2>&1; then
            ufw allow \$PORT/tcp
            echo "✅ 已添加ufw规则"
            
            # 检查ufw状态
            UFW_STATUS=\$(ufw status | grep -i "status" | awk '{print \$2}')
            if [ "\$UFW_STATUS" = "inactive" ]; then
                echo "⚠️  ufw防火墙当前处于禁用状态"
                read -p "是否启用ufw防火墙？(y/N): " ENABLE
                if [[ "\$ENABLE" =~ ^[Yy]$ ]]; then
                    ufw --force enable
                    echo "✅ ufw防火墙已启用"
                fi
            fi
        fi
        
        # 检查并配置iptables
        if command -v iptables >/dev/null 2>&1; then
            if ! iptables -L INPUT -n | grep -q "tcp dpt:\$PORT"; then
                iptables -A INPUT -p tcp --dport \$PORT -j ACCEPT
                echo "✅ 已添加iptables规则"
                
                # 询问是否保存
                read -p "是否保存iptables规则？(y/N): " SAVE
                if [[ "\$SAVE" =~ ^[Yy]$ ]] && command -v iptables-save >/dev/null 2>&1; then
                    iptables-save > /etc/iptables/rules.v4 2>/dev/null && echo "✅ 规则已保存" || echo "⚠️  保存失败"
                fi
            else
                echo "端口 \$PORT 已在iptables规则中"
            fi
        fi
        
        echo ""
        echo "✅ 端口 \$PORT 已配置完成"
        echo "注意：云服务器还需要在控制台安全组中开放此端口"
        ;;
        
    2)
        echo "正在关闭端口 \$PORT..."
        
        if command -v ufw >/dev/null 2>&1; then
            ufw delete allow \$PORT/tcp 2>/dev/null
            echo "✅ 已移除ufw规则"
        fi
        
        if command -v iptables >/dev/null 2>&1; then
            iptables -D INPUT -p tcp --dport \$PORT -j ACCEPT 2>/dev/null
            echo "✅ 已移除iptables规则"
            
            # 保存iptables规则
            if command -v iptables-save >/dev/null 2>&1; then
                iptables-save > /etc/iptables/rules.v4 2>/dev/null
            fi
        fi
        
        echo "✅ 端口 \$PORT 已关闭"
        ;;
        
    3)
        echo "=== 防火墙状态 ==="
        
        if command -v ufw >/dev/null 2>&1; then
            echo "ufw状态:"
            ufw status
            echo ""
        fi
        
        if command -v iptables >/dev/null 2>&1; then
            echo "iptables规则 (端口相关):"
            iptables -L INPUT -n | grep "tcp" | grep "dpt"
        fi
        ;;
        
    4)
        echo "=== 端口 \$PORT 状态 ==="
        
        # 检查监听状态
        echo "监听状态:"
        if netstat -tln 2>/dev/null | grep -q ":\$PORT "; then
            echo "✅ 端口 \$PORT 正在监听"
            netstat -tln | grep ":\$PORT "
        else
            echo "❌ 端口 \$PORT 未监听"
        fi
        
        # 检查防火墙规则
        echo ""
        echo "防火墙规则:"
        
        if command -v ufw >/dev/null 2>&1; then
            if ufw status | grep -q "\$PORT/tcp"; then
                echo "✅ ufw: 端口 \$PORT 已开放"
            else
                echo "❌ ufw: 端口 \$PORT 未开放"
            fi
        fi
        
        if command -v iptables >/dev/null 2>&1; then
            if iptables -L INPUT -n | grep -q "tcp dpt:\$PORT"; then
                echo "✅ iptables: 端口 \$PORT 已开放"
            else
                echo "❌ iptables: 端口 \$PORT 未开放"
            fi
        fi
        ;;
        
    5)
        echo "退出"
        ;;
        
    *)
        echo "无效选择"
        ;;
esac
FIREWALL_EOF

chmod +x $PROJECT_ROOT/firewall-setup.sh

# 创建配置文件
echo "7. 创建配置文件..."
cat > $PROJECT_ROOT/config.py << CONFIG_END
import hashlib
import socket

# 密码设置（安装时设置）
ADMIN_PASSWORD = "$PASSWORD"

# 端口设置
DEFAULT_PORT = $DEFAULT_PORT

def verify_password(input_password):
    """验证密码"""
    return input_password == ADMIN_PASSWORD

def find_available_port(start_port):
    """寻找可用端口"""
    port = start_port
    max_port = start_port + 100  # 最多尝试100个端口
    
    while port <= max_port:
        try:
            # 尝试绑定端口
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(('0.0.0.0', port))
            sock.close()
            return port
        except OSError:
            port += 1
            continue
    
    # 如果没有找到可用端口，返回None
    return None
CONFIG_END

# 创建UUID版本的后端服务器
echo "8. 正在创建后端服务器 (UUID版本)..."
cat > $PROJECT_ROOT/server.py << SERVER_END
from flask import Flask, request, send_file, jsonify, send_from_directory, session
import os
import hashlib
import socket
import uuid
import json
import time
from datetime import datetime, timezone, timedelta  # 新增：时区处理
from config import verify_password, find_available_port, DEFAULT_PORT

app = Flask(__name__)

# 设置密钥（用于session）
app.secret_key = os.urandom(24)

UPLOAD_FOLDER = 'uploads'
MAPPING_FILE = 'file_mapping.json'
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = 1024 * 1024 * 1024  # 1GB

# 确保上传目录存在
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# ========== 定义北京时间时区 ==========
BEIJING_TZ = timezone(timedelta(hours=8))

def format_beijing_time(timestamp):
    """将时间戳格式化为北京时间字符串"""
    dt = datetime.fromtimestamp(timestamp, tz=BEIJING_TZ)
    return dt.strftime('%Y-%m-%d %H:%M:%S')

def require_auth():
    """检查是否已登录"""
    return session.get('authenticated', False)

def generate_uuid_filename(original_filename):
    """生成UUID文件名，保留扩展名"""
    _, extension = os.path.splitext(original_filename)
    if original_filename.lower().endswith('.tar.gz'):
        extension = '.tar.gz'
    file_uuid = str(uuid.uuid4())
    return f"{file_uuid}{extension}"

def save_file_mapping(uuid_filename, original_filename, file_size):
    """保存文件映射关系"""
    mapping_file = os.path.join(app.config['UPLOAD_FOLDER'], '..', MAPPING_FILE)
    mappings = {}
    if os.path.exists(mapping_file):
        try:
            with open(mapping_file, 'r', encoding='utf-8') as f:
                mappings = json.load(f)
        except:
            pass
    # 存储上传时的时间戳（秒）
    mappings[uuid_filename] = {
        'original_name': original_filename,
        'size': file_size,
        'upload_time': time.time()  # 记录上传时刻的时间戳
    }
    try:
        with open(mapping_file, 'w', encoding='utf-8') as f:
            json.dump(mappings, f, ensure_ascii=False, indent=2)
    except:
        pass
    return mappings

def get_original_filename(uuid_filename):
    """获取原始文件名"""
    mapping_file = os.path.join(app.config['UPLOAD_FOLDER'], '..', MAPPING_FILE)
    if os.path.exists(mapping_file):
        try:
            with open(mapping_file, 'r', encoding='utf-8') as f:
                mappings = json.load(f)
            if uuid_filename in mappings:
                return mappings[uuid_filename].get('original_name', uuid_filename)
        except:
            pass
    return uuid_filename

def get_all_file_mappings():
    """获取所有文件映射"""
    mapping_file = os.path.join(app.config['UPLOAD_FOLDER'], '..', MAPPING_FILE)
    if os.path.exists(mapping_file):
        try:
            with open(mapping_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except:
            pass
    return {}

@app.route('/')
def index():
    return send_from_directory('.', 'index.html')

@app.route('/login', methods=['POST'])
def login():
    data = request.json
    if not data or 'password' not in data:
        return jsonify({'success': False, 'message': '密码不能为空'}), 400
    if verify_password(data['password']):
        session['authenticated'] = True
        return jsonify({'success': True}), 200
    else:
        return jsonify({'success': False, 'message': '密码错误'}), 401

@app.route('/logout', methods=['POST'])
def logout():
    session.pop('authenticated', None)
    return jsonify({'success': True}), 200

@app.route('/check_auth')
def check_auth():
    return jsonify({'authenticated': session.get('authenticated', False)}), 200

@app.route('/upload', methods=['POST'])
def upload_file():
    if not require_auth():
        return jsonify({'success': False, 'message': '未授权访问'}), 401
    if 'file' not in request.files:
        return jsonify({'success': False, 'message': '没有选择文件'}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({'success': False, 'message': '没有选择文件'}), 400

    file.seek(0, 2)
    file_size = file.tell()
    file.seek(0)
    if file_size > 1024 * 1024 * 1024:
        return jsonify({'success': False, 'message': '文件超过1GB大小限制'}), 400

    allowed_extensions = {'.zip', '.rar', '.7z', '.tar', '.gz', '.tar.gz'}
    original_filename = file.filename
    file_ext = os.path.splitext(original_filename)[1].lower()
    if file_ext == '.gz' and original_filename.lower().endswith('.tar.gz'):
        file_ext = '.tar.gz'
    if file_ext not in allowed_extensions:
        return jsonify({'success': False, 'message': '不支持的文件格式'}), 400

    try:
        uuid_filename = generate_uuid_filename(original_filename)
        base_name, extension = os.path.splitext(uuid_filename)
        counter = 1
        while os.path.exists(os.path.join(app.config['UPLOAD_FOLDER'], uuid_filename)):
            uuid_filename = f"{base_name}_{counter}{extension}"
            counter += 1

        save_path = os.path.join(app.config['UPLOAD_FOLDER'], uuid_filename)
        file.save(save_path)

        # 保存映射（已记录时间戳）
        save_file_mapping(uuid_filename, original_filename, file_size)

        # 获取当前北京时间字符串
        upload_time_str = format_beijing_time(time.time())

        return jsonify({
            'success': True,
            'message': '上传成功',
            'uuid_filename': uuid_filename,
            'original_name': original_filename,
            'size': file_size,
            'upload_time': upload_time_str   # 返回北京时间
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': f'上传失败: {str(e)}'}), 500

@app.route('/files')
def list_files():
    if not require_auth():
        return jsonify({'success': False, 'message': '未授权访问'}), 401

    mappings = get_all_file_mappings()
    files = []
    for filename in os.listdir(app.config['UPLOAD_FOLDER']):
        path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        if os.path.isfile(path):
            file_info = mappings.get(filename, {})
            original_name = file_info.get('original_name', filename)
            file_size = file_info.get('size', os.path.getsize(path))

            # 获取上传时间戳
            upload_ts = file_info.get('upload_time')
            if upload_ts is None:
                upload_ts = os.path.getmtime(path)
            # 转换为北京时间字符串
            upload_time_str = format_beijing_time(upload_ts)

            files.append({
                'uuid': filename,
                'name': original_name,
                'original_name': original_name,
                'size': file_size,
                'filename': filename,
                'url': f'/download/{filename}',
                'is_uuid': True,
                'upload_time': upload_time_str   # 北京时间
            })

    return jsonify({'success': True, 'files': files}), 200

@app.route('/download/<filename>')
def download_file(filename):
    try:
        path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        if not os.path.exists(path):
            return jsonify({'success': False, 'message': '文件不存在'}), 404
        original_filename = get_original_filename(filename)
        return send_file(
            path,
            as_attachment=True,
            download_name=original_filename,
            mimetype='application/octet-stream'
        )
    except Exception as e:
        return jsonify({'success': False, 'message': f'下载失败: {str(e)}'}), 500

if __name__ == '__main__':
    port = find_available_port(DEFAULT_PORT)
    if port is None:
        print(f"错误：从端口{DEFAULT_PORT}开始，没有找到可用端口！")
        exit(1)
    if port != DEFAULT_PORT:
        print(f"端口{DEFAULT_PORT}被占用，使用端口{port}")
    print("文件上传系统启动成功！(UUID版本)")
    print(f"项目目录: {os.path.dirname(os.path.abspath(__file__))}")
    print(f"访问地址: http://0.0.0.0:{port}")
    print(f"上传目录: {os.path.join(os.path.dirname(os.path.abspath(__file__)), 'uploads')}")
    print(f"文件映射: {os.path.join(os.path.dirname(os.path.abspath(__file__)), 'file_mapping.json')}")
    print("")
    print("✅ 文件上传系统已启用UUID文件名模式！")
    print("   上传的文件会自动重命名为UUID格式，但下载时仍显示原始文件名。")
    print("   前端显示原始文件名，下载链接使用UUID格式。")
    app.run(host='0.0.0.0', port=port, debug=False)
SERVER_END

# 创建简单的提示页面
echo "9. 创建简单的提示页面..."
cat > $PROJECT_ROOT/index.html << HTML_END
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>文件上传系统</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 40px 20px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            border-radius: 10px;
            padding: 40px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            text-align: center;
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
        }
        .icon {
            font-size: 64px;
            margin-bottom: 20px;
            color: #4a90e2;
        }
        .warning-box {
            background-color: #fff3cd;
            border-left: 4px solid #ffc107;
            color: #856404;
            padding: 15px;
            margin: 20px 0;
            text-align: left;
        }
        .info-box {
            background-color: #f8f9fa;
            border-left: 4px solid #4a90e2;
            padding: 15px;
            margin: 20px 0;
            text-align: left;
        }
        .steps {
            text-align: left;
            margin: 20px 0;
            padding-left: 20px;
        }
        .steps li {
            margin: 10px 0;
        }
        .code {
            background-color: #f1f1f1;
            padding: 2px 5px;
            border-radius: 3px;
            font-family: monospace;
        }
        .firewall-note {
            background-color: #d4edda;
            border-left: 4px solid #28a745;
            color: #155724;
            padding: 15px;
            margin: 20px 0;
            text-align: left;
        }
        .service-note {
            background-color: #e7f3ff;
            border-left: 4px solid #1890ff;
            color: #0d47a1;
            padding: 15px;
            margin: 20px 0;
            text-align: left;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">📁</div>
        <h1>文件上传系统</h1>
        
        <div class="service-note">
            <strong>✅ 系统服务已配置！</strong>
            <p>服务已在后台运行，关闭终端后不会停止。</p>
            <p>系统重启后会自动启动。</p>
            <p>管理命令：<span class="code">sudo systemctl status file-upload-uuid</span></p>
        </div>
        
        <div class="firewall-note">
            <strong>防火墙已自动配置！</strong>
            系统已尝试自动配置防火墙规则。如果无法访问，请检查：
            <ol>
                <li>云服务器安全组设置（控制台）</li>
                <li>系统防火墙状态</li>
                <li>使用 <span class="code">./firewall-setup.sh</span> 检查配置</li>
            </ol>
        </div>
        
        <div class="warning-box">
            <strong>重要提示：</strong>
            这是一个临时页面，请上传你自己的index.html文件以启用完整功能！
        </div>
        
        <div class="info-box">
            <h3>系统已安装成功！</h3>
            <p>后端服务器已启动并运行正常。</p>
            <p>请按照以下步骤上传你的自定义界面：</p>
        </div>
        
        <div>
            <h3>安装步骤：</h3>
            <ol class="steps">
                <li>将你的 <span class="code">index.html</span> 文件上传到服务器</li>
                <li>复制到安装目录：<span class="code">sudo cp /path/to/your/index.html $PROJECT_ROOT/</span></li>
                <li>重启服务：<span class="code">sudo systemctl restart file-upload-uuid</span></li>
                <li>刷新此页面查看效果</li>
            </ol>
        </div>
        
        <div class="info-box">
            <h3>服务管理命令：</h3>
            <ul class="steps">
                <li>查看状态：<span class="code">sudo systemctl status file-upload-uuid</span></li>
                <li>启动服务：<span class="code">sudo systemctl start file-upload-uuid</span></li>
                <li>停止服务：<span class="code">sudo systemctl stop file-upload-uuid</span></li>
                <li>重启服务：<span class="code">sudo systemctl restart file-upload-uuid</span></li>
                <li>查看日志：<span class="code">sudo journalctl -u file-upload-uuid -f</span></li>
                <li>开机自启：<span class="code">sudo systemctl enable file-upload-uuid</span></li>
                <li>禁用自启：<span class="code">sudo systemctl disable file-upload-uuid</span></li>
            </ul>
            
            <h3>脚本管理命令：</h3>
            <ul class="steps">
                <li>修改密码：<span class="code">sudo ./change-password.sh</span></li>
                <li>防火墙管理：<span class="code">sudo ./firewall-setup.sh</span></li>
                <li>清理文件：<span class="code">./cleanup.sh</span></li>
            </ul>
        </div>
        
        <div style="margin-top: 30px;">
            <p>安装目录：<span class="code">$PROJECT_ROOT</span></p>
            <p>上传目录：<span class="code">$PROJECT_ROOT/uploads</span></p>
            <p>服务文件：<span class="code">/etc/systemd/system/file-upload-uuid.service</span></p>
        </div>
    </div>
</body>
</html>
HTML_END

# 创建启动脚本（前台运行）
echo "10. 创建前台启动脚本..."
cat > $PROJECT_ROOT/start.sh << START_EOF
#!/bin/bash
cd $PROJECT_ROOT
echo "启动文件上传系统（前台运行）..."
echo "按 Ctrl+C 停止"
python3 server.py
START_EOF

chmod +x $PROJECT_ROOT/start.sh

# 创建后台启动脚本
echo "11. 创建后台启动脚本..."
cat > $PROJECT_ROOT/start-background.sh << START_BG_EOF
#!/bin/bash
cd $PROJECT_ROOT
echo "启动文件上传系统（后台运行）..."
nohup python3 server.py > server.log 2>&1 &
echo "进程PID: \$!"
echo "日志文件: $PROJECT_ROOT/server.log"
echo "查看日志: tail -f server.log"
echo "停止命令: pkill -f 'python3 server.py'"
START_BG_EOF

chmod +x $PROJECT_ROOT/start-background.sh

# 创建停止脚本
echo "12. 创建停止脚本..."
cat > $PROJECT_ROOT/stop.sh << STOP_EOF
#!/bin/bash
echo "正在停止文件上传系统..."
pkill -f "python3 server.py" 2>/dev/null
sleep 2
echo "已停止前台进程"

# 同时停止systemd服务（如果存在）
if systemctl is-active --quiet file-upload-uuid 2>/dev/null; then
    echo "停止systemd服务..."
    systemctl stop file-upload-uuid
fi
STOP_EOF

chmod +x $PROJECT_ROOT/stop.sh

# 创建重启脚本
echo "13. 创建重启脚本..."
cat > $PROJECT_ROOT/restart.sh << RESTART_EOF
#!/bin/bash
cd $PROJECT_ROOT
./stop.sh
sleep 1
echo "重新启动..."
./start-background.sh
RESTART_EOF

chmod +x $PROJECT_ROOT/restart.sh

# 创建修改密码脚本
echo "14. 创建密码修改脚本..."
cat > $PROJECT_ROOT/change-password.sh << CHANGE_PASS_EOF
#!/bin/bash

if [ "\$EUID" -ne 0 ]; then 
    echo "请使用 sudo 运行此脚本: sudo ./change-password.sh"
    exit 1
fi

cd $PROJECT_ROOT

echo "=== 修改文件上传系统密码 ==="
echo ""
read -sp "请输入新密码: " NEW_PASSWORD
echo ""
read -sp "请再次确认新密码: " NEW_PASSWORD_CONFIRM
echo ""

if [ "\$NEW_PASSWORD" != "\$NEW_PASSWORD_CONFIRM" ]; then
    echo "错误：两次输入的密码不一致！"
    exit 1
fi

if [ -z "\$NEW_PASSWORD" ]; then
    echo "错误：密码不能为空！"
    exit 1
fi

# 更新配置文件
OLD_PORT=\$(grep "DEFAULT_PORT = " config.py | cut -d'=' -f2 | tr -d ' ')

cat > config.py << CONFIG_UPDATE_END
import hashlib
import socket

# 密码设置（安装时设置）
ADMIN_PASSWORD = "\$NEW_PASSWORD"

# 端口设置（保持原端口）
DEFAULT_PORT = \$OLD_PORT

def verify_password(input_password):
    """验证密码"""
    return input_password == ADMIN_PASSWORD

def find_available_port(start_port):
    """寻找可用端口"""
    port = start_port
    max_port = start_port + 100  # 最多尝试100个端口
    
    while port <= max_port:
        try:
            # 尝试绑定端口
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(('0.0.0.0', port))
            sock.close()
            return port
        except OSError:
            port += 1
            continue
    
    # 如果没有找到可用端口，返回None
    return None
CONFIG_UPDATE_END

echo "✅ 密码修改成功！"

# 重启服务使新密码生效
if systemctl is-active --quiet file-upload-uuid 2>/dev/null; then
    echo "重启systemd服务..."
    systemctl restart file-upload-uuid
    echo "服务已重启，新密码立即生效。"
else
    echo "需要重启服务才能使新密码生效。"
    echo "重启命令:"
    echo "cd $PROJECT_ROOT && ./restart.sh"
fi
CHANGE_PASS_EOF

chmod +x $PROJECT_ROOT/change-password.sh

# 创建查看状态脚本
echo "15. 创建查看状态脚本..."
cat > $PROJECT_ROOT/status.sh << STATUS_EOF
#!/bin/bash
echo "=== 文件上传系统状态 (UUID版本) ==="
echo ""

# 检查systemd服务状态
if systemctl is-active --quiet file-upload-uuid 2>/dev/null; then
    echo "✅ 服务状态: systemd服务运行中"
    
    # 获取端口信息
    PORT=\$(grep "DEFAULT_PORT = " config.py | cut -d'=' -f2 | tr -d ' ')
    
    if [ -n "\$PORT" ]; then
        echo "📡 配置端口: \$PORT"
        
        # 检查端口是否在监听
        if netstat -tln 2>/dev/null | grep -q ":\$PORT "; then
            echo "✅ 端口状态: 正在监听"
        else
            echo "❌ 端口状态: 未监听"
        fi
    fi
    
    # 显示systemd服务状态
    echo ""
    echo "=== systemd服务状态 ==="
    systemctl status file-upload-uuid --no-pager -l
    
elif pgrep -f "python3 server.py" > /dev/null; then
    echo "✅ 服务状态: 后台进程运行中"
    
    # 获取端口信息
    PORT=\$(netstat -tlnp 2>/dev/null | grep "python3" | grep "server.py" | awk '{print \$4}' | cut -d':' -f2 | head -1)
    
    if [ -n "\$PORT" ]; then
        echo "📡 运行端口: \$PORT"
    else
        PORT_INFO=\$(ps aux | grep "python3 server.py" | grep -v grep | tr -s ' ' | cut -d' ' -f22 | grep -o "[0-9]*\$")
        if [ -n "\$PORT_INFO" ]; then
            echo "📡 运行端口: \$PORT_INFO"
            PORT=\$PORT_INFO
        else
            echo "📡 运行端口: 获取中..."
        fi
    fi
else
    echo "❌ 服务状态: 未运行"
    echo ""
    echo "启动命令:"
    echo "- 前台启动: cd $PROJECT_ROOT && ./start.sh"
    echo "- 后台启动: cd $PROJECT_ROOT && ./start-background.sh"
    echo "- systemd启动: sudo systemctl start file-upload-uuid"
fi

# 获取IP地址
IP_ADDRESS=\$(hostname -I | awk '{print \$1}')
if [ -n "\$PORT" ]; then
    echo "🌐 访问地址: http://\$IP_ADDRESS:\$PORT"
    echo "🌐 本地访问: http://localhost:\$PORT"
fi

# 统计上传文件
if [ -d "$PROJECT_ROOT/uploads" ]; then
    FILE_COUNT=\$(ls $PROJECT_ROOT/uploads/ 2>/dev/null | wc -l)
    echo "📁 文件数量: \$FILE_COUNT"
    
    TOTAL_SIZE=\$(du -sh $PROJECT_ROOT/uploads 2>/dev/null | cut -f1)
    echo "💾 总大小: \$TOTAL_SIZE"
fi

# 检查映射文件
if [ -f "$PROJECT_ROOT/file_mapping.json" ]; then
    MAPPING_COUNT=\$(grep -c '"original_name"' $PROJECT_ROOT/file_mapping.json 2>/dev/null || echo "0")
    echo "🗂️  文件映射: \$MAPPING_COUNT 条记录"
fi

# 检查防火墙状态
if [ -n "\$PORT" ]; then
    echo ""
    echo "=== 防火墙状态 (端口 \$PORT) ==="
    
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "\$PORT/tcp"; then
            echo "✅ ufw: 端口 \$PORT 已开放"
        else
            echo "❌ ufw: 端口 \$PORT 未开放"
        fi
    fi
    
    if command -v iptables >/dev/null 2>&1; then
        if iptables -L INPUT -n 2>/dev/null | grep -q "tcp dpt:\$PORT"; then
            echo "✅ iptables: 端口 \$PORT 已开放"
        else
            echo "❌ iptables: 端口 \$PORT 未开放"
        fi
    fi
fi

echo ""
echo "=== 管理命令 ==="
echo "服务管理:"
echo "- 启动: sudo systemctl start file-upload-uuid"
echo "- 停止: sudo systemctl stop file-upload-uuid"
echo "- 重启: sudo systemctl restart file-upload-uuid"
echo "- 状态: sudo systemctl status file-upload-uuid"
echo "- 日志: sudo journalctl -u file-upload-uuid -f"
echo "- 自启: sudo systemctl enable file-upload-uuid"
echo "- 禁用: sudo systemctl disable file-upload-uuid"
echo ""
echo "脚本管理:"
echo "- 修改密码: sudo ./change-password.sh"
echo "- 防火墙管理: sudo ./firewall-setup.sh"
echo "- 清理文件: ./cleanup.sh"
echo "- 前台启动: ./start.sh"
echo "- 后台启动: ./start-background.sh"
echo "- 停止进程: ./stop.sh"
STATUS_EOF

chmod +x $PROJECT_ROOT/status.sh

# 创建清理脚本
echo "16. 创建清理脚本..."
cat > $PROJECT_ROOT/cleanup.sh << CLEANUP_EOF
#!/bin/bash
echo "=== 清理文件上传系统 ==="
echo "警告：此操作将删除所有上传的文件！"
echo ""

read -p "确定要清理所有文件吗？(y/N): " CONFIRM

if [[ "\$CONFIRM" != "y" && "\$CONFIRM" != "Y" ]]; then
    echo "操作取消"
    exit 0
fi

cd $PROJECT_ROOT

# 停止服务
./stop.sh

# 删除上传的文件
rm -rf uploads/*
rm -f file_mapping.json
rm -f server.log 2>/dev/null

# 重新创建目录
mkdir -p uploads

echo ""
echo "✅ 所有文件已清理！"
echo "现在可以重新启动服务:"
echo "前台启动: ./start.sh"
echo "后台启动: ./start-background.sh"
echo "systemd启动: sudo systemctl start file-upload-uuid"
CLEANUP_EOF

chmod +x $PROJECT_ROOT/cleanup.sh

# 创建systemd服务文件
echo "17. 创建systemd服务文件..."
cat > $SERVICE_FILE << SERVICE_EOF
[Unit]
Description=File Upload System (UUID Version)
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_ROOT
ExecStart=/usr/bin/python3 $PROJECT_ROOT/server.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

# 环境变量
Environment="PYTHONUNBUFFERED=1"

# 安全设置
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$PROJECT_ROOT/uploads $PROJECT_ROOT

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 设置目录权限
echo "18. 设置目录权限..."
chmod -R 755 $PROJECT_ROOT
chmod 777 $PROJECT_ROOT/uploads

# 重新加载systemd并启动服务
echo "19. 配置并启动系统服务..."
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# 等待服务启动
sleep 3

# 检查服务状态
SERVICE_STATUS=$(systemctl is-active $SERVICE_NAME)

# 获取服务器IP
IP_ADDRESS=$(hostname -I | awk '{print $1}')

echo ""
echo "========================================"
echo "✅ UUID版本文件上传系统安装完成！"
echo "========================================"
echo ""
echo "重要信息："
echo "1. 你设置的密码为: $PASSWORD"
echo "2. 起始端口设置为: $DEFAULT_PORT"
echo "3. 项目目录: $PROJECT_ROOT"
echo "4. 系统使用UUID文件名存储文件"
echo "   - 前端显示：原始文件名"
echo "   - 下载链接：UUID格式"
echo "   - 下载时显示：原始文件名"
echo ""
echo "服务状态：$SERVICE_STATUS"
echo ""

if [ "$SERVICE_STATUS" = "active" ]; then
    echo "✅ 服务已成功启动并运行在后台！"
    echo "✅ 系统重启后会自动启动"
    echo ""
    echo "访问地址: http://$IP_ADDRESS:$DEFAULT_PORT"
    echo "本地访问: http://localhost:$DEFAULT_PORT"
else
    echo "⚠️  服务启动可能有问题，请检查状态"
    echo "查看服务状态: sudo systemctl status $SERVICE_NAME"
    echo "查看服务日志: sudo journalctl -u $SERVICE_NAME -f"
fi

echo ""
echo "防火墙配置："
echo "✅ 已尝试自动配置系统防火墙"
echo "⚠️  如果仍无法访问，请检查："
echo "   1. 云服务器安全组（控制台）"
echo "   2. 使用防火墙管理工具: sudo ./firewall-setup.sh"
echo ""
echo "=== 服务管理命令 ==="
echo "1. 查看服务状态: sudo systemctl status $SERVICE_NAME"
echo "2. 启动/停止/重启服务: sudo systemctl start|stop|restart $SERVICE_NAME"
echo "3. 查看实时日志: sudo journalctl -u $SERVICE_NAME -f"
echo "4. 查看所有日志: sudo journalctl -u $SERVICE_NAME"
echo "5. 启用开机自启: sudo systemctl enable $SERVICE_NAME"
echo "6. 禁用开机自启: sudo systemctl disable $SERVICE_NAME"
echo ""
echo "=== 脚本管理命令 ==="
echo "- 查看详细状态: cd $PROJECT_ROOT && ./status.sh"
echo "- 修改密码: cd $PROJECT_ROOT && sudo ./change-password.sh"
echo "- 防火墙管理: cd $PROJECT_ROOT && sudo ./firewall-setup.sh"
echo "- 清理文件: cd $PROJECT_ROOT && ./cleanup.sh"
echo "- 前台运行: cd $PROJECT_ROOT && ./start.sh"
echo "- 后台运行: cd $PROJECT_ROOT && ./start-background.sh"
echo ""
echo "安装目录: $PROJECT_ROOT"
echo "上传目录: $PROJECT_ROOT/uploads"
echo "映射文件: $PROJECT_ROOT/file_mapping.json"
echo "服务文件: $SERVICE_FILE"
echo ""

if [ "$SERVICE_STATUS" != "active" ]; then
    echo "⚠️  尝试手动启动服务..."
    echo "cd $PROJECT_ROOT && ./start-background.sh"
    echo "或检查端口是否被占用"
fi
