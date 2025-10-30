#!/bin/bash
#
# GNB 编译系统 - 上传脚本
# 负责将编译产物上传到远程服务器
#

set -e

# ==================== 加载配置和依赖库 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载工具函数库
source "$SCRIPT_DIR/lib/utils.sh"

# 尝试加载 config.env 配置文件
if [ -f "$SCRIPT_DIR/config.env" ]; then
    source "$SCRIPT_DIR/config.env"
fi

# ==================== 配置区域 ====================
# SSH 服务器配置 (兼容多种变量名)
SSH_HOST="${DOWNLOAD_SSH_HOST:-${SSH_HOST:-}}"           # SSH 服务器地址
SSH_USER="${DOWNLOAD_SSH_USER:-${SSH_USER:-}}"           # SSH 用户名
SSH_PORT="${DOWNLOAD_SSH_PORT:-${SSH_PORT:-22}}"         # SSH 端口
SSH_KEY="${DOWNLOAD_SSH_KEY_PATH:-${SSH_KEY:-~/.ssh/id_rsa}}" # SSH 私钥路径
REMOTE_DIR="${DOWNLOAD_SSH_REMOTE_DIR:-${REMOTE_DIR:-}}" # 远程目录路径

# 项目配置
WORKSPACE_DIR="${WORKSPACE_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
DIST_DIR="${DIST_DIR:-$WORKSPACE_DIR/dist}"

# ==================== 上传函数 ====================

# 上传到服务器
upload_to_server() {
    local version=$1
    local dist_dir="${2:-$DIST_DIR}"
    local source_dir="$dist_dir/$version"
    
    print_info "准备上传到服务器..."
    
    # 验证配置
    if [ -z "$SSH_HOST" ] || [ -z "$SSH_USER" ] || [ -z "$REMOTE_DIR" ]; then
        print_error "SSH 配置不完整，请设置 SSH_HOST, SSH_USER, REMOTE_DIR 环境变量"
        print_info "可以在 config.env 文件中配置，或通过环境变量传递"
        return 1
    fi
    
    if [ ! -f "$SSH_KEY" ]; then
        print_error "SSH 私钥不存在: $SSH_KEY"
        return 1
    fi
    
    if [ ! -d "$source_dir" ]; then
        print_error "源目录不存在: $source_dir"
        return 1
    fi
    
    local dest_dir="${REMOTE_DIR%/}/${version}/"
    
    print_info "SSH 配置:"
    print_info "  主机: $SSH_USER@$SSH_HOST:$SSH_PORT"
    print_info "  源目录: $source_dir"
    print_info "  目标: $dest_dir"
    
    # SSH 选项
    local ssh_opts="-i $SSH_KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15"
    
    # 测试连接
    print_info "测试 SSH 连接..."
    if ! ssh $ssh_opts "$SSH_USER@$SSH_HOST" "echo 'SSH 连接成功'"; then
        print_error "SSH 连接失败"
        return 1
    fi
    
    # 创建远程目录
    print_info "创建远程目录..."
    ssh $ssh_opts "$SSH_USER@$SSH_HOST" "mkdir -p '$dest_dir'"
    
    # 使用 rsync 上传
    print_info "开始上传文件..."
    if rsync -avz --progress -e "ssh $ssh_opts" "$source_dir/" "$SSH_USER@$SSH_HOST:$dest_dir"; then
        print_success "文件上传完成"
        
        # 显示上传的文件列表
        print_info "远程文件列表:"
        ssh $ssh_opts "$SSH_USER@$SSH_HOST" "cd '$dest_dir' && ls -lh *.tgz checksums.txt 2>/dev/null | tail -20"
        
        return 0
    else
        print_error "文件上传失败"
        return 1
    fi
}

# ==================== 显示帮助 ====================

show_help() {
    cat << EOF
GNB 上传脚本

使用方法:
    $0 <版本号> [选项]

参数:
    <版本号>        要上传的版本号，如 v1.5.3

选项:
    -h, --help              显示此帮助信息
    --dist-dir DIR          指定 dist 目录路径 (默认: $DIST_DIR)

环境变量配置:
    DOWNLOAD_SSH_HOST           SSH 服务器地址
    DOWNLOAD_SSH_USER           SSH 用户名
    DOWNLOAD_SSH_PORT           SSH 端口 (默认: 22)
    DOWNLOAD_SSH_KEY_PATH       SSH 私钥路径
    DOWNLOAD_SSH_REMOTE_DIR     远程目录路径

示例:
    # 上传指定版本
    $0 ver1.6.0.a

    # 指定自定义 dist 目录
    $0 ver1.6.0.a --dist-dir /path/to/dist

配置文件:
    可以在 $SCRIPT_DIR/config.env 中配置 SSH 参数

EOF
}

# ==================== 主程序 ====================

main() {
    local version=""
    local custom_dist_dir=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --dist-dir|--dist-dir=*)
                if [[ "$1" == --dist-dir=* ]]; then
                    custom_dist_dir="${1#*=}"
                    shift
                else
                    custom_dist_dir="$2"
                    shift 2
                fi
                ;;
            -*)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                version=$1
                shift
                ;;
        esac
    done
    
    # 验证版本号
    if [ -z "$version" ]; then
        print_error "请指定版本号"
        show_help
        exit 1
    fi
    
    # 使用自定义 dist 目录（如果指定）
    if [ -n "$custom_dist_dir" ]; then
        DIST_DIR="$custom_dist_dir"
    fi
    
    print_info "=========================================="
    print_info "GNB 上传脚本"
    print_info "版本: $version"
    print_info "Dist 目录: $DIST_DIR"
    print_info "=========================================="
    
    # 检查编译产物是否存在
    if [ ! -d "$DIST_DIR/$version" ]; then
        print_error "编译产物不存在: $DIST_DIR/$version"
        print_info "请先运行编译命令"
        exit 1
    fi
    
    # 检查是否存在校验和文件
    if [ ! -f "$DIST_DIR/$version/checksums.txt" ]; then
        print_warning "校验和文件不存在，正在生成..."
        if ! generate_checksums "$version" "$DIST_DIR"; then
            print_warning "校验和生成失败，但继续上传"
        fi
    fi
    
    # 上传到服务器
    if upload_to_server "$version" "$DIST_DIR"; then
        print_success "=========================================="
        print_success "上传完成！"
        print_success "=========================================="
        exit 0
    else
        print_error "上传失败"
        exit 1
    fi
}

# 运行主程序（仅当直接执行时）
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
    main "$@"
fi
