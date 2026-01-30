#!/bin/bash

echo "========================================"
echo "文件上传系统安装脚本 (UUID版本) - 含防火墙配置"
echo "========================================"
echo ""

# 检查是否以root运行
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 sudo 运行此脚本: sudo $0"
    exit 1
fi

# 定义项目根目录
PROJECT_ROOT="/opt/file-upload-uuid"

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

def require_auth():
    """检查是否已登录"""
    return session.get('authenticated', False)

def generate_uuid_filename(original_filename):
    """生成UUID文件名，保留扩展名"""
    # 获取文件扩展名
    _, extension = os.path.splitext(original_filename)
    
    # 特殊处理 .tar.gz
    if original_filename.lower().endswith('.tar.gz'):
        extension = '.tar.gz'
    
    # 生成UUID
    file_uuid = str(uuid.uuid4())
    
    # 返回UUID + 扩展名
    return f"{file_uuid}{extension}"

def save_file_mapping(uuid_filename, original_filename, file_size):
    """保存文件映射关系"""
    mapping_file = os.path.join(app.config['UPLOAD_FOLDER'], '..', MAPPING_FILE)
    
    # 读取现有映射
    mappings = {}
    if os.path.exists(mapping_file):
        try:
            with open(mapping_file, 'r', encoding='utf-8') as f:
                mappings = json.load(f)
        except:
            pass
    
    # 添加新映射
    mappings[uuid_filename] = {
        'original_name': original_filename,
        'size': file_size,
        'upload_time': os.path.getmtime(os.path.join(app.config['UPLOAD_FOLDER'], uuid_filename))
    }
    
    # 保存映射
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
    """登录验证"""
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
    """退出登录"""
    session.pop('authenticated', None)
    return jsonify({'success': True}), 200

@app.route('/check_auth')
def check_auth():
    """检查登录状态"""
    return jsonify({'authenticated': session.get('authenticated', False)}), 200

@app.route('/upload', methods=['POST'])
def upload_file():
    """上传文件（需要登录）"""
    if not require_auth():
        return jsonify({'success': False, 'message': '未授权访问'}), 401
    
    if 'file' not in request.files:
        return jsonify({'success': False, 'message': '没有选择文件'}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({'success': False, 'message': '没有选择文件'}), 400
    
    # 检查文件大小（限制为1GB）
    file.seek(0, 2)  # 移动到文件末尾
    file_size = file.tell()
    file.seek(0)  # 移回文件开头
    
    if file_size > 1024 * 1024 * 1024:  # 1GB
        return jsonify({'success': False, 'message': '文件超过1GB大小限制'}), 400
    
    # 检查文件类型
    allowed_extensions = {'.zip', '.rar', '.7z', '.tar', '.gz', '.tar.gz'}
    original_filename = file.filename
    file_ext = os.path.splitext(original_filename)[1].lower()
    
    if file_ext == '.gz' and original_filename.lower().endswith('.tar.gz'):
        file_ext = '.tar.gz'
    
    if file_ext not in allowed_extensions:
        return jsonify({'success': False, 'message': '不支持的文件格式'}), 400
    
    try:
        # 生成UUID文件名
        uuid_filename = generate_uuid_filename(original_filename)
        
        # 确保文件名唯一（理论上UUID已经唯一，但以防万一）
        counter = 1
        base_name, extension = os.path.splitext(uuid_filename)
        
        while os.path.exists(os.path.join(app.config['UPLOAD_FOLDER'], uuid_filename)):
            uuid_filename = f"{base_name}_{counter}{extension}"
            counter += 1
        
        # 保存文件
        file.save(os.path.join(app.config['UPLOAD_FOLDER'], uuid_filename))
        
        # 保存映射关系
        save_file_mapping(uuid_filename, original_filename, file_size)
        
        return jsonify({
            'success': True, 
            'message': '上传成功', 
            'uuid_filename': uuid_filename,
            'original_name': original_filename,
            'size': file_size
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': f'上传失败: {str(e)}'}), 500

@app.route('/files')
def list_files():
    """获取文件列表（需要登录）"""
    if not require_auth():
        return jsonify({'success': False, 'message': '未授权访问'}), 401
    
    # 获取所有映射
    mappings = get_all_file_mappings()
    files = []
    
    # 遍历上传目录
    for filename in os.listdir(app.config['UPLOAD_FOLDER']):
        path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        if os.path.isfile(path):
            # 从映射中获取原始文件名
            file_info = mappings.get(filename, {})
            original_name = file_info.get('original_name', filename)
            file_size = file_info.get('size', os.path.getsize(path))
            
            files.append({
                'uuid': filename,
                'name': original_name,
                'original_name': original_name,
                'size': file_size,
                'filename': filename,
                'url': f'/download/{filename}',
                'is_uuid': True
            })
    
    return jsonify({'success': True, 'files': files}), 200

@app.route('/download/<filename>')
def download_file(filename):
    """下载文件"""
    try:
        path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        if not os.path.exists(path):
            return jsonify({'success': False, 'message': '文件不存在'}), 404
        
        # 获取原始文件名
        original_filename = get_original_filename(filename)
        
        # 设置下载时的文件名
        download_name = original_filename
        
        return send_file(
            path,
            as_attachment=True,
            download_name=download_name,
            mimetype='application/octet-stream'
        )
    except Exception as e:
        return jsonify({'success': False, 'message': f'下载失败: {str(e)}'}), 500

if __name__ == '__main__':
    # 寻找可用端口
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

# 创建启动脚本
echo "10. 创建启动脚本..."
cat > $PROJECT_ROOT/start.sh << START_EOF
#!/bin/bash
cd $PROJECT_ROOT
python3 server.py
START_EOF

chmod +x $PROJECT_ROOT/start.sh

# 创建停止脚本
echo "11. 创建停止脚本..."
cat > $PROJECT_ROOT/stop.sh << STOP_EOF
#!/bin/bash
echo "正在停止文件上传系统..."
pkill -f "python3 server.py" 2>/dev/null
sleep 2
echo "已停止"
STOP_EOF

chmod +x $PROJECT_ROOT/stop.sh

# 创建重启脚本
echo "12. 创建重启脚本..."
cat > $PROJECT_ROOT/restart.sh << RESTART_EOF
#!/bin/bash
cd $PROJECT_ROOT
./stop.sh
sleep 1
./start.sh
RESTART_EOF

chmod +x $PROJECT_ROOT/restart.sh

# 创建修改密码脚本
echo "13. 创建密码修改脚本..."
cat > $PROJECT_ROOT/change-password.sh << CHANGE_PASS_EOF
#!/bin/bash

if [ "$EUID" -ne 0 ]; then 
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

if [ "$NEW_PASSWORD" != "$NEW_PASSWORD_CONFIRM" ]; then
    echo "错误：两次输入的密码不一致！"
    exit 1
fi

if [ -z "$NEW_PASSWORD" ]; then
    echo "错误：密码不能为空！"
    exit 1
fi

# 更新配置文件
OLD_PORT=$(grep "DEFAULT_PORT = " config.py | cut -d'=' -f2 | tr -d ' ')

cat > config.py << CONFIG_UPDATE_END
import hashlib
import socket

# 密码设置（安装时设置）
ADMIN_PASSWORD = "$NEW_PASSWORD"

# 端口设置（保持原端口）
DEFAULT_PORT = $OLD_PORT

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
echo "需要重启服务才能使新密码生效。"
echo ""
echo "重启命令:"
echo "cd $PROJECT_ROOT && ./restart.sh"
CHANGE_PASS_EOF

chmod +x $PROJECT_ROOT/change-password.sh

# 创建查看状态脚本
echo "14. 创建查看状态脚本..."
cat > $PROJECT_ROOT/status.sh << STATUS_EOF
#!/bin/bash
echo "=== 文件上传系统状态 (UUID版本) ==="
echo ""

# 检查进程是否运行
if pgrep -f "python3 server.py" > /dev/null; then
    echo "✅ 服务状态: 运行中"
    
    # 获取端口信息
    PORT=$(netstat -tlnp 2>/dev/null | grep "python3" | grep "server.py" | awk '{print $4}' | cut -d':' -f2 | head -1)
    
    if [ -n "$PORT" ]; then
        echo "📡 运行端口: $PORT"
    else
        PORT_INFO=$(ps aux | grep "python3 server.py" | grep -v grep | tr -s ' ' | cut -d' ' -f22 | grep -o "[0-9]*$")
        if [ -n "$PORT_INFO" ]; then
            echo "📡 运行端口: $PORT_INFO"
            PORT=$PORT_INFO
        else
            echo "📡 运行端口: 获取中..."
        fi
    fi
    
    # 获取IP地址
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    if [ -n "$PORT" ]; then
        echo "🌐 访问地址: http://$IP_ADDRESS:$PORT"
    else
        echo "🌐 访问地址: 请查看启动日志"
    fi
    
    # 统计上传文件
    if [ -d "$PROJECT_ROOT/uploads" ]; then
        FILE_COUNT=$(ls $PROJECT_ROOT/uploads/ 2>/dev/null | wc -l)
        echo "📁 文件数量: $FILE_COUNT"
        
        TOTAL_SIZE=$(du -sh $PROJECT_ROOT/uploads 2>/dev/null | cut -f1)
        echo "💾 总大小: $TOTAL_SIZE"
    fi
    
    # 检查映射文件
    if [ -f "$PROJECT_ROOT/file_mapping.json" ]; then
        MAPPING_COUNT=$(grep -c '"original_name"' $PROJECT_ROOT/file_mapping.json 2>/dev/null || echo "0")
        echo "🗂️  文件映射: $MAPPING_COUNT 条记录"
    fi
    
    # 检查防火墙状态
    echo ""
    echo "=== 防火墙状态 ==="
    
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "$PORT/tcp"; then
            echo "✅ ufw: 端口 $PORT 已开放"
        else
            echo "❌ ufw: 端口 $PORT 未开放"
        fi
    fi
    
    if command -v iptables >/dev/null 2>&1; then
        if iptables -L INPUT -n 2>/dev/null | grep -q "tcp dpt:$PORT"; then
            echo "✅ iptables: 端口 $PORT 已开放"
        else
            echo "❌ iptables: 端口 $PORT 未开放"
        fi
    fi
    
else
    echo "❌ 服务状态: 未运行"
    echo ""
    echo "启动命令:"
    echo "cd $PROJECT_ROOT && ./start.sh"
fi

echo ""
echo "管理命令:"
echo "- 启动: ./start.sh"
echo "- 停止: ./stop.sh"
echo "- 重启: ./restart.sh"
echo "- 修改密码: sudo ./change-password.sh"
echo "- 防火墙管理: sudo ./firewall-setup.sh"
echo "- 清理文件: ./cleanup.sh"
STATUS_EOF

chmod +x $PROJECT_ROOT/status.sh

# 创建清理脚本
echo "15. 创建清理脚本..."
cat > $PROJECT_ROOT/cleanup.sh << CLEANUP_EOF
#!/bin/bash
echo "=== 清理文件上传系统 ==="
echo "警告：此操作将删除所有上传的文件！"
echo ""

read -p "确定要清理所有文件吗？(y/N): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "操作取消"
    exit 0
fi

cd $PROJECT_ROOT

# 停止服务
./stop.sh

# 删除上传的文件
rm -rf uploads/*
rm -f file_mapping.json

# 重新创建目录
mkdir -p uploads

echo ""
echo "✅ 所有文件已清理！"
echo "现在可以重新启动服务:"
echo "cd $PROJECT_ROOT && ./start.sh"
CLEANUP_EOF

chmod +x $PROJECT_ROOT/cleanup.sh

# 设置目录权限
echo "16. 设置目录权限..."
chmod -R 755 $PROJECT_ROOT
chmod 777 $PROJECT_ROOT/uploads

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
echo "防火墙配置："
echo "✅ 已尝试自动配置系统防火墙"
echo "⚠️  如果仍无法访问，请检查："
echo "   1. 云服务器安全组（控制台）"
echo "   2. 使用防火墙管理工具: sudo ./firewall-setup.sh"
echo ""
echo "管理命令:"
echo "- 查看状态: cd $PROJECT_ROOT && ./status.sh"
echo "- 启动服务: cd $PROJECT_ROOT && ./start.sh"
echo "- 停止服务: cd $PROJECT_ROOT && ./stop.sh"
echo "- 重启服务: cd $PROJECT_ROOT && ./restart.sh"
echo "- 修改密码: cd $PROJECT_ROOT && sudo ./change-password.sh"
echo "- 防火墙管理: cd $PROJECT_ROOT && sudo ./firewall-setup.sh"
echo "- 清理文件: cd $PROJECT_ROOT && ./cleanup.sh"
echo ""
echo "安装目录: $PROJECT_ROOT"
echo "上传目录: $PROJECT_ROOT/uploads"
echo "映射文件: $PROJECT_ROOT/file_mapping.json"
echo ""
echo "现在可以启动服务了："
echo "cd $PROJECT_ROOT && ./start.sh"
echo ""
echo "访问地址: http://$IP_ADDRESS:$DEFAULT_PORT"
echo ""
echo "如果无法访问，请运行防火墙检查："
echo "cd $PROJECT_ROOT && sudo ./firewall-setup.sh"
