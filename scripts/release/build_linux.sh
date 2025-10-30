#!/bin/bash
#
# GNB 编译系统 - Linux 编译脚本
# 使用 GNU gcc 进行静态链接编译
#

set -e

# ==================== 加载配置和依赖库 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载函数库
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/toolchain_detection.sh"
source "$SCRIPT_DIR/lib/build_common.sh"

# 尝试加载 config.env 配置文件
if [ -f "$SCRIPT_DIR/config.env" ]; then
    source "$SCRIPT_DIR/config.env"
fi

# ==================== 配置区域 ====================
PROJECT="gnb"
WORKSPACE_DIR="${WORKSPACE_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$WORKSPACE_DIR/.build}"
DIST_DIR="${DIST_DIR:-$WORKSPACE_DIR/dist}"

# 不使用 SDK
export USE_SDK=false
export SDK_VERSION=""
export SDK_ABI="default"

# ==================== Linux 架构列表 ====================
LINUX_TARGETS=(
    "linux:amd64:Makefile.linux"
    "linux:i386:Makefile.linux"
    "linux:arm64:Makefile.linux"
    "linux:armv7:Makefile.linux"
    "linux:armv7-softfp:Makefile.linux"
    "linux:mips64:Makefile.linux"
    "linux:mips64el:Makefile.linux"
    "linux:mips:Makefile.linux"
    "linux:mips-softfp:Makefile.linux"
    "linux:mipsel:Makefile.linux"
    "linux:mipsel-softfp:Makefile.linux"
    "linux:riscv64:Makefile.linux"
)

# ==================== 显示帮助 ====================

show_help() {
    cat << EOF
GNB Linux 编译脚本 (静态链接)

使用方法:
    $0 <版本号> [选项]

参数:
    <版本号>        版本号，如 v1.5.3

选项:
    -h, --help              显示此帮助信息
    --arch ARCH             仅编译指定架构 (可多次使用，格式: linux:arch)
    --clean                 编译前清理输出目录

可用架构:
    - amd64, i386
    - arm64
    - armv7, armv7-softfp
    - mips64, mips64el
    - mips, mips-softfp
    - mipsel, mipsel-softfp
    - riscv64

示例:
    # 编译所有 Linux 架构
    $0 ver1.6.0.a

    # 仅编译特定架构
    $0 ver1.6.0.a --arch linux:arm64 --arch linux:amd64

    # 编译前清理
    $0 ver1.6.0.a --clean

注意:
    - 此脚本使用 GNU gcc 进行静态链接编译
    - x86 架构使用本地 gcc
    - 其他架构需要安装对应的交叉编译工具链
    - 安装命令示例: sudo apt-get install gcc-aarch64-linux-gnu

EOF
}

# ==================== 主程序 ====================

main() {
    local version=""
    local clean=false
    local selected_arches=()
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
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
    
    # 验证参数
    if [ -z "$version" ]; then
        print_error "请指定版本号"
        show_help
        exit 1
    fi
    
    print_info "=========================================="
    print_info "GNB Linux 编译脚本"
    print_info "版本: $version"
    print_info "工具链: GNU gcc"
    print_info "链接方式: 静态链接"
    print_info "工作目录: $WORKSPACE_DIR"
    print_info "=========================================="
    
    # 检查依赖
    check_dependencies || exit 1
    
    # 清理输出目录
    if [ "$clean" = true ]; then
        print_info "清理输出目录..."
        rm -rf "$BUILD_DIR/$version"
        rm -rf "$DIST_DIR/$version"
    fi
    
    # 确定要编译的架构
    local targets_to_build=()
    if [ ${#selected_arches[@]} -gt 0 ]; then
        for target in "${LINUX_TARGETS[@]}"; do
            local os=$(echo "$target" | cut -d: -f1)
            local arch=$(echo "$target" | cut -d: -f2)
            local target_name="$os:$arch"
            
            for selected in "${selected_arches[@]}"; do
                if [ "$target_name" = "$selected" ]; then
                    targets_to_build+=("$target")
                    break
                fi
            done
        done
    else
        targets_to_build=("${LINUX_TARGETS[@]}")
    fi
    
    if [ ${#targets_to_build[@]} -eq 0 ]; then
        print_error "没有找到匹配的架构"
        exit 1
    fi
    
    print_info "计划编译 ${#targets_to_build[@]} 个架构"
    
    # 编译和打包
    local success_count=0
    local fail_count=0
    
    for target in "${targets_to_build[@]}"; do
        local os=$(echo "$target" | cut -d: -f1)
        local arch=$(echo "$target" | cut -d: -f2)
        local makefile=$(echo "$target" | cut -d: -f3)
        
        print_info "=========================================="
        
        if build_arch "$os" "$arch" "$makefile" "$version" "$WORKSPACE_DIR" "$BUILD_DIR"; then
            if package_arch "$os" "$arch" "$version" "$BUILD_DIR" "$DIST_DIR" "$PROJECT"; then
                ((success_count++))
            else
                ((fail_count++))
            fi
        else
            ((fail_count++))
        fi
        
        # 重置环境变量
        unset CC CXX AR RANLIB STATIC_LINKING ARCH_CFLAGS
    done
    
    print_info "=========================================="
    print_info "编译统计:"
    print_success "  成功: $success_count"
    if [ $fail_count -gt 0 ]; then
        print_error "  失败: $fail_count"
    fi
    print_info "=========================================="
    
    if [ $success_count -eq 0 ]; then
        print_error "所有编译都失败了"
        exit 1
    fi
    
    # 生成校验和
    generate_checksums "$version" "$DIST_DIR" || true
    
    print_success "=========================================="
    print_success "Linux 编译完成！"
    print_info "编译产物位于:"
    print_info "  构建: $BUILD_DIR/$version"
    print_info "  发布: $DIST_DIR/$version"
    print_success "=========================================="
}

# 运行主程序
main "$@"
