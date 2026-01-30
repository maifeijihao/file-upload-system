# 首先清理之前的安装目录
rm -rf /opt/file-upload-uuid

# 创建新的安装脚本
cat > /tmp/install-fixed.sh << 'INSTALL_FIXED'
#!/bin/bash

echo "========================================"
echo "文件上传系统安装脚本 (UUID版本) - 修复版"
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
while true; do
    read -sp "请输入访问密码: " PASSWORD
    echo ""
    read -sp "请再次确认密码: " PASSWORD_CONFIRM
    echo ""

    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        echo "错误：两次输入的密码不一致！"
        echo ""
        continue
    fi

    if [ -z "$PASSWORD" ]; then
        echo "错误：密码不能为空！"
        echo ""
        continue
    fi
    
    break
done

# 设置端口
echo ""
echo "4. 设置服务器端口..."
while true; do
    read -p "请输入端口号（默认5555）: " INPUT_PORT
    
    # 如果用户直接回车，使用默认值
    if [ -z "$INPUT_PORT" ]; then
        DEFAULT_PORT=5555
    else
        DEFAULT_PORT="$INPUT_PORT"
    fi
    
    # 检查是否为数字
    if ! [[ "$DEFAULT_PORT" =~ ^[0-9]+$ ]] ; then
        echo "错误：端口必须是数字！"
        echo ""
        continue
    fi

    # 检查端口范围
    if [ "$DEFAULT_PORT" -lt 1024 ] || [ "$DEFAULT_PORT" -gt 65535 ]; then
        echo "错误：端口号必须在1024-65535之间！"
        echo ""
        continue
    fi
    
    break
done

echo "✅ 使用端口: $DEFAULT_PORT"

# 创建配置文件
echo "5. 创建配置文件..."
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
echo "6. 正在创建后端服务器..."
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

# 创建简单的提示页面
echo "7. 创建前端..."
cat > $PROJECT_ROOT/index.html << HTML_END
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>压缩包上传与下载</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
            display: flex;
            justify-content: center;
            align-items: flex-start;
        }
        
        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            width: 100%;
            max-width: 1000px;
            margin: 40px 20px;
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5rem;
            margin-bottom: 10px;
            font-weight: 300;
        }
        
        .header p {
            opacity: 0.9;
            font-size: 1.1rem;
        }
        
        .main-content {
            padding: 40px;
        }
        
        /* 密码验证弹窗 */
        .password-modal {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0,0,0,0.85);
            display: flex;
            justify-content: center;
            align-items: center;
            z-index: 1000;
        }
        
        .password-box {
            background: white;
            border-radius: 15px;
            width: 90%;
            max-width: 400px;
            overflow: hidden;
            animation: slideIn 0.3s ease;
        }
        
        @keyframes slideIn {
            from {
                transform: translateY(-50px);
                opacity: 0;
            }
            to {
                transform: translateY(0);
                opacity: 1;
            }
        }
        
        .password-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 25px;
            text-align: center;
        }
        
        .password-header h2 {
            font-size: 1.8rem;
            margin-bottom: 8px;
        }
        
        .password-body {
            padding: 30px;
        }
        
        .password-input {
            width: 100%;
            padding: 15px;
            border: 2px solid #e0e0e0;
            border-radius: 10px;
            font-size: 16px;
            margin-bottom: 15px;
            transition: border-color 0.3s;
        }
        
        .password-input:focus {
            border-color: #667eea;
            outline: none;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }
        
        .password-btn {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 15px 30px;
            border-radius: 10px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            width: 100%;
            transition: transform 0.2s;
        }
        
        .password-btn:hover {
            transform: translateY(-2px);
        }
        
        .password-error {
            color: #ff4757;
            font-size: 14px;
            margin-top: 10px;
            text-align: center;
            display: none;
        }
        
        /* 上传区域 */
        .upload-section {
            margin-bottom: 40px;
        }
        
        .upload-box {
            border: 3px dashed #ddd;
            border-radius: 15px;
            padding: 60px 20px;
            text-align: center;
            cursor: pointer;
            transition: all 0.3s;
            background: #f8f9fa;
            position: relative;
        }
        
        .upload-box:hover {
            border-color: #667eea;
            background: #f0f2ff;
        }
        
        .upload-box.dragover {
            border-color: #667eea;
            background: #e8ebff;
        }
        
        .upload-icon {
            font-size: 60px;
            color: #667eea;
            margin-bottom: 20px;
        }
        
        .upload-box h3 {
            font-size: 1.5rem;
            color: #333;
            margin-bottom: 10px;
        }
        
        .upload-box p {
            color: #666;
            margin-bottom: 20px;
        }
        
        .upload-btn {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 12px 30px;
            border-radius: 25px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 10px;
            transition: all 0.3s;
        }
        
        .upload-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
        }
        
        .file-input {
            display: none;
        }
        
        /* 文件列表区域 */
        .files-section {
            background: #f8f9fa;
            border-radius: 15px;
            padding: 25px;
            margin-top: 30px;
        }
        
        .stats-bar {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 25px;
            padding: 20px;
            background: white;
            border-radius: 10px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.05);
        }
        
        .stats {
            display: flex;
            gap: 30px;
        }
        
        .stat-item {
            text-align: center;
        }
        
        .stat-value {
            font-size: 1.5rem;
            font-weight: bold;
            display: block;
        }
        
        .stat-label {
            font-size: 0.9rem;
            color: #666;
        }
        
        .file-count { color: #667eea; }
        .total-size { color: #764ba2; }
        .success-count { color: #00b894; }
        .failed-count { color: #ff4757; }
        
        .batch-btn {
            background: #00b894;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 8px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
        }
        
        .batch-btn:hover:not(:disabled) {
            background: #00a085;
            transform: translateY(-2px);
        }
        
        .batch-btn:disabled {
            background: #ccc;
            cursor: not-allowed;
        }
        
        /* 文件列表 */
        .file-list {
            max-height: 400px;
            overflow-y: auto;
        }
        
        .file-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 15px;
            background: white;
            border-radius: 10px;
            margin-bottom: 10px;
            transition: all 0.3s;
        }
        
        .file-item:hover {
            transform: translateX(5px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        
        .file-info {
            display: flex;
            align-items: center;
            gap: 15px;
        }
        
        .file-icon {
            width: 40px;
            height: 40px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 10px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-size: 20px;
        }
        
        .file-details {
            flex: 1;
        }
        
        .file-name {
            font-weight: 600;
            color: #333;
            margin-bottom: 5px;
        }
        
        .file-size {
            color: #666;
            font-size: 0.9rem;
        }
        
        .file-actions {
            display: flex;
            gap: 10px;
        }
        
        .copy-btn {
            background: #0984e3;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 0.9rem;
            transition: all 0.3s;
        }
        
        .copy-btn:hover {
            background: #0770c4;
        }
        
        .empty-message {
            text-align: center;
            padding: 60px 20px;
            color: #999;
        }
        
        /* 进度条 */
        .progress-container {
            width: 100%;
            height: 6px;
            background: #e0e0e0;
            border-radius: 3px;
            overflow: hidden;
            margin-top: 10px;
            display: none;
        }
        
        .progress-bar {
            height: 100%;
            background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
            width: 0%;
            transition: width 0.3s;
        }
        
        /* 认证状态 */
        .auth-status {
            position: fixed;
            top: 20px;
            right: 20px;
            background: linear-gradient(135deg, #00b894 0%, #00a085 100%);
            color: white;
            padding: 10px 20px;
            border-radius: 25px;
            font-weight: 600;
            box-shadow: 0 5px 15px rgba(0, 184, 148, 0.3);
            z-index: 100;
            animation: slideInRight 0.3s ease;
            display: none;
        }
        
        .logout-btn {
            background: rgba(255,255,255,0.2);
            border: none;
            color: white;
            padding: 4px 12px;
            border-radius: 15px;
            margin-left: 10px;
            cursor: pointer;
            font-size: 0.8rem;
        }
        
        @keyframes slideInRight {
            from {
                transform: translateX(100%);
                opacity: 0;
            }
            to {
                transform: translateX(0);
                opacity: 1;
            }
        }
        
        /* 响应式设计 */
        @media (max-width: 768px) {
            .container {
                margin: 20px 10px;
            }
            
            .main-content {
                padding: 20px;
            }
            
            .stats-bar {
                flex-direction: column;
                gap: 20px;
            }
            
            .stats {
                flex-wrap: wrap;
                justify-content: center;
            }
            
            .file-item {
                flex-direction: column;
                align-items: stretch;
                gap: 15px;
            }
            
            .file-actions {
                justify-content: flex-end;
            }
        }
    </style>
</head>
<body>
    <!-- 密码验证弹窗 -->
    <div id="passwordModal" class="password-modal">
        <div class="password-box">
            <div class="password-header">
                <h2>🔒 安全验证</h2>
                <p>请输入密码访问文件系统</p>
            </div>
            <div class="password-body">
                <input type="password" id="passwordInput" class="password-input" placeholder="请输入访问密码" autocomplete="current-password">
                <button id="passwordSubmit" class="password-btn">验证并进入</button>
                <div id="passwordError" class="password-error">密码错误，请重试</div>
            </div>
        </div>
    </div>

    <!-- 认证状态提示 -->
    <div id="authStatus" class="auth-status">
        <span>已认证用户</span>
        <button id="logoutBtn" class="logout-btn">退出</button>
    </div>

    <div class="container">
        <div class="header">
            <h1>📁 文件上传与管理系统</h1>
            <p>安全、快速的文件上传与分享平台</p>
        </div>

        <div class="main-content">
            <!-- 上传区域 -->
            <div class="upload-section">
                <div id="uploadBox" class="upload-box">
                    <div class="upload-icon">📤</div>
                    <h3>拖放文件到此处上传</h3>
                    <p>支持 ZIP, RAR, 7Z, TAR, GZ 格式，最大 1GB</p>
                    <button id="selectFileBtn" class="upload-btn">
                        <span>📁</span> 选择文件
                    </button>
                    <input type="file" id="fileInput" class="file-input" multiple accept=".zip,.rar,.7z,.tar,.gz,.tar.gz">
                </div>
            </div>

            <!-- 文件列表区域 -->
            <div class="files-section">
                <div class="stats-bar">
                    <div class="stats">
                        <div class="stat-item">
                            <span id="totalFiles" class="stat-value file-count">0</span>
                            <span class="stat-label">文件数量</span>
                        </div>
                        <div class="stat-item">
                            <span id="totalSize" class="stat-value total-size">0</span>
                            <span class="stat-label">总大小</span>
                        </div>
                        <div class="stat-item">
                            <span id="successCount" class="stat-value success-count">0</span>
                            <span class="stat-label">成功</span>
                        </div>
                        <div class="stat-item">
                            <span id="failedCount" class="stat-value failed-count">0</span>
                            <span class="stat-label">失败</span>
                        </div>
                    </div>
                    <button id="batchCopyBtn" class="batch-btn" disabled>📋 批量复制链接</button>
                </div>

                <div id="fileList" class="file-list">
                    <div class="empty-message">
                        <div style="font-size: 48px; margin-bottom: 20px;">📂</div>
                        <h3>暂无文件</h3>
                        <p>上传文件后，它们会显示在这里</p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        // ==================== DOM 元素 ====================
        const passwordModal = document.getElementById('passwordModal');
        const passwordInput = document.getElementById('passwordInput');
        const passwordSubmit = document.getElementById('passwordSubmit');
        const passwordError = document.getElementById('passwordError');
        const authStatus = document.getElementById('authStatus');
        const logoutBtn = document.getElementById('logoutBtn');
        const uploadBox = document.getElementById('uploadBox');
        const selectFileBtn = document.getElementById('selectFileBtn');
        const fileInput = document.getElementById('fileInput');
        const fileList = document.getElementById('fileList');
        const batchCopyBtn = document.getElementById('batchCopyBtn');
        
        // 统计元素
        const totalFilesEl = document.getElementById('totalFiles');
        const totalSizeEl = document.getElementById('totalSize');
        const successCountEl = document.getElementById('successCount');
        const failedCountEl = document.getElementById('failedCount');
        
        // 状态变量
        let isAuthenticated = false;
        let uploadQueue = [];
        let activeUploads = new Map();
        let failedUploads = [];
        let currentFiles = [];
        
        // ==================== 工具函数 ====================
        function formatFileSize(bytes) {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }
        
        function getFileExtension(filename) {
            const ext = filename.split('.').pop().toLowerCase();
            if (filename.toLowerCase().endsWith('.tar.gz')) return '.tar.gz';
            return '.' + ext;
        }
        
        // ==================== 认证相关 ====================
        async function checkAuth() {
            try {
                const response = await fetch('/check_auth');
                if (!response.ok) throw new Error('Network error');
                const data = await response.json();
                return data.authenticated || false;
            } catch (error) {
                console.error('检查认证失败:', error);
                return false;
            }
        }
        
        async function login(password) {
            try {
                const response = await fetch('/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ password })
                });
                return await response.json();
            } catch (error) {
                console.error('登录失败:', error);
                return { success: false, message: '网络错误' };
            }
        }
        
        async function logout() {
            try {
                await fetch('/logout', { method: 'POST' });
                return true;
            } catch (error) {
                console.error('登出失败:', error);
                return false;
            }
        }
        
        async function updateAuthStatus() {
            isAuthenticated = await checkAuth();
            
            if (isAuthenticated) {
                passwordModal.style.display = 'none';
                authStatus.style.display = 'block';
                uploadBox.style.pointerEvents = 'auto';
                uploadBox.style.opacity = '1';
                selectFileBtn.disabled = false;
                await loadFiles();
            } else {
                passwordModal.style.display = 'flex';
                authStatus.style.display = 'none';
                uploadBox.style.pointerEvents = 'none';
                uploadBox.style.opacity = '0.5';
                selectFileBtn.disabled = true;
                showEmptyState('请先通过密码验证');
                updateStats(0, 0, 0, 0);
            }
        }
        
        // ==================== 文件管理 ====================
        async function loadFiles() {
            try {
                const response = await fetch('/files');
                if (response.status === 401) {
                    await updateAuthStatus();
                    return;
                }
                
                if (!response.ok) throw new Error('获取文件列表失败');
                
                const data = await response.json();
                if (!data.success) throw new Error(data.message);
                
                currentFiles = data.files || [];
                displayFiles(currentFiles);
                
            } catch (error) {
                console.error('加载文件失败:', error);
                showEmptyState('加载文件列表失败');
            }
        }
        
        function displayFiles(files) {
            if (!files || files.length === 0) {
                showEmptyState('暂无文件');
                updateStats(0, 0, 0, failedUploads.length);
                return;
            }
            
            let totalSize = 0;
            let html = '';
            
            files.forEach(file => {
                totalSize += file.size || 0;
                // 使用原始文件名显示，但下载链接使用UUID
                const displayName = file.original_name || file.name || file.filename;
                const fileSize = formatFileSize(file.size || 0);
                const fileId = file.uuid || file.filename; // UUID文件名
                const downloadUrl = `/download/${fileId}`; // 使用UUID构建下载链接
                const fileExt = getFileExtension(displayName).toLowerCase();
                
                // 根据文件类型设置图标
                let fileIcon = '📄';
                if (fileExt === '.zip') fileIcon = '🗜️';
                else if (fileExt === '.rar') fileIcon = '🗃️';
                else if (fileExt === '.7z') fileIcon = '🗄️';
                else if (fileExt === '.tar' || fileExt === '.tar.gz') fileIcon = '📦';
                else if (fileExt === '.gz') fileIcon = '💨';
                
                html += `
                    <div class="file-item" data-id="${fileId}">
                        <div class="file-info">
                            <div class="file-icon">${fileIcon}</div>
                            <div class="file-details">
                                <div class="file-name" title="${displayName}">${displayName}</div>
                                <div class="file-size">${fileSize}</div>
                                <div style="font-size: 11px; color: #999; margin-top: 3px;">
                                    文件ID: ${fileId.substring(0, 8)}...
                                </div>
                            </div>
                        </div>
                        <div class="file-actions">
                            <button class="copy-btn" onclick="copyLink('${fileId}', '${displayName}')">复制链接</button>
                        </div>
                    </div>
                `;
            });
            
            fileList.innerHTML = html;
            updateStats(files.length, totalSize, files.length, failedUploads.length);
        }
        
        function showEmptyState(message = '暂无文件') {
            fileList.innerHTML = `
                <div class="empty-message">
                    <div style="font-size: 48px; margin-bottom: 20px;">📂</div>
                    <h3>${message}</h3>
                    <p>${message.includes('验证') ? '请先输入密码验证身份' : '上传文件后，它们会显示在这里'}</p>
                </div>
            `;
        }
        
        function updateStats(total, size, success, failed) {
            totalFilesEl.textContent = total;
            totalSizeEl.textContent = formatFileSize(size);
            successCountEl.textContent = success;
            failedCountEl.textContent = failed;
            batchCopyBtn.disabled = total === 0;
        }
        
        // ==================== 文件上传 ====================
        async function uploadFile(file) {
            // 验证文件类型
            const allowedExts = ['.zip', '.rar', '.7z', '.tar', '.gz', '.tar.gz'];
            const fileExt = getFileExtension(file.name);
            
            if (!allowedExts.includes(fileExt)) {
                alert(`不支持的文件格式: ${fileExt}\n请上传压缩文件 (ZIP, RAR, 7Z, TAR, GZ)`);
                failedUploads.push({ name: file.name, error: '不支持的文件格式' });
                updateStats(currentFiles.length, 
                           currentFiles.reduce((s, f) => s + (f.size || 0), 0),
                           currentFiles.length,
                           failedUploads.length);
                return;
            }
            
            // 验证文件大小 (1GB)
            if (file.size > 1024 * 1024 * 1024) {
                alert(`文件太大: ${formatFileSize(file.size)}\n最大支持 1GB`);
                failedUploads.push({ name: file.name, error: '文件超过大小限制' });
                updateStats(currentFiles.length,
                           currentFiles.reduce((s, f) => s + (f.size || 0), 0),
                           currentFiles.length,
                           failedUploads.length);
                return;
            }
            
            // 创建上传项目
            const uploadId = 'upload_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
            const uploadItem = createUploadItem(file, uploadId);
            
            // 准备表单数据
            const formData = new FormData();
            formData.append('file', file);
            
            // 创建 XMLHttpRequest
            const xhr = new XMLHttpRequest();
            
            // 进度事件
            xhr.upload.addEventListener('progress', (e) => {
                if (e.lengthComputable) {
                    const percent = Math.round((e.loaded / e.total) * 100);
                    updateUploadProgress(uploadId, percent);
                }
            });
            
            // 完成事件
            xhr.addEventListener('load', () => {
                handleUploadComplete(uploadId, xhr, file);
            });
            
            // 错误事件
            xhr.addEventListener('error', () => {
                handleUploadError(uploadId, file, '网络错误');
            });
            
            // 存储上传
            activeUploads.set(uploadId, { xhr, file, item: uploadItem });
            
            // 发送请求
            xhr.open('POST', '/upload');
            xhr.send(formData);
        }
        
        function createUploadItem(file, uploadId) {
            // 移除空状态
            if (fileList.querySelector('.empty-message')) {
                fileList.innerHTML = '';
            }
            
            const item = document.createElement('div');
            item.className = 'file-item';
            item.id = uploadId;
            item.innerHTML = `
                <div class="file-info">
                    <div class="file-icon">⏳</div>
                    <div class="file-details">
                        <div class="file-name" title="${file.name}">${file.name}</div>
                        <div class="file-size">${formatFileSize(file.size)}</div>
                        <div class="progress-container">
                            <div class="progress-bar" style="width: 0%"></div>
                        </div>
                    </div>
                </div>
                <div class="file-actions">
                    <button class="copy-btn" style="background: #ff4757;" onclick="cancelUpload('${uploadId}')">
                        取消
                    </button>
                </div>
            `;
            
            // 显示进度条
            item.querySelector('.progress-container').style.display = 'block';
            
            // 添加到列表顶部
            fileList.prepend(item);
            return item;
        }
        
        function updateUploadProgress(uploadId, percent) {
            const item = document.getElementById(uploadId);
            if (item) {
                const progressBar = item.querySelector('.progress-bar');
                if (progressBar) {
                    progressBar.style.width = percent + '%';
                }
            }
        }
        
        function handleUploadComplete(uploadId, xhr, file) {
            const upload = activeUploads.get(uploadId);
            if (!upload) return;
            
            try {
                const response = JSON.parse(xhr.responseText);
                
                if (xhr.status === 200 && response.success) {
                    // 上传成功
                    upload.item.querySelector('.file-icon').textContent = '✅';
                    upload.item.querySelector('.progress-bar').style.background = '#00b894';
                    
                    // 显示成功信息
                    const uuidFilename = response.uuid_filename || '未知UUID';
                    upload.item.querySelector('.file-name').innerHTML = 
                        `${file.name} <small style="color: #00b894;">(上传成功)</small>`;
                    
                    setTimeout(() => {
                        if (upload.item.parentNode) {
                            upload.item.remove();
                        }
                        loadFiles(); // 重新加载文件列表
                    }, 1000);
                    
                } else if (xhr.status === 401) {
                    // 未授权
                    handleUploadError(uploadId, file, '会话过期，请重新登录');
                    updateAuthStatus();
                } else {
                    // 其他错误
                    const errorMsg = response.message || '上传失败';
                    handleUploadError(uploadId, file, errorMsg);
                }
            } catch (error) {
                handleUploadError(uploadId, file, '服务器响应错误');
            }
            
            activeUploads.delete(uploadId);
        }
        
        function handleUploadError(uploadId, file, error) {
            const upload = activeUploads.get(uploadId);
            if (!upload) return;
            
            upload.item.querySelector('.file-icon').textContent = '❌';
            upload.item.querySelector('.file-name').innerHTML = `${file.name} <small style="color: #ff4757;">(${error})</small>`;
            upload.item.querySelector('.progress-bar').style.background = '#ff4757';
            upload.item.querySelector('.copy-btn').style.display = 'none';
            
            failedUploads.push({ name: file.name, error });
            
            setTimeout(() => {
                if (upload.item.parentNode) {
                    upload.item.remove();
                }
                updateStats(currentFiles.length,
                           currentFiles.reduce((s, f) => s + (f.size || 0), 0),
                           currentFiles.length,
                           failedUploads.length);
            }, 3000);
            
            activeUploads.delete(uploadId);
        }
        
        // ==================== 全局函数 ====================
        window.cancelUpload = function(uploadId) {
            const upload = activeUploads.get(uploadId);
            if (upload && upload.xhr) {
                upload.xhr.abort();
                upload.item.querySelector('.file-icon').textContent = '⏹️';
                upload.item.querySelector('.file-name').innerHTML = `${upload.file.name} <small style="color: #999;">(已取消)</small>`;
                
                setTimeout(() => {
                    if (upload.item.parentNode) {
                        upload.item.remove();
                    }
                }, 1000);
                
                activeUploads.delete(uploadId);
            }
        };
        
        window.copyLink = async function(fileId, displayName) {
            const fileUrl = `${window.location.origin}/download/${fileId}`;
            
            try {
                await navigator.clipboard.writeText(fileUrl);
                alert(`✅ 链接已复制到剪贴板\n\n文件名: ${displayName}\n链接: ${fileUrl}`);
            } catch (err) {
                // 备用方法
                const textarea = document.createElement('textarea');
                textarea.value = fileUrl;
                document.body.appendChild(textarea);
                textarea.select();
                try {
                    document.execCommand('copy');
                    alert(`✅ 链接已复制到剪贴板\n\n文件名: ${displayName}\n链接: ${fileUrl}`);
                } catch (err2) {
                    alert('❌ 复制失败，请手动复制链接:\n' + fileUrl);
                }
                document.body.removeChild(textarea);
            }
        };
        
        // ==================== 事件监听 ====================
        // 密码验证
        passwordSubmit.addEventListener('click', async () => {
            const password = passwordInput.value.trim();
            if (!password) {
                passwordError.textContent = '请输入密码';
                passwordError.style.display = 'block';
                return;
            }
            
            const result = await login(password);
            
            if (result.success) {
                await updateAuthStatus();
                passwordError.style.display = 'none';
                passwordInput.value = '';
            } else {
                passwordError.textContent = result.message || '密码错误';
                passwordError.style.display = 'block';
                passwordInput.value = '';
                passwordInput.focus();
            }
        });
        
        passwordInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                passwordSubmit.click();
            }
        });
        
        // 退出登录
        logoutBtn.addEventListener('click', async () => {
            await logout();
            await updateAuthStatus();
        });
        
        // 选择文件
        selectFileBtn.addEventListener('click', () => {
            if (!isAuthenticated) {
                alert('请先通过密码验证');
                return;
            }
            fileInput.click();
        });
        
        fileInput.addEventListener('change', (e) => {
            if (!isAuthenticated) {
                alert('请先通过密码验证');
                return;
            }
            
            const files = Array.from(e.target.files);
            if (files.length === 0) return;
            
            files.forEach(file => {
                uploadFile(file);
            });
            
            fileInput.value = ''; // 清除选择，允许选择相同文件
        });
        
        // 拖放上传
        uploadBox.addEventListener('dragover', (e) => {
            if (!isAuthenticated) {
                e.preventDefault();
                return;
            }
            e.preventDefault();
            uploadBox.classList.add('dragover');
        });
        
        uploadBox.addEventListener('dragleave', () => {
            uploadBox.classList.remove('dragover');
        });
        
        uploadBox.addEventListener('drop', (e) => {
            e.preventDefault();
            uploadBox.classList.remove('dragover');
            
            if (!isAuthenticated) {
                alert('请先通过密码验证');
                return;
            }
            
            const files = Array.from(e.dataTransfer.files);
            if (files.length === 0) return;
            
            files.forEach(file => {
                uploadFile(file);
            });
        });
        
        // 批量复制
        batchCopyBtn.addEventListener('click', async () => {
            try {
                const response = await fetch('/files');
                if (!response.ok) throw new Error('获取文件列表失败');
                
                const data = await response.json();
                if (!data.success) throw new Error(data.message);
                
                const files = data.files || [];
                if (files.length === 0) {
                    alert('没有文件可以复制');
                    return;
                }
                
                const serverUrl = window.location.origin;
                let allLinks = '';
                
                files.forEach((file, index) => {
                    const displayName = file.original_name || file.name || file.filename;
                    const fileId = file.uuid || file.filename;
                    const fileUrl = `${serverUrl}/download/${fileId}`;
                    allLinks += `${index + 1}. ${displayName}\n${fileUrl}\n\n`;
                });
                
                try {
                    await navigator.clipboard.writeText(allLinks);
                    alert(`✅ 已复制 ${files.length} 个文件的链接到剪贴板！`);
                } catch (err) {
                    // 备用方法
                    const textarea = document.createElement('textarea');
                    textarea.value = allLinks;
                    document.body.appendChild(textarea);
                    textarea.select();
                    document.execCommand('copy');
                    document.body.removeChild(textarea);
                    alert(`✅ 已复制 ${files.length} 个文件的链接到剪贴板！`);
                }
                
            } catch (error) {
                console.error('批量复制失败:', error);
                alert('批量复制失败: ' + error.message);
            }
        });
        
        // ==================== 初始化 ====================
        async function init() {
            await updateAuthStatus();
            
            // 每30秒刷新文件列表
            setInterval(async () => {
                if (isAuthenticated) {
                    await loadFiles();
                }
            }, 30000);
        }
        
        // 页面加载完成后初始化
        document.addEventListener('DOMContentLoaded', init);
    </script>
</body>
</html>
HTML_END

# 创建管理脚本
echo "8. 创建管理脚本..."

# 启动脚本
cat > $PROJECT_ROOT/start.sh << 'START_EOF'
#!/bin/bash
cd $(dirname "$0")
python3 server.py
START_EOF

chmod +x $PROJECT_ROOT/start.sh

# 停止脚本
cat > $PROJECT_ROOT/stop.sh << 'STOP_EOF'
#!/bin/bash
echo "正在停止文件上传系统..."
pkill -f "python3 server.py" 2>/dev/null
sleep 2
echo "已停止"
STOP_EOF

chmod +x $PROJECT_ROOT/stop.sh

# 重启脚本
cat > $PROJECT_ROOT/restart.sh << 'RESTART_EOF'
#!/bin/bash
cd $(dirname "$0")
./stop.sh
sleep 1
./start.sh
RESTART_EOF

chmod +x $PROJECT_ROOT/restart.sh

# 状态查看脚本
cat > $PROJECT_ROOT/status.sh << 'STATUS_EOF'
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
    if [ -d "uploads" ]; then
        FILE_COUNT=$(ls uploads/ 2>/dev/null | wc -l)
        echo "📁 文件数量: $FILE_COUNT"
        
        TOTAL_SIZE=$(du -sh uploads 2>/dev/null | cut -f1)
        echo "💾 总大小: $TOTAL_SIZE"
    fi
    
    # 检查映射文件
    if [ -f "file_mapping.json" ]; then
        MAPPING_COUNT=$(grep -c '"original_name"' file_mapping.json 2>/dev/null || echo "0")
        echo "🗂️  文件映射: $MAPPING_COUNT 条记录"
    fi
else
    echo "❌ 服务状态: 未运行"
    echo ""
    echo "启动命令:"
    echo "./start.sh"
fi

echo ""
echo "管理命令:"
echo "- 启动: ./start.sh"
echo "- 停止: ./stop.sh"
echo "- 重启: ./restart.sh"
echo "- 查看状态: ./status.sh"
STATUS_EOF

chmod +x $PROJECT_ROOT/status.sh

# 设置目录权限
echo "9. 设置目录权限..."
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
echo "1. 你设置的密码已保存到配置文件"
echo "2. 使用端口: $DEFAULT_PORT"
echo "3. 项目目录: $PROJECT_ROOT"
echo "4. 系统使用UUID文件名存储文件"
echo "   - 前端显示：原始文件名"
echo "   - 下载链接：UUID格式"
echo "   - 下载时显示：原始文件名"
echo ""
echo "管理命令:"
echo "- 查看状态: cd $PROJECT_ROOT && ./status.sh"
echo "- 启动服务: cd $PROJECT_ROOT && ./start.sh"
echo "- 停止服务: cd $PROJECT_ROOT && ./stop.sh"
echo "- 重启服务: cd $PROJECT_ROOT && ./restart.sh"
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
echo "注意：如果需要开放防火墙端口，请运行："
echo "sudo ufw allow $DEFAULT_PORT/tcp"
echo "sudo ufw enable"
echo ""
echo "✅ 安装完成！"
INSTALL_FIXED

# 运行修复后的安装脚本
chmod +x /tmp/install-fixed.sh
sudo bash /tmp/install-fixed.sh
