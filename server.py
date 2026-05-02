import os
import sqlite3
import re
import time
from flask import Flask, request, jsonify, send_from_directory, render_template
from werkzeug.utils import secure_filename
from datetime import datetime

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['MAX_CONTENT_LENGTH'] = 1024 * 1024 * 1024
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

def init_db():
    conn = sqlite3.connect('files.db')
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS files
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  filename TEXT NOT NULL,
                  size INTEGER NOT NULL,
                  upload_time TEXT NOT NULL)''')
    conn.commit()
    conn.close()

init_db()

def safe_filename(filename):
    if filename.lower().endswith('.tar.gz'):
        base = filename[:-7]
        ext = '.tar.gz'
    else:
        base, ext = os.path.splitext(filename)
    
    base = re.sub(r'[\\/*?:"<>|]', '', base)
    base = base.strip()
    if not base:
        base = f"file_{int(time.time())}"
    
    final_name = base + ext
    counter = 1
    while os.path.exists(os.path.join(app.config['UPLOAD_FOLDER'], final_name)):
        final_name = f"{base}_{counter}{ext}"
        counter += 1
    return final_name

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400
    
    filename = safe_filename(file.filename)
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    file.save(filepath)
    
    size = os.path.getsize(filepath)
    upload_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    conn = sqlite3.connect('files.db')
    c = conn.cursor()
    c.execute("INSERT INTO files (filename, size, upload_time) VALUES (?, ?, ?)",
              (filename, size, upload_time))
    conn.commit()
    file_id = c.lastrowid
    conn.close()
    
    return jsonify({
        'id': file_id,
        'filename': filename,
        'size': size,
        'upload_time': upload_time
    })

@app.route('/files', methods=['GET'])
def list_files():
    conn = sqlite3.connect('files.db')
    c = conn.cursor()
    c.execute("SELECT id, filename, size, upload_time FROM files ORDER BY upload_time DESC")
    rows = c.fetchall()
    conn.close()
    files = []
    for row in rows:
        files.append({
            'id': row[0],
            'filename': row[1],
            'size': row[2],
            'upload_time': row[3]
        })
    return jsonify(files)

@app.route('/delete/<int:file_id>', methods=['DELETE'])
def delete_file(file_id):
    conn = sqlite3.connect('files.db')
    c = conn.cursor()
    c.execute("SELECT filename FROM files WHERE id=?", (file_id,))
    row = c.fetchone()
    if not row:
        conn.close()
        return jsonify({'error': 'File not found'}), 404
    filename = row[0]
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    if os.path.exists(filepath):
        os.remove(filepath)
    c.execute("DELETE FROM files WHERE id=?", (file_id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/download/<int:file_id>')
def download_file(file_id):
    conn = sqlite3.connect('files.db')
    c = conn.cursor()
    c.execute("SELECT filename FROM files WHERE id=?", (file_id,))
    row = c.fetchone()
    conn.close()
    if not row:
        return 'File not found', 404
    filename = row[0]
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename, as_attachment=True)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
