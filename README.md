# 文件上传系统

一个带密码验证的文件上传系统，支持自动端口扫描。

## 功能特点
- 🔐 密码验证保护【支持Ubuntu 20.04 64 Bit】
- 🔄 自动端口扫描（如果端口被占用，自动使用下一个可用端口）
- 📁 支持压缩包格式：.zip .rar .7z .tar .gz .tar.gz
- 💾 最大文件大小：1GB
- 📱 响应式界面
- 🔗 支持复制下载链接
- 🚀 一键安装

## 安装方法

### 第一步：安装系统
```bash
sudo apt update && sudo apt install -y curl && curl -s -o /tmp/install.sh https://raw.githubusercontent.com/maifeijihao/file-upload-system/main/upload-install.sh && sed -i 's/--break-system-packages //g' /tmp/install.sh && sudo bash /tmp/install.sh
```

### 第二步：更新文件并重启
```bash
curl -fsSL https://raw.githubusercontent.com/maifeijihao/file-upload-system/main/index.html -o /opt/file-upload-uuid/index.html && cd /opt/file-upload-uuid && sudo ./restart.sh
```




