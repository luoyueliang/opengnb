#!/bin/bash
#
# GNB 编译系统 - 主入口脚本（路由器）
# 根据参数路由到对应的编译脚本，并处理上传
#

# 注意: 不使用 set -e，以便可以继续处理失败的情况

# ==================== 加载配置和依赖库 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载工具函数库
source "$SCRIPT_DIR/lib/utils.sh"

# 尝试加载 config.env 配置文件
if [ -f "$SCRIPT_DIR/config.env" ]; then
    source "$SCRIPT_DIR/config.env"
fi

# ==================== 配置区域 ====================
PROJECT="gnb"
WORKSPACE_DIR="${WORKSPACE_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$WORKSPACE_DIR/.build}"
DIST_DIR="${DIST_DIR:-$WORKSPACE_DIR/dist}"

# ==================== 显示帮助 ====================

show_help() {
    cat << EOF
GNB Linux 本地编译与上传脚本

使用方法:
    $0 [选项] <版本号>

参数:
    <版本号>        版本号，如 v1.5.3

选项:
    -h, --help              显示此帮助信息
    --no-upload             仅编译，不上传到服务器
    --upload-only           仅上传已编译的文件，不重新编译
    --arch ARCH             仅编译指定架构 (可多次使用，格式: os:arch)
    --clean                 编译前清理输出目录
    --sdk-version VERSION   OpenWRT SDK 版本 (默认: 24.10)
                            可选: 19.07, 21.02, 22.03, 23.05, 24.10

编译策略:
    Linux 平台 (linux:arch):
      - GNU gcc + glibc 动态链接
      - 适用于标准 Linux 发行版
      → 调用 build_linux.sh
    
    OpenWRT 平台 (openwrt:arch):
      - OpenWRT SDK (默认 24.10) + musl 静态链接
      - 适用于所有 OpenWRT 路由器(向下兼容)
      - 可通过 --sdk-version 指定特定版本
      → 调用 build_openwrt.sh
    
    嵌入式平台 (embedded:arch):
      - musl-cross + musl 静态链接
      - 适用于使用 musl libc 的自定义嵌入式系统
      → 调用 build_embedded_musl.sh

环境变量配置 (可选):
    DOWNLOAD_SSH_HOST           SSH 服务器地址
    DOWNLOAD_SSH_USER           SSH 用户名
    DOWNLOAD_SSH_PORT           SSH 端口 (默认: 22)
    DOWNLOAD_SSH_KEY_PATH       SSH 私钥路径
    DOWNLOAD_SSH_REMOTE_DIR     远程目录路径

示例:
    # 编译 Linux + OpenWRT 所有架构并上传 (默认 SDK 24.10)
    $0 v1.5.3

    # 使用 OpenWRT SDK 23.05 编译
    $0 --sdk-version=23.05 v1.5.3

    # 仅编译不上传
    $0 --no-upload v1.5.3
    
    # 仅编译特定架构
    $0 --arch linux:arm64 --arch openwrt:mipsel v1.5.3
    
    # 编译嵌入式 musl 系统
    $0 --arch embedded:mipsel v1.5.3
    
    # 仅上传已编译的文件
    $0 --upload-only ver1.6.0.a

可用架构列表:
    x86:
      - amd64, i386
    ARM 64位:
      - arm64
    ARM 32位 v7:
      - armv7 (默认hard-float), armv7-softfp
    MIPS 64位:
      - mips64, mips64el
    MIPS 32位:
      - mips (默认hard-float), mips-softfp
      - mipsel (默认hard-float), mipsel-softfp
    RISC-V 64位:
      - riscv64

命名规范:
    - 默认hard-float不加后缀: armv7, mips, mipsel
    - soft-float加-softfp后缀: armv7-softfp, mips-softfp, mipsel-softfp
    - 文件命名: gnb_{os}_{arch}_{version}.tgz

子脚本:
    本脚本会根据参数调用以下子脚本：
    - build_linux.sh           标准 Linux (GNU gcc + glibc 动态)
    - build_openwrt.sh         OpenWRT 设备 (SDK 24.10 + musl 静态)
    - build_embedded_musl.sh   嵌入式设备 (musl-cross + musl 静态)
    - upload.sh                上传到服务器

目标平台选择:
    linux:xxx       标准 Linux 发行版 (静态链接 glibc, 推荐用于非路由设备)
    openwrt:xxx     OpenWRT 路由器 (静态链接 musl)
    embedded:xxx    musl 嵌入式系统 (静态链接 musl)

EOF
}

# ==================== 主程序 ====================

main() {
    local version=""
    local no_upload=false
    local upload_only=false
    local clean=false
    local selected_arches=()
    local sdk_version=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --no-upload)
                no_upload=true
                shift
                ;;
            --upload-only)
                upload_only=true
                shift
                ;;
            --clean)
                clean=true
                shift
                ;;
            --arch|--arch=*)
                if [[ "$1" == --arch=* ]]; then
                    selected_arches+=("${1#*=}")
                    shift
                else
                    selected_arches+=("$2")
                    shift 2
                fi
                ;;
            --sdk-version|--sdk-version=*)
                if [[ "$1" == --sdk-version=* ]]; then
                    sdk_version="${1#*=}"
                    shift
                else
                    sdk_version="$2"
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
    
    print_info "=========================================="
    print_info "GNB Linux 编译脚本 (主入口)"
    print_info "版本: $version"
    print_info "工作目录: $WORKSPACE_DIR"
    print_info "=========================================="
    
    # ==================== 仅上传模式 ====================
    if [ "$upload_only" = true ]; then
        print_info "仅上传模式，跳过编译"
        
        # 检查是否存在编译产物
        if [ ! -d "$DIST_DIR/$version" ]; then
            print_error "编译产物不存在: $DIST_DIR/$version"
            print_info "请先运行编译命令"
            exit 1
        fi
        
        # 调用上传脚本
        if "$SCRIPT_DIR/upload.sh" "$version"; then
            print_success "=========================================="
            print_success "上传完成！"
            print_success "=========================================="
            exit 0
        else
            print_error "上传失败"
            exit 1
        fi
    fi
    
    # ==================== 编译阶段 ====================
    
    # 判断需要编译的平台
    local has_linux=false
    local has_openwrt=false
    local has_embedded=false
    
    if [ ${#selected_arches[@]} -gt 0 ]; then
        # 检查选择的架构
        for arch in "${selected_arches[@]}"; do
            if [[ "$arch" == linux:* ]]; then
                has_linux=true
            elif [[ "$arch" == openwrt:* ]]; then
                has_openwrt=true
            elif [[ "$arch" == embedded:* ]]; then
                has_embedded=true
            fi
        done
    else
        # 默认编译 Linux 和 OpenWRT 平台
        has_linux=true
        has_openwrt=true
        # embedded 需要显式指定
    fi
    
    local overall_success=true
    
    # 构建参数
    local build_args=("$version")
    
    if [ "$clean" = true ]; then
        build_args+=("--clean")
    fi
    
    # 添加架构参数
    for arch in "${selected_arches[@]}"; do
        build_args+=("--arch" "$arch")
    done
    
    # ==================== 编译 Linux 平台 ====================
    if [ "$has_linux" = true ]; then
        print_info "=========================================="
        print_info "开始编译 Linux 平台 (GNU gcc + 静态链接)"
        print_info "=========================================="
        
        # 过滤 Linux 架构参数
        local linux_args=("$version")
        if [ "$clean" = true ]; then
            linux_args+=("--clean")
        fi
        for arch in "${selected_arches[@]}"; do
            if [[ "$arch" == linux:* ]]; then
                linux_args+=("--arch" "$arch")
            fi
        done
        
        if "$SCRIPT_DIR/build_linux.sh" "${linux_args[@]}"; then
            print_success "Linux 平台编译完成"
        else
            print_error "Linux 平台编译失败"
            overall_success=false
        fi
    fi
    
    # ==================== 编译 OpenWRT 平台 ====================
    if [ "$has_openwrt" = true ]; then
        print_info "=========================================="
        print_info "开始编译 OpenWRT 平台 (SDK 24.10 + musl 静态)"
        print_info "=========================================="
        
        # 过滤 OpenWRT 架构参数
        local openwrt_args=("$version")
        if [ "$clean" = true ]; then
            openwrt_args+=("--clean")
        fi
        if [ -n "$sdk_version" ]; then
            openwrt_args+=("--sdk-version" "$sdk_version")
        fi
        for arch in "${selected_arches[@]}"; do
            if [[ "$arch" == openwrt:* ]]; then
                openwrt_args+=("--arch" "$arch")
            fi
        done
        
        if "$SCRIPT_DIR/build_openwrt.sh" "${openwrt_args[@]}"; then
            print_success "OpenWRT 平台编译完成"
        else
            print_error "OpenWRT 平台编译失败"
            overall_success=false
        fi
    fi
    
    # ==================== 编译嵌入式 musl 平台 ====================
    if [ "$has_embedded" = true ]; then
        print_info "=========================================="
        print_info "开始编译嵌入式 musl 平台 (musl-cross + 静态)"
        print_info "=========================================="
        
        # 过滤嵌入式架构参数
        local embedded_args=("$version")
        if [ "$clean" = true ]; then
            embedded_args+=("--clean")
        fi
        for arch in "${selected_arches[@]}"; do
            if [[ "$arch" == embedded:* ]]; then
                embedded_args+=("--arch" "$arch")
            fi
        done
        
        if "$SCRIPT_DIR/build_embedded_musl.sh" "${embedded_args[@]}"; then
            print_success "嵌入式 musl 平台编译完成"
        else
            print_error "嵌入式 musl 平台编译失败"
            overall_success=false
        fi
    fi
    
    # ==================== 编译完成总结 ====================
    print_info "=========================================="
    if [ "$overall_success" = true ]; then
        print_success "所有平台编译完成！"
    else
        print_warning "部分平台编译失败"
    fi
    print_info "=========================================="
    
    # ==================== 上传阶段 ====================
    if [ "$no_upload" = false ]; then
        print_info "开始上传..."
        
        if "$SCRIPT_DIR/upload.sh" "$version"; then
            print_success "=========================================="
            print_success "所有任务完成！"
            print_success "=========================================="
            exit 0
        else
            print_warning "编译完成，但上传失败"
            print_info "编译产物位于:"
            print_info "  $DIST_DIR/$version"
            exit 1
        fi
    else
        print_success "=========================================="
        print_success "编译完成！"
        print_info "编译产物位于:"
        print_info "  构建: $BUILD_DIR/$version"
        print_info "  发布: $DIST_DIR/$version"
        print_success "=========================================="
        
        if [ "$overall_success" = true ]; then
            exit 0
        else
            exit 1
        fi
    fi
}

# 运行主程序
main "$@"
