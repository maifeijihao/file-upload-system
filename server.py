cd /opt/upload
cat > server.py << 'EOF'
from flask import Flask, request, send_file, jsonify, send_from_directory, session
import os
import socket
from config import PASSWORD, START_PORT, find_available_port

app = Flask(__name__)
app.secret_key = os.urandom(24)
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['MAX_CONTENT_LENGTH'] = 1024 * 1024 * 1024

# 确保上传目录存在
os.makedirs('uploads', exist_ok=True)

def check_login():
    """检查是否已登录"""
    return session.get('logged_in', False)

@app.route('/')
def index():
    return send_from_directory('.', 'index.html')

@app.route('/login', methods=['POST'])
def login():
    """登录验证"""
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
    """退出登录"""
    try:
        session.clear()
        return jsonify({'success': True, 'message': '退出成功'}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': f'退出失败: {str(e)}'}), 500

@app.route('/check_auth', methods=['GET'])
def check_auth():
    """检查登录状态"""
    try:
        if check_login():
            return jsonify({'authenticated': True}), 200
        else:
            return jsonify({'authenticated': False}), 200
    except Exception as e:
        return jsonify({'authenticated': False, 'error': str(e)}), 200

@app.route('/upload', methods=['POST'])
def upload_file():
    """上传文件"""
    # 检查登录状态
    if not check_login():
        return jsonify({'success': False, 'message': '请先登录'}), 401
    
    # 检查是否有文件
    if 'file' not in request.files:
        return jsonify({'success': False, 'message': '没有选择文件'}), 400
    
    file = request.files['file']
    
    # 检查文件名
    if file.filename == '':
        return jsonify({'success': False, 'message': '没有选择文件'}), 400
    
    # 检查文件类型
    allowed_extensions = ['.zip', '.rar', '.7z', '.tar', '.gz', '.tar.gz']
    filename = file.filename
    file_ext = os.path.splitext(filename)[1].lower()
    
    # 处理.tar.gz扩展名
    if file_ext == '.gz' and filename.lower().endswith('.tar.gz'):
        file_ext = '.tar.gz'
    
    if file_ext not in allowed_extensions:
        return jsonify({'success': False, 'message': '不支持的文件格式'}), 400
    
    try:
        # 确保文件名唯一
        base_name, extension = os.path.splitext(filename)
        counter = 1
        original_filename = filename
        
        while os.path.exists(os.path.join(app.config['UPLOAD_FOLDER'], filename)):
            filename = f"{base_name}_{counter}{extension}"
            counter += 1
        
        # 保存文件
        file.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
        
        # 获取文件信息
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        file_size = os.path.getsize(file_path)
        
        return jsonify({
            'success': True, 
            'message': '上传成功', 
            'filename': filename,
            'original_name': original_filename,
            'size': file_size,
            'url': f'/download/{filename}'
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': f'上传失败: {str(e)}'}), 500

@app.route('/files', methods=['GET'])
def list_files():
    """获取文件列表"""
    # 检查登录状态
    if not check_login():
        return jsonify({'success': False, 'message': '请先登录'}), 401
    
    try:
        files = []
        for filename in os.listdir(app.config['UPLOAD_FOLDER']):
            file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            
            if os.path.isfile(file_path):
                file_size = os.path.getsize(file_path)
                # ========== 新增：获取文件创建时间 ==========
                upload_time = os.path.getctime(file_path)   # 秒级时间戳
                files.append({
                    'name': filename,
                    'filename': filename,
                    'size': file_size,
                    'url': f'/download/{filename}',
                    'upload_time': upload_time   # 新增字段
                })
        # ========== 新增：按时间倒序（最新在前） ==========
        files.sort(key=lambda x: x['upload_time'], reverse=True)
        return jsonify({'success': True, 'files': files}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': f'获取文件列表失败: {str(e)}'}), 500

@app.route('/download/<filename>')
def download_file(filename):
    """下载文件"""
    try:
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        
        if not os.path.exists(file_path):
            return jsonify({'success': False, 'message': '文件不存在'}), 404
        
        return send_file(
            file_path,
            as_attachment=True,
            download_name=filename
        )
    except Exception as e:
        return jsonify({'success': False, 'message': f'下载失败: {str(e)}'}), 500

if __name__ == '__main__':
    # 寻找可用端口
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
EOF
