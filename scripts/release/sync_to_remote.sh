#!/bin/bash
# 同步编译脚本到远程服务器

REMOTE_HOST="arthur@192.168.0.32"
REMOTE_DIR="~/mynet/gnb"
LOCAL_DIR="/Users/arthur/Devel/WorkSpacePHP/lyt.com/mynet_gnb"

echo "=========================================="
echo "同步到 $REMOTE_HOST ..."
echo "=========================================="

# 同步主脚本
echo "→ 同步主脚本..."
rsync -avz \
    "$LOCAL_DIR/scripts/release/build_and_upload.sh" \
    "$LOCAL_DIR/scripts/release/build_linux.sh" \
    "$LOCAL_DIR/scripts/release/build_openwrt.sh" \
    "$LOCAL_DIR/scripts/release/build_embedded_musl.sh" \
    "$LOCAL_DIR/scripts/release/upload.sh" \
    "$LOCAL_DIR/scripts/release/install_toolchains.sh" \
    "$LOCAL_DIR/scripts/release/sync_to_remote.sh" \
    "$REMOTE_HOST:$REMOTE_DIR/scripts/release/"

# 同步函数库
echo "→ 同步函数库..."
rsync -avz \
    "$LOCAL_DIR/scripts/release/lib/" \
    "$REMOTE_HOST:$REMOTE_DIR/scripts/release/lib/"

# 同步配置和文档
echo "→ 同步配置和文档..."
rsync -avz \
    "$LOCAL_DIR/scripts/release/config.env" \
    "$LOCAL_DIR/scripts/release/config.env.example" \
    "$LOCAL_DIR/scripts/release/USAGE.md" \
    "$LOCAL_DIR/scripts/release/QUICK_REFERENCE.md" \
    "$LOCAL_DIR/scripts/release/REFACTOR_COMPLETE.md" \
    "$LOCAL_DIR/scripts/release/TOOLCHAIN_STRUCTURE.md" \
    "$LOCAL_DIR/scripts/release/TOOLCHAIN_COMPARISON.md" \
    "$REMOTE_HOST:$REMOTE_DIR/scripts/release/"

# 同步源码 Makefile
echo "→ 同步 Makefile..."
rsync -avz \
    "$LOCAL_DIR/src/Makefile.linux" \
    "$LOCAL_DIR/src/Makefile.openwrt" \
    "$REMOTE_HOST:$REMOTE_DIR/src/"

# 设置可执行权限
echo "→ 设置可执行权限..."
ssh "$REMOTE_HOST" "chmod +x $REMOTE_DIR/scripts/release/*.sh $REMOTE_DIR/scripts/release/lib/*.sh"

echo "=========================================="
echo "✓ 同步完成"
echo "=========================================="
