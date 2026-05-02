cd /opt/upload
cat > server.py << 'EOF'
import os
import uuid
import shutil
from datetime import datetime
from flask import Flask, request, jsonify, send_from_directory, session, redirect, url_for
from werkzeug.utils import secure_filename
from functools import wraps

app = Flask(__name__)
app.secret_key = 'your-secret-key-here'  # 请替换为随机字符串，建议从环境变量读取

# 配置
UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'zip', 'rar', '7z', 'tar', 'gz', 'tar.gz'}
MAX_CONTENT_LENGTH = 1 * 1024 * 1024 * 1024  # 1GB

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = MAX_CONTENT_LENGTH

# 确保上传目录存在
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# 密码验证（请修改为你自己的密码）
ACCESS_PASSWORD = 'your_password'  # 请替换为实际密码


def allowed_file(filename):
    """检查文件扩展名是否允许"""
    # 处理.tar.gz特殊情况
    if filename.lower().endswith('.tar.gz'):
        return True
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def login_required(f):
    """登录验证装饰器"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not session.get('authenticated'):
            return jsonify({'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated_function


@app.route('/check_auth', methods=['GET'])
def check_auth():
    """检查认证状态"""
    return jsonify({'authenticated': session.get('authenticated', False)})


@app.route('/login', methods=['POST'])
def login():
    """登录验证"""
    data = request.get_json()
    password = data.get('password', '')
    if password == ACCESS_PASSWORD:
        session['authenticated'] = True
        return jsonify({'success': True, 'message': '验证成功'})
    else:
        return jsonify({'success': False, 'message': '密码错误'}), 401


@app.route('/logout', methods=['POST'])
def logout():
    """登出"""
    session.pop('authenticated', None)
    return jsonify({'success': True})


@app.route('/upload', methods=['POST'])
@login_required
def upload_file():
    """上传文件（修改了文件命名逻辑，不再使用 UUID）"""
    if 'file' not in request.files:
        return jsonify({'success': False, 'message': '没有文件部分'}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({'success': False, 'message': '未选择文件'}), 400
    
    if not allowed_file(file.filename):
        return jsonify({'success': False, 'message': '不支持的文件类型'}), 400
    
    # 获取安全化的原始文件名
    original_filename = secure_filename(file.filename)
    # 分离基础名和扩展名（处理 .tar.gz）
    if original_filename.lower().endswith('.tar.gz'):
        base_name = original_filename[:-7]
        extension = '.tar.gz'
    else:
        base_name, extension = os.path.splitext(original_filename)
    
    # 处理重名：如果文件已存在，添加 _1, _2, ... 后缀
    final_filename = original_filename
    counter = 1
    while os.path.exists(os.path.join(app.config['UPLOAD_FOLDER'], final_filename)):
        final_filename = f"{base_name}_{counter}{extension}"
        counter += 1
    
    # 保存文件（最终文件名是原始名或带数字后缀，不再使用 UUID）
    file.save(os.path.join(app.config['UPLOAD_FOLDER'], final_filename))
    
    return jsonify({
        'success': True,
        'message': '上传成功',
        'uuid_filename': final_filename,   # 这里实际是可读的文件名
        'original_name': original_filename
    })


@app.route('/files', methods=['GET'])
@login_required
def list_files():
    """获取所有已上传文件列表"""
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
    # 按修改时间倒序排列（最新在上）
    files.sort(key=lambda x: x['modified'], reverse=True)
    return jsonify({'success': True, 'files': files})


@app.route('/download/<path:filename>', methods=['GET'])
@login_required
def download_file(filename):
    """下载文件"""
    # 防止路径穿越攻击
    safe_path = os.path.join(app.config['UPLOAD_FOLDER'], os.path.basename(filename))
    if not os.path.exists(safe_path):
        return jsonify({'error': '文件不存在'}), 404
    return send_from_directory(app.config['UPLOAD_FOLDER'], os.path.basename(filename), as_attachment=True)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
