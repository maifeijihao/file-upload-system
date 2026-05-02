from flask import Flask, request, send_file, jsonify, send_from_directory, session
import os
import socket
import json
import time
from config import PASSWORD, START_PORT, find_available_port

app = Flask(__name__)
app.secret_key = os.urandom(24)
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['MAX_CONTENT_LENGTH'] = 1024 * 1024 * 1024

# 确保上传目录存在
os.makedirs('uploads', exist_ok=True)

# 元数据文件路径
METADATA_FILE = os.path.join(app.config['UPLOAD_FOLDER'], 'upload_metadata.json')

def load_metadata():
    """安全加载上传元数据，出错时返回空字典"""
    if not os.path.exists(METADATA_FILE):
        return {}
    try:
        with open(METADATA_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        # 损坏或无法读取时返回空，不影响主流程
        return {}

def save_metadata(metadata):
    """保存元数据，忽略写入错误"""
    try:
        with open(METADATA_FILE, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, ensure_ascii=False, indent=2)
    except IOError:
        pass  # 上传本身的成功不受影响

def set_file_upload_time(filename, timestamp=None):
    if timestamp is None:
        timestamp = time.time()
    metadata = load_metadata()
    metadata[filename] = timestamp
    save_metadata(metadata)

def get_file_upload_time(filename):
    """获取上传时间，没有则返回文件修改时间或 None"""
    metadata = load_metadata()
    if filename in metadata:
        return metadata[filename]
    file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    if os.path.exists(file_path):
        return os.path.getmtime(file_path)
    return None

def check_login():
    return session.get('logged_in', False)

@app.route('/')
def index():
    return send_from_directory('.', 'index.html')

@app.route('/login', methods=['POST'])
def login():
    try:
        data = request.get_json()
        if not data or 'password' not in data:
            return jsonify({'success': False, 'message': '密码不能为空'}), 400
        if data['password'] == PASSWORD:
            session['logged_in'] = True
            return jsonify({'success': True, 'message': '登录成功'}), 200
        else:
            return jsonify({'success': False, 'message': '密码错误'}), 401
    except Exception as e:
        return jsonify({'success': False, 'message': f'登录失败: {str(e)}'}), 500

@app.route('/logout', methods=['POST'])
def logout():
    try:
        session.clear()
        return jsonify({'success': True, 'message': '退出成功'}), 200
    except Exception:
        return jsonify({'success': False, 'message': '退出失败'}), 500

@app.route('/check_auth', methods=['GET'])
def check_auth():
    try:
        if check_login():
            return jsonify({'authenticated': True}), 200
        else:
            return jsonify({'authenticated': False}), 200
    except Exception:
        return jsonify({'authenticated': False}), 200

@app.route('/upload', methods=['POST'])
def upload_file():
    if not check_login():
        return jsonify({'success': False, 'message': '请先登录'}), 401
    if 'file' not in request.files:
        return jsonify({'success': False, 'message': '没有选择文件'}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({'success': False, 'message': '没有选择文件'}), 400

    allowed_extensions = ['.zip', '.rar', '.7z', '.tar', '.gz', '.tar.gz']
    filename = file.filename
    file_ext = os.path.splitext(filename)[1].lower()
    if file_ext == '.gz' and filename.lower().endswith('.tar.gz'):
        file_ext = '.tar.gz'
    if file_ext not in allowed_extensions:
        return jsonify({'success': False, 'message': '不支持的文件格式'}), 400

    try:
        base_name, extension = os.path.splitext(filename)
        counter = 1
        original_filename = filename
        while os.path.exists(os.path.join(app.config['UPLOAD_FOLDER'], filename)):
            filename = f"{base_name}_{counter}{extension}"
            counter += 1

        file.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
        upload_timestamp = time.time()
        set_file_upload_time(filename, upload_timestamp)

        file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        file_size = os.path.getsize(file_path)

        return jsonify({
            'success': True,
            'message': '上传成功',
            'filename': filename,
            'original_name': original_filename,
            'size': file_size,
            'url': f'/download/{filename}',
            'upload_time': upload_timestamp
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': f'上传失败: {str(e)}'}), 500

@app.route('/files', methods=['GET'])
def list_files():
    if not check_login():
        return jsonify({'success': False, 'message': '请先登录'}), 401
    try:
        files = []
        for filename in os.listdir(app.config['UPLOAD_FOLDER']):
            if filename == 'upload_metadata.json':
                continue
            file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            if not os.path.isfile(file_path):
                continue
            file_size = os.path.getsize(file_path)
            upload_time = get_file_upload_time(filename)
            files.append({
                'name': filename,
                'filename': filename,
                'size': file_size,
                'url': f'/download/{filename}',
                'upload_time': upload_time
            })
        return jsonify({'success': True, 'files': files}), 200
    except Exception as e:
        # 即使出错也返回空列表，保证前端不崩溃
        return jsonify({'success': True, 'files': [], 'message': str(e)}), 200

@app.route('/download/<filename>')
def download_file(filename):
    try:
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        if not os.path.exists(file_path):
            return jsonify({'success': False, 'message': '文件不存在'}), 404
        return send_file(file_path, as_attachment=True, download_name=filename)
    except Exception as e:
        return jsonify({'success': False, 'message': f'下载失败: {str(e)}'}), 500

if __name__ == '__main__':
    port = find_available_port(START_PORT)
    if port is None:
        print(f"错误：从端口{START_PORT}开始，没有找到可用端口！")
        exit(1)
    if port != START_PORT:
        print(f"端口{START_PORT}被占用，使用端口{port}")
    print("=" * 50)
    print("文件上传系统启动成功！")
    print(f"访问地址: http://0.0.0.0:{port}")
    print(f"上传目录: {os.path.abspath(app.config['UPLOAD_FOLDER'])}")
    print("支持格式: .zip .rar .7z .tar .gz .tar.gz")
    print("最大大小: 1GB")
    print("=" * 50)
    app.run(host='0.0.0.0', port=port, debug=False, threaded=True)
