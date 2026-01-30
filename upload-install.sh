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
echo "6. 正在创建后端服务器 (UUID版本)..."
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

# 创建简化的前端页面（修复登录问题）
echo "7. 创建简化的前端页面..."
cat > $PROJECT_ROOT/index.html << HTML_END
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>压缩包上传与下载系统</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: Arial, sans-serif;
        }
        
        body {
            background-color: #f5f5f5;
            min-height: 100vh;
        }
        
        /* 登录弹窗 */
        .login-modal {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.8);
            display: flex;
            justify-content: center;
            align-items: center;
            z-index: 1000;
        }
        
        .login-box {
            background: white;
            border-radius: 10px;
            padding: 40px;
            width: 90%;
            max-width: 400px;
            box-shadow: 0 5px 20px rgba(0, 0, 0, 0.2);
        }
        
        .login-box h2 {
            text-align: center;
            color: #333;
            margin-bottom: 30px;
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-group label {
            display: block;
            margin-bottom: 5px;
            color: #555;
        }
        
        .form-group input {
            width: 100%;
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 16px;
        }
        
        .login-btn {
            width: 100%;
            padding: 12px;
            background: #4CAF50;
            color: white;
            border: none;
            border-radius: 5px;
            font-size: 16px;
            cursor: pointer;
            transition: background 0.3s;
        }
        
        .login-btn:hover {
            background: #45a049;
        }
        
        .error-message {
            color: #f44336;
            text-align: center;
            margin-top: 15px;
            display: none;
        }
        
        /* 主界面 */
        .main-container {
            display: none;
            padding: 20px;
        }
        
        .header {
            background: white;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        
        .header h1 {
            color: #333;
            margin-bottom: 10px;
        }
        
        .upload-section {
            background: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 20px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
            text-align: center;
        }
        
        .upload-box {
            border: 3px dashed #ddd;
            border-radius: 10px;
            padding: 40px 20px;
            cursor: pointer;
            transition: all 0.3s;
        }
        
        .upload-box:hover {
            border-color: #4CAF50;
            background: #f9f9f9;
        }
        
        .upload-btn {
            background: #4CAF50;
            color: white;
            padding: 10px 20px;
            border: none;
            border-radius: 5px;
            font-size: 16px;
            cursor: pointer;
            margin-top: 10px;
        }
        
        .files-section {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        
        .file-list {
            margin-top: 20px;
        }
        
        .file-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 15px;
            border-bottom: 1px solid #eee;
        }
        
        .file-info {
            flex: 1;
        }
        
        .file-name {
            font-weight: bold;
            color: #333;
            margin-bottom: 5px;
        }
        
        .file-size {
            color: #777;
            font-size: 14px;
        }
        
        .copy-btn {
            background: #2196F3;
            color: white;
            padding: 8px 15px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
        }
        
        .logout-btn {
            position: absolute;
            top: 20px;
            right: 20px;
            background: #f44336;
            color: white;
            padding: 8px 15px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
        }
        
        .progress-bar {
            width: 100%;
            height: 4px;
            background: #f0f0f0;
            margin-top: 10px;
            border-radius: 2px;
            overflow: hidden;
            display: none;
        }
        
        .progress {
            height: 100%;
            background: #4CAF50;
            width: 0%;
            transition: width 0.3s;
        }
        
        .empty-message {
            text-align: center;
            padding: 40px;
            color: #999;
        }
    </style>
</head>
<body>
    <!-- 登录弹窗 -->
    <div id="loginModal" class="login-modal">
        <div class="login-box">
            <h2>🔐 请输入密码</h2>
            <div class="form-group">
                <label for="password">密码:</label>
                <input type="password" id="password" placeholder="输入访问密码">
            </div>
            <button id="loginBtn" class="login-btn">登录</button>
            <div id="errorMsg" class="error-message">密码错误，请重试</div>
        </div>
    </div>
    
    <!-- 主界面 -->
    <div id="mainContainer" class="main-container">
        <button id="logoutBtn" class="logout-btn">退出登录</button>
        
        <div class="header">
            <h1>📁 文件上传与管理系统</h1>
            <p>支持 ZIP, RAR, 7Z, TAR, GZ 格式，最大 1GB</p>
        </div>
        
        <div class="upload-section">
            <div id="uploadBox" class="upload-box">
                <h3>拖放文件到此处或点击选择文件</h3>
                <p>支持压缩文件格式，最大1GB</p>
                <button id="selectFileBtn" class="upload-btn">选择文件</button>
                <input type="file" id="fileInput" style="display: none;" multiple accept=".zip,.rar,.7z,.tar,.gz,.tar.gz">
            </div>
        </div>
        
        <div class="files-section">
            <h2>📋 文件列表</h2>
            <div id="fileList" class="file-list">
                <div class="empty-message">
                    <p>暂无文件</p>
                    <p>上传文件后，它们会显示在这里</p>
                </div>
            </div>
        </div>
    </div>

    <script>
        // DOM元素
        const loginModal = document.getElementById('loginModal');
        const mainContainer = document.getElementById('mainContainer');
        const passwordInput = document.getElementById('password');
        const loginBtn = document.getElementById('loginBtn');
        const errorMsg = document.getElementById('errorMsg');
        const logoutBtn = document.getElementById('logoutBtn');
        const uploadBox = document.getElementById('uploadBox');
        const selectFileBtn = document.getElementById('selectFileBtn');
        const fileInput = document.getElementById('fileInput');
        const fileList = document.getElementById('fileList');
        
        // 状态变量
        let isAuthenticated = false;
        
        // 检查登录状态
        async function checkAuth() {
            try {
                const response = await fetch('/check_auth');
                const data = await response.json();
                return data.authenticated || false;
            } catch (error) {
                console.error('检查认证失败:', error);
                return false;
            }
        }
        
        // 登录
        async function login(password) {
            try {
                const response = await fetch('/login', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ password: password })
                });
                
                const data = await response.json();
                return data;
            } catch (error) {
                console.error('登录失败:', error);
                return { success: false, message: '网络错误' };
            }
        }
        
        // 登出
        async function logout() {
            try {
                await fetch('/logout', { method: 'POST' });
                return true;
            } catch (error) {
                console.error('登出失败:', error);
                return false;
            }
        }
        
        // 更新UI状态
        async function updateAuthStatus() {
            isAuthenticated = await checkAuth();
            
            if (isAuthenticated) {
                loginModal.style.display = 'none';
                mainContainer.style.display = 'block';
                loadFiles();
            } else {
                loginModal.style.display = 'flex';
                mainContainer.style.display = 'none';
                showEmptyState('请先登录');
            }
        }
        
        // 加载文件列表
        async function loadFiles() {
            try {
                const response = await fetch('/files');
                if (response.status === 401) {
                    // 未授权，重新检查登录状态
                    await updateAuthStatus();
                    return;
                }
                
                const data = await response.json();
                if (data.success) {
                    displayFiles(data.files);
                } else {
                    showEmptyState('加载文件列表失败');
                }
            } catch (error) {
                console.error('加载文件失败:', error);
                showEmptyState('网络错误');
            }
        }
        
        // 显示文件列表
        function displayFiles(files) {
            if (!files || files.length === 0) {
                showEmptyState('暂无文件');
                return;
            }
            
            let html = '';
            files.forEach(file => {
                const fileSize = formatFileSize(file.size);
                const fileName = file.original_name || file.name;
                
                html += `
                    <div class="file-item">
                        <div class="file-info">
                            <div class="file-name">${fileName}</div>
                            <div class="file-size">${fileSize}</div>
                        </div>
                        <button class="copy-btn" onclick="copyLink('${file.uuid || file.filename}', '${fileName}')">
                            复制链接
                        </button>
                    </div>
                `;
            });
            
            fileList.innerHTML = html;
        }
        
        // 显示空状态
        function showEmptyState(message) {
            fileList.innerHTML = `
                <div class="empty-message">
                    <p>${message}</p>
                </div>
            `;
        }
        
        // 格式化文件大小
        function formatFileSize(bytes) {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }
        
        // 复制链接
        async function copyLink(fileId, fileName) {
            const fileUrl = `${window.location.origin}/download/${fileId}`;
            
            try {
                await navigator.clipboard.writeText(fileUrl);
                alert(`✅ 链接已复制到剪贴板\n\n文件名: ${fileName}\n链接: ${fileUrl}`);
            } catch (err) {
                // 备用方法
                const textarea = document.createElement('textarea');
                textarea.value = fileUrl;
                document.body.appendChild(textarea);
                textarea.select();
                try {
                    document.execCommand('copy');
                    alert(`✅ 链接已复制到剪贴板\n\n文件名: ${fileName}\n链接: ${fileUrl}`);
                } catch (err2) {
                    prompt('请手动复制链接:', fileUrl);
                }
                document.body.removeChild(textarea);
            }
        }
        
        // 上传文件
        function uploadFile(file) {
            // 验证文件类型
            const allowedExts = ['.zip', '.rar', '.7z', '.tar', '.gz', '.tar.gz'];
            const fileExt = '.' + file.name.split('.').pop().toLowerCase();
            const isTarGz = file.name.toLowerCase().endsWith('.tar.gz');
            
            if (!allowedExts.includes(fileExt) && !isTarGz) {
                alert(`不支持的文件格式: ${fileExt}\n请上传压缩文件`);
                return;
            }
            
            // 验证文件大小
            if (file.size > 1024 * 1024 * 1024) {
                alert(`文件太大: ${formatFileSize(file.size)}\n最大支持 1GB`);
                return;
            }
            
            const formData = new FormData();
            formData.append('file', file);
            
            // 创建文件项
            const fileItem = document.createElement('div');
            fileItem.className = 'file-item';
            fileItem.innerHTML = `
                <div class="file-info">
                    <div class="file-name">${file.name}</div>
                    <div class="file-size">${formatFileSize(file.size)}</div>
                    <div class="progress-bar">
                        <div class="progress"></div>
                    </div>
                </div>
                <div>上传中...</div>
            `;
            
            const progressBar = fileItem.querySelector('.progress-bar');
            const progress = fileItem.querySelector('.progress');
            progressBar.style.display = 'block';
            
            // 从空状态移除
            if (fileList.querySelector('.empty-message')) {
                fileList.innerHTML = '';
            }
            
            fileList.prepend(fileItem);
            
            // 发送请求
            fetch('/upload', {
                method: 'POST',
                body: formData
            })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    progress.style.width = '100%';
                    fileItem.innerHTML = `
                        <div class="file-info">
                            <div class="file-name">${data.original_name}</div>
                            <div class="file-size">${formatFileSize(data.size)}</div>
                        </div>
                        <div style="color: #4CAF50;">✅ 上传成功</div>
                    `;
                    
                    setTimeout(() => {
                        loadFiles(); // 重新加载文件列表
                    }, 1000);
                } else {
                    fileItem.innerHTML = `
                        <div class="file-info">
                            <div class="file-name">${file.name}</div>
                            <div class="file-size">${formatFileSize(file.size)}</div>
                        </div>
                        <div style="color: #f44336;">❌ ${data.message || '上传失败'}</div>
                    `;
                }
            })
            .catch(error => {
                console.error('上传错误:', error);
                fileItem.innerHTML = `
                    <div class="file-info">
                        <div class="file-name">${file.name}</div>
                        <div class="file-size">${formatFileSize(file.size)}</div>
                    </div>
                    <div style="color: #f44336;">❌ 上传失败</div>
                `;
            });
        }
        
        // 事件监听器
        loginBtn.addEventListener('click', async () => {
            const password = passwordInput.value.trim();
            if (!password) {
                errorMsg.textContent = '请输入密码';
                errorMsg.style.display = 'block';
                return;
            }
            
            const result = await login(password);
            
            if (result.success) {
                await updateAuthStatus();
            } else {
                errorMsg.textContent = result.message || '密码错误';
                errorMsg.style.display = 'block';
                passwordInput.value = '';
                passwordInput.focus();
            }
        });
        
        passwordInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                loginBtn.click();
            }
        });
        
        logoutBtn.addEventListener('click', async () => {
            await logout();
            await updateAuthStatus();
        });
        
        selectFileBtn.addEventListener('click', () => {
            fileInput.click();
        });
        
        fileInput.addEventListener('change', (e) => {
            const files = Array.from(e.target.files);
            if (files.length === 0) return;
            
            files.forEach(file => {
                uploadFile(file);
            });
            
            fileInput.value = '';
        });
        
        uploadBox.addEventListener('dragover', (e) => {
            e.preventDefault();
            uploadBox.style.borderColor = '#4CAF50';
            uploadBox.style.background = '#f0f8f0';
        });
        
        uploadBox.addEventListener('dragleave', () => {
            uploadBox.style.borderColor = '#ddd';
            uploadBox.style.background = 'white';
        });
        
        uploadBox.addEventListener('drop', (e) => {
            e.preventDefault();
            uploadBox.style.borderColor = '#ddd';
            uploadBox.style.background = 'white';
            
            const files = Array.from(e.dataTransfer.files);
            if (files.length === 0) return;
            
            files.forEach(file => {
                uploadFile(file);
            });
        });
        
        // 页面加载时检查登录状态
        window.addEventListener('load', async () => {
            await updateAuthStatus();
            
            // 自动刷新文件列表
            setInterval(() => {
                if (isAuthenticated) {
                    loadFiles();
                }
            }, 30000);
        });
    </script>
</body>
</html>
HTML_END

# 创建启动脚本
echo "8. 创建启动脚本..."
cat > $PROJECT_ROOT/start.sh << START_EOF
#!/bin/bash
cd $PROJECT_ROOT
nohup python3 server.py > server.log 2>&1 &
echo "服务已启动，日志: $PROJECT_ROOT/server.log"
echo "使用 ./status.sh 查看状态"
START_EOF

chmod +x $PROJECT_ROOT/start.sh

# 创建停止脚本
echo "9. 创建停止脚本..."
cat > $PROJECT_ROOT/stop.sh << STOP_EOF
#!/bin/bash
echo "正在停止文件上传系统..."
pkill -f "python3 server.py" 2>/dev/null
sleep 2
echo "已停止"
STOP_EOF

chmod +x $PROJECT_ROOT/stop.sh

# 创建重启脚本
echo "10. 创建重启脚本..."
cat > $PROJECT_ROOT/restart.sh << RESTART_EOF
#!/bin/bash
cd $PROJECT_ROOT
./stop.sh
sleep 1
./start.sh
RESTART_EOF

chmod +x $PROJECT_ROOT/restart.sh

# 创建查看日志脚本
echo "11. 创建查看日志脚本..."
cat > $PROJECT_ROOT/logs.sh << LOGS_EOF
#!/bin/bash
cd $PROJECT_ROOT
tail -f server.log
LOGS_EOF

chmod +x $PROJECT_ROOT/logs.sh

# 创建修改密码脚本
echo "12. 创建密码修改脚本..."
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

if [ "\$NEW_PASSWORD" != "\$NEW_PASSWORD_CONFIRM" ]; then
    echo "错误：两次输入的密码不一致！"
    exit 1
fi

if [ -z "\$NEW_PASSWORD" ]; then
    echo "错误：密码不能为空！"
    exit 1
fi

# 停止服务
./stop.sh

# 更新配置文件
OLD_PORT=$(grep "DEFAULT_PORT = " config.py | cut -d'=' -f2 | tr -d ' ')

cat > config.py << CONFIG_UPDATE_END
import hashlib
import socket

# 密码设置（安装时设置）
ADMIN_PASSWORD = "\$NEW_PASSWORD"

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

# 启动服务
./start.sh

echo "✅ 密码修改成功！"
echo "服务已重启，新密码立即生效。"
CHANGE_PASS_EOF

chmod +x $PROJECT_ROOT/change-password.sh

# 创建查看状态脚本
echo "13. 创建查看状态脚本..."
cat > $PROJECT_ROOT/status.sh << STATUS_EOF
#!/bin/bash
echo "=== 文件上传系统状态 (UUID版本) ==="
echo ""

cd $PROJECT_ROOT

# 检查进程是否运行
if pgrep -f "python3 server.py" > /dev/null; then
    echo "✅ 服务状态: 运行中"
    
    # 获取端口信息
    PORT=$(netstat -tlnp 2>/dev/null | grep "python3" | grep "server.py" | awk '{print \$4}' | cut -d':' -f2 | head -1)
    
    if [ -n "\$PORT" ]; then
        echo "📡 运行端口: \$PORT"
    else
        PORT_INFO=\$(ps aux | grep "python3 server.py" | grep -v grep | tr -s ' ' | cut -d' ' -f22 | grep -o "[0-9]*\$")
        if [ -n "\$PORT_INFO" ]; then
            echo "📡 运行端口: \$PORT_INFO"
            PORT=\$PORT_INFO
        else
            echo "📡 运行端口: 从日志中获取..."
            PORT=\$(grep "访问地址:" server.log | tail -1 | grep -o ":[0-9]*" | tr -d ':')
            if [ -n "\$PORT" ]; then
                echo "📡 运行端口: \$PORT"
            else
                echo "📡 运行端口: 未知"
            fi
        fi
    fi
    
    # 获取IP地址
    IP_ADDRESS=\$(hostname -I | awk '{print \$1}')
    if [ -n "\$PORT" ]; then
        echo "🌐 访问地址: http://\$IP_ADDRESS:\$PORT"
    else
        echo "🌐 访问地址: 请查看日志文件"
    fi
    
    # 统计上传文件
    if [ -d "\$PROJECT_ROOT/uploads" ]; then
        FILE_COUNT=\$(ls \$PROJECT_ROOT/uploads/ 2>/dev/null | wc -l)
        echo "📁 文件数量: \$FILE_COUNT"
        
        TOTAL_SIZE=\$(du -sh \$PROJECT_ROOT/uploads 2>/dev/null | cut -f1)
        echo "💾 总大小: \$TOTAL_SIZE"
    fi
    
    # 显示日志文件位置
    echo "📝 日志文件: \$PROJECT_ROOT/server.log"
    
    # 显示最后几行日志
    echo ""
    echo "最近日志:"
    tail -5 server.log
else
    echo "❌ 服务状态: 未运行"
    echo ""
    echo "启动命令:"
    echo "cd \$PROJECT_ROOT && ./start.sh"
fi

echo ""
echo "管理命令:"
echo "- 查看状态: ./status.sh"
echo "- 启动服务: ./start.sh"
echo "- 停止服务: ./stop.sh"
echo "- 重启服务: ./restart.sh"
echo "- 查看日志: ./logs.sh"
echo "- 修改密码: sudo ./change-password.sh"
STATUS_EOF

chmod +x $PROJECT_ROOT/status.sh

# 设置目录权限
echo "14. 设置目录权限..."
chmod -R 755 $PROJECT_ROOT
chmod 777 $PROJECT_ROOT/uploads

# 启动服务
echo "15. 启动文件上传服务..."
cd $PROJECT_ROOT
./start.sh

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
echo "管理命令:"
echo "- 查看状态: cd $PROJECT_ROOT && ./status.sh"
echo "- 查看日志: cd $PROJECT_ROOT && ./logs.sh"
echo "- 启动服务: cd $PROJECT_ROOT && ./start.sh"
echo "- 停止服务: cd $PROJECT_ROOT && ./stop.sh"
echo "- 重启服务: cd $PROJECT_ROOT && ./restart.sh"
echo "- 修改密码: cd $PROJECT_ROOT && sudo ./change-password.sh"
echo ""
echo "安装目录: $PROJECT_ROOT"
echo "上传目录: $PROJECT_ROOT/uploads"
echo "日志文件: $PROJECT_ROOT/server.log"
echo ""
echo "如果无法访问，请检查防火墙设置:"
echo "sudo ufw allow $DEFAULT_PORT/tcp"
echo ""
echo "✅ 安装完成！现在可以通过浏览器访问系统了。"
