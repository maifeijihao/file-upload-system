import os
import time
from flask import Flask, request, jsonify, send_from_directory, session
from werkzeug.utils import secure_filename
from functools import wraps

app = Flask(__name__)
app.secret_key = 'your-secret-key-here'  # 请修改为随机字符串

# 配置
UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'zip', 'rar', '7z', 'tar', 'gz', 'tar.gz'}
MAX_CONTENT_LENGTH = 1 * 1024 * 1024 * 1024  # 1GB

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = MAX_CONTENT_LENGTH

os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# 访问密码（请修改）
ACCESS_PASSWORD = 'your_password'


def allowed_file(filename):
    """检查文件扩展名是否允许"""
    if filename.lower().endswith('.tar.gz'):
        return True
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not session.get('authenticated'):
            return jsonify({'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated_function


@app.route('/check_auth', methods=['GET'])
def check_auth():
    return jsonify({'authenticated': session.get('authenticated', False)})


@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    password = data.get('password', '')
    if password == ACCESS_PASSWORD:
        session['authenticated'] = True
        return jsonify({'success': True, 'message': '验证成功'})
    return jsonify({'success': False, 'message': '密码错误'}), 401


@app.route('/logout', methods=['POST'])
def logout():
    session.pop('authenticated', None)
    return jsonify({'success': True})


def safe_filename(original_name):
    """
    生成安全的文件名：保留原始文件名（安全化），重名时加数字后缀。
    绝不产生 UUID。
    """
    # 安全化文件名（移除危险字符，保留中文等）
    safe = secure_filename(original_name)
    # 如果 secure_filename 返回空（例如原文件名全是非法字符），则使用时间戳
    if not safe:
        safe = f"file_{int(time.time())}"
        print(f"警告: 原文件名 '{original_name}' 安全化后为空，使用 '{safe}'")
    
    # 分离基础名和扩展名（处理 .tar.gz）
    if safe.lower().endswith('.tar.gz'):
        base_name = safe[:-7]
        extension = '.tar.gz'
    else:
        base_name, extension = os.path.splitext(safe)
    
    # 重名处理
    final_name = safe
    counter = 1
    while os.path.exists(os.path.join(app.config['UPLOAD_FOLDER'], final_name)):
        final_name = f"{base_name}_{counter}{extension}"
        counter += 1
    
    return final_name


@app.route('/upload', methods=['POST'])
@login_required
def upload_file():
    if 'file' not in request.files:
        return jsonify({'success': False, 'message': '没有文件部分'}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({'success': False, 'message': '未选择文件'}), 400
    if not allowed_file(file.filename):
        return jsonify({'success': False, 'message': '不支持的文件类型'}), 400
    
    # 生成最终保存的文件名（保证可读，绝不使用 UUID）
    final_filename = safe_filename(file.filename)
    save_path = os.path.join(app.config['UPLOAD_FOLDER'], final_filename)
    file.save(save_path)
    
    print(f"文件已保存: {final_filename} (原文件名: {file.filename})")
    
    return jsonify({
        'success': True,
        'message': '上传成功',
        'uuid_filename': final_filename,   # 实际上就是原始文件名（可能带数字后缀）
        'original_name': file.filename
    })


@app.route('/files', methods=['GET'])
@login_required
def list_files():
    files = []
    for filename in os.listdir(app.config['UPLOAD_FOLDER']):
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        if os.path.isfile(filepath):
            stat = os.stat(filepath)
            files.append({
                'name': filename,
                'filename': filename,
                'size': stat.st_size,
                'modified': stat.st_mtime,
                'url': f'/download/{filename}'
            })
    # 按修改时间倒序
    files.sort(key=lambda x: x['modified'], reverse=True)
    return jsonify({'success': True, 'files': files})


@app.route('/download/<path:filename>', methods=['GET'])
@login_required
def download_file(filename):
    safe_path = os.path.join(app.config['UPLOAD_FOLDER'], os.path.basename(filename))
    if not os.path.exists(safe_path):
        return jsonify({'error': '文件不存在'}), 404
    return send_from_directory(app.config['UPLOAD_FOLDER'], os.path.basename(filename), as_attachment=True)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
