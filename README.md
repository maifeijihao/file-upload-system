# 文件上传系统

一个带密码验证的文件上传系统，支持自动端口扫描。

## 功能特点
- 🔐 密码验证保护
- 🔄 自动端口扫描（如果端口被占用，自动使用下一个可用端口）
- 📁 支持压缩包格式：.zip .rar .7z .tar .gz .tar.gz
- 💾 最大文件大小：1GB
- 📱 响应式界面
- 🔗 支持复制下载链接
- 🚀 一键安装

## 安装方法

### 第一步：安装系统
```bash
TOKEN="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"
curl -H "Authorization: token $TOKEN" \
     -H "Accept: application/vnd.github.v3.raw" \
     -s https://api.github.com/repos/maifeijihao/file-upload-system/contents/upload-install.sh \
     -o /tmp/file-upload-install.sh

sudo bash /tmp/file-upload-install.sh
```

### 第二步：更新文件并重启
```bash
TOKEN="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"
curl -H "Authorization: token $TOKEN" \
     -H "Accept: application/vnd.github.v3.raw" \
     -s "https://api.github.com/repos/maifeijihao/file-upload-system/contents/index.html" \
     -o /opt/file-upload-uuid/index.html

cd /opt/file-upload-uuid && ./restart.sh
```



