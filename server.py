cd /opt/upload
cat > server.py << 'EOF'
from flask import Flask, request, send_file, jsonify, send_from_directory, session
import os
import uuid
import json
import shutil
from datetime import datetime

app = Flask(__name__)
app.secret_key = os.urandom(24)
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['MAX_CONTENT_LENGTH'] = 1024 * 1024 * 1024  # 1GB

# 配置文件映射（原始文件名 -> UUID文件名）
MAPPING_FILE = 'file_mapping.json'

# 确保上传目录和映射文件存在
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
if not os.path.exists(MAPPING_FILE):
    with open(MAPPING_FILE, 'w') as f:
        json.dump({}, f)

def load_mapping():
    """加载文件名映射"""
    try:
        with open(MAPPING_FILE, 'r') as f:
            return json.load(f)
    except:
        return {}

def save_mapping(mapping):
    """保存文件名映射"""
    with open(MAPPING_FILE, 'w') as f:
        json.dump(mapping, f, indent=2)

def get_original_name(uuid_name):
    """根据UUID文件名获取原始文件名"""
    mapping = load_mapping()
    return mapping.get(uuid_name, uuid_name)

def get_uuid_name(original_name):
    """根据原始文件名获取UUID文件名（反向查找）"""
    mapping = load_mapping()
    for uuid_name, orig in mapping.items():
        if orig == original_name:
            return uuid_name
    return None

# 登录密码（请修改）
PASSWORD = 'your_password_here'  # ！！！请修改为你的实际密码 ！！！

def check_login():
    return session.get('logged_in', False)

@app.route('/')
def index():
    return send_from_directory('.', 'index.html')

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    if not data or 'password' not in data:
        return jsonify({'success': False, 'message': '密码不能为空'}), 400
    if data['password'] == PASSWORD:
        session['logged_in'] = True
        return jsonify({'success': True, 'message': '登录成功'}), 200
    else:
        return jsonify({'success': False, 'message': '密码错误'}), 401

@app.route('/logout', methods=['POST'])
def logout():
    session.clear()
    return jsonify({'success': True, 'message': '退出成功'}), 200

@app.route('/check_auth', methods=['GET'])
def check_auth():
    if check_login():
        return jsonify({'authenticated': True}), 200
    else:
        return jsonify({'authenticated': False}), 200

@app.route('/upload', methods=['POST'])
def upload_file():
    if not check_login():
        return jsonify({'success': False, 'message': '请先登录'}), 401
    if 'file' not in request.files:
        return jsonify({'success': False, 'message': '没有选择文件'}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({'success': False, 'message': '文件名为空'}), 400

    # 允许的压缩格式
    allowed_extensions = ['.zip', '.rar', '.7z', '.tar', '.gz', '.tar.gz']
    original_filename = file.filename
    # 检查扩展名
    ext = os.path.splitext(original_filename)[1].lower()
    if original_filename.lower().endswith('.tar.gz'):
        ext = '.tar.gz'
    if ext not in allowed_extensions:
        return jsonify({'success': False, 'message': '不支持的文件格式'}), 400

    # 生成UUID文件名（保留扩展名）
    uuid_filename = str(uuid.uuid4()) + ext
    save_path = os.path.join(app.config['UPLOAD_FOLDER'], uuid_filename)

    # 保存文件
    file.save(save_path)

    # 记录映射
    mapping = load_mapping()
    mapping[uuid_filename] = original_filename
    save_mapping(mapping)

    return jsonify({
        'success': True,
        'message': '上传成功',
        'filename': uuid_filename,
        'original_name': original_filename,
        'size': os.path.getsize(save_path),
        'url': f'/download/{uuid_filename}'
    }), 200

@app.route('/files', methods=['GET'])
def list_files():
    if not check_login():
        return jsonify({'success': False, 'message': '请先登录'}), 401
    try:
        files = []
        mapping = load_mapping()
        for uuid_name in os.listdir(app.config['UPLOAD_FOLDER']):
            file_path = os.path.join(app.config['UPLOAD_FOLDER'], uuid_name)
            if os.path.isfile(file_path):
                original = mapping.get(uuid_name, uuid_name)
                file_size = os.path.getsize(file_path)
                # ===== 新增：获取创建时间 =====
                upload_time = os.path.getctime(file_path)  # 秒级时间戳
                files.append({
                    'name': original,
                    'filename': uuid_name,
                    'size': file_size,
                    'url': f'/download/{uuid_name}',
                    'upload_time': upload_time   # 新增
                })
        # ===== 新增：按时间倒序排列（最新的在前） =====
        files.sort(key=lambda x: x['upload_time'], reverse=True)
        return jsonify({'success': True, 'files': files}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': f'获取文件列表失败: {str(e)}'}), 500

@app.route('/download/<uuid_name>')
def download_file(uuid_name):
    try:
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], uuid_name)
        if not os.path.exists(file_path):
            return jsonify({'success': False, 'message': '文件不存在'}), 404
        # 获取原始文件名作为下载名称
        original = get_original_name(uuid_name)
        return send_file(
            file_path,
            as_attachment=True,
            download_name=original
        )
    except Exception as e:
        return jsonify({'success': False, 'message': f'下载失败: {str(e)}'}), 500

@app.route('/delete/<uuid_name>', methods=['DELETE'])
def delete_file(uuid_name):
    if not check_login():
        return jsonify({'success': False, 'message': '请先登录'}), 401
    try:
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], uuid_name)
        if not os.path.exists(file_path):
            return jsonify({'success': False, 'message': '文件不存在'}), 404
        os.remove(file_path)
        # 同时删除映射
        mapping = load_mapping()
        if uuid_name in mapping:
            del mapping[uuid_name]
            save_mapping(mapping)
        return jsonify({'success': True, 'message': '删除成功'}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': f'删除失败: {str(e)}'}), 500

if __name__ == '__main__':
    # 从config导入端口查找函数（如果存在）
    try:
        from config import PASSWORD as CFG_PASSWORD, START_PORT, find_available_port
        PASSWORD = CFG_PASSWORD
        port = find_available_port(START_PORT)
    except ImportError:
        # 如果没有config，使用默认密码和端口
        port = 5555
        # 检查端口是否被占用，若占用则自动加1
        import socket
        def is_port_in_use(port):
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                return s.connect_ex(('127.0.0.1', port)) == 0
        while is_port_in_use(port):
            port += 1

    print("=" * 50)
    print("文件上传系统启动成功！(UUID版本)")
    print(f"项目目录: {os.getcwd()}")
    print(f"访问地址: http://0.0.0.0:{port}")
    print(f"上传目录: {os.path.abspath(app.config['UPLOAD_FOLDER'])}")
    print(f"文件映射: {os.path.abspath(MAPPING_FILE)}")
    print("\n✅ 文件上传系统已启用UUID文件名模式！")
    print("   上传的文件会自动重命名为UUID格式，但下载时仍显示原始文件名。")
    print("   前端显示原始文件名，下载链接使用UUID格式。")
    print("=" * 50)

    app.run(host='0.0.0.0', port=port, debug=False, threaded=True)
EOF
