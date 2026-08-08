from flask import Flask, request, send_file, jsonify, send_from_directory, session
import os
import hashlib
import socket
import uuid
import json
import time
from datetime import datetime, timezone, timedelta
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

# ========== 新增：定义北京时间时区 ==========
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
        'upload_time': time.time()
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
            'upload_time': upload_time_str
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': f'上传失败: {str(e)}'}), 500

@app.route('/files')
def list_files():
    # 隐藏文件列表接口，直接返回 404
    return jsonify({'success': False, 'message': 'Not Found'}), 404

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
