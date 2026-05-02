import os
import sqlite3
import re
import time
import uuid
from flask import Flask, request, jsonify, send_from_directory, render_template, session
from werkzeug.utils import secure_filename
from datetime import datetime
from functools import wraps

app = Flask(__name__)
app.secret_key = os.urandom(24)  # 用于 session
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['MAX_CONTENT_LENGTH'] = 1024 * 1024 * 1024  # 1GB
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

# 简单密码验证（请修改为您自己的密码）
ADMIN_PASSWORD = 'admin123'  # 建议改为强密码

def init_db():
    conn = sqlite3.connect('files.db')
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS files
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  uuid TEXT UNIQUE NOT NULL,
                  filename TEXT NOT NULL,
                  original_name TEXT NOT NULL,
                  size INTEGER NOT NULL,
                  upload_time TEXT NOT NULL)''')
    conn.commit()
    conn.close()

init_db()

def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not session.get('authenticated'):
            return jsonify({'success': False, 'message': '未授权'}), 401
        return f(*args, **kwargs)
    return decorated_function

def safe_filename(original_name):
    """生成安全的文件名，重名时自动添加 _数字"""
    # 分离基础名和扩展名
    if original_name.lower().endswith('.tar.gz'):
        base = original_name[:-7]
        ext = '.tar.gz'
    else:
        base, ext = os.path.splitext(original_name)
    
    # 清理基础名（去除危险字符，保留中文、字母、数字、点、空格、下划线）
    base = re.sub(r'[\\/*?:"<>|]', '', base)
    base = base.strip()
    if not base:
        base = f"file_{int(time.time())}"
    
    # 重名检测：生成 base.ext，如果存在则 base_1.ext，base_2.ext ...
    final_name = base + ext
    counter = 1
    while os.path.exists(os.path.join(app.config['UPLOAD_FOLDER'], final_name)):
        final_name = f"{base}_{counter}{ext}"
        counter += 1
    return final_name

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/check_auth')
def check_auth():
    return jsonify({'authenticated': session.get('authenticated', False)})

@app.route('/login', methods=['POST'])
def login():
    data = request.json
    password = data.get('password', '')
    if password == ADMIN_PASSWORD:
        session['authenticated'] = True
        return jsonify({'success': True})
    return jsonify({'success': False, 'message': '密码错误'})

@app.route('/logout', methods=['POST'])
def logout():
    session.pop('authenticated', None)
    return jsonify({'success': True})

@app.route('/upload', methods=['POST'])
@login_required
def upload_file():
    if 'file' not in request.files:
        return jsonify({'success': False, 'message': '没有文件'}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({'success': False, 'message': '文件名为空'}), 400
    
    # 生成服务器存储的文件名（带重名处理）
    server_filename = safe_filename(file.filename)
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], server_filename)
    file.save(filepath)
    
    # 生成唯一 UUID（用于下载链接）
    file_uuid = str(uuid.uuid4())
    size = os.path.getsize(filepath)
    upload_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    conn = sqlite3.connect('files.db')
    c = conn.cursor()
    c.execute("INSERT INTO files (uuid, filename, original_name, size, upload_time) VALUES (?, ?, ?, ?, ?)",
              (file_uuid, server_filename, file.filename, size, upload_time))
    conn.commit()
    conn.close()
    
    return jsonify({
        'success': True,
        'uuid_filename': file_uuid,
        'filename': server_filename,      # 服务器实际存储的文件名
        'original_name': file.filename,
        'size': size,
        'upload_time': upload_time
    })

@app.route('/files', methods=['GET'])
@login_required
def list_files():
    conn = sqlite3.connect('files.db')
    c = conn.cursor()
    c.execute("SELECT uuid, filename, original_name, size, upload_time FROM files ORDER BY upload_time DESC")
    rows = c.fetchall()
    conn.close()
    files = []
    for row in rows:
        files.append({
            'uuid': row[0],
            'filename': row[1],
            'original_name': row[2],
            'size': row[3],
            'upload_time': row[4]
        })
    return jsonify({'success': True, 'files': files})

@app.route('/download/<uuid>')
@login_required
def download_file(uuid):
    conn = sqlite3.connect('files.db')
    c = conn.cursor()
    c.execute("SELECT filename FROM files WHERE uuid=?", (uuid,))
    row = c.fetchone()
    conn.close()
    if not row:
        return '文件不存在', 404
    filename = row[0]
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename, as_attachment=True)

@app.route('/delete/<uuid>', methods=['DELETE'])
@login_required
def delete_file(uuid):
    conn = sqlite3.connect('files.db')
    c = conn.cursor()
    c.execute("SELECT filename FROM files WHERE uuid=?", (uuid,))
    row = c.fetchone()
    if not row:
        conn.close()
        return jsonify({'success': False, 'message': '文件不存在'}), 404
    filename = row[0]
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    if os.path.exists(filepath):
        os.remove(filepath)
    c.execute("DELETE FROM files WHERE uuid=?", (uuid,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
