cd /opt/upload
cat > server.py << 'EOF'
import os
import re
import time
from flask import Flask, request, jsonify, send_from_directory, session
from werkzeug.utils import secure_filename
from functools import wraps

app = Flask(__name__)
app.secret_key = 'your-secret-key-here'  # 请替换为随机字符串

# 配置
UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'zip', 'rar', '7z', 'tar', 'gz', 'tar.gz'}
MAX_CONTENT_LENGTH = 1 * 1024 * 1024 * 1024  # 1GB

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = MAX_CONTENT_LENGTH

os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# 密码（请修改）
ACCESS_PASSWORD = 'your_password'

# 匹配标准UUID（带连字符）以及32位十六进制（无连字符）
UUID_PATTERN = re.compile(
    r'^(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{32})\.(?:zip|rar|7z|tar|gz|tar\.gz)$',
    re.IGNORECASE
)

def allowed_file(filename):
    if filename.lower().endswith('.tar.gz'):
        return True
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def is_uuid_filename(filename):
    return bool(UUID_PATTERN.match(filename))

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

def get_final_filename(original_filename):
    safe_name = secure_filename(original_filename)
    
    # 如果文件名是UUID格式，重命名为 file_时间戳.扩展名
    if is_uuid_filename(safe_name):
        if safe_name.lower().endswith('.tar.gz'):
            extension = '.tar.gz'
            base = safe_name[:-7]
        else:
            base, extension = os.path.splitext(safe_name)
        safe_name = f"file_{int(time.time())}{extension}"
        print(f"检测到 UUID 文件名，已重命名为: {safe_name}")
    
    # 处理 .tar.gz 特殊情况
    if safe_name.lower().endswith('.tar.gz'):
        base_name = safe_name[:-7]
        extension = '.tar.gz'
    else:
        base_name, extension = os.path.splitext(safe_name)
    
    # 重名冲突处理
    final_name = safe_name
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
    
    final_filename = get_final_filename(file.filename)
    file.save(os.path.join(app.config['UPLOAD_FOLDER'], final_filename))
    print(f"文件已保存: {final_filename} (原文件名: {file.filename})")
    
    return jsonify({
        'success': True,
        'message': '上传成功',
        'uuid_filename': final_filename,
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
