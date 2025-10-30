#!/bin/bash
#
# GNB 编译系统 - 嵌入式 musl 编译脚本
# 使用 musl-cross 工具链进行静态链接编译
# 目标: 非 OpenWRT 的嵌入式设备 (如 UBNT EdgeRouter, Mikrotik等)
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

# 使用 musl-cross，不使用 SDK
export USE_SDK=false
export SDK_VERSION=""
export SDK_ABI="default"

# ==================== 嵌入式设备架构列表 ====================
# 注意: os 标记为 "embedded" 以区别于 linux 和 openwrt
EMBEDDED_TARGETS=(
    "embedded:amd64:Makefile.linux"
    "embedded:i386:Makefile.linux"
    "embedded:arm64:Makefile.linux"
    "embedded:armv7:Makefile.linux"
    "embedded:armv7-softfp:Makefile.linux"
    "embedded:mips64:Makefile.linux"
    "embedded:mips64el:Makefile.linux"
    "embedded:mips:Makefile.linux"
    "embedded:mips-softfp:Makefile.linux"
    "embedded:mipsel:Makefile.linux"
    "embedded:mipsel-softfp:Makefile.linux"
    "embedded:riscv64:Makefile.linux"
)

# ==================== 显示帮助 ====================

show_help() {
    cat << EOF
GNB 嵌入式 musl 编译脚本 (musl-cross + 静态链接)

使用方法:
    $0 <版本号> [选项]

参数:
    <版本号>        版本号，如 v1.5.3

选项:
    -h, --help              显示此帮助信息
    --arch ARCH             仅编译指定架构 (可多次使用，格式: embedded:arch)
    --clean                 编译前清理输出目录

可用架构:
    - amd64, i386
    - arm64
    - armv7, armv7-softfp
    - mips64, mips64el
    - mips, mips-softfp
    - mipsel, mipsel-softfp (常用于 UBNT EdgeRouter)
    - riscv64

工具链策略:
    使用 musl-cross 工具链 (GCC 11.2.1 + musl 1.2.2)
    - 静态链接 musl libc (无运行时依赖)
    - 适用于非 OpenWRT 的嵌入式 Linux 设备
    - 例如: UBNT EdgeRouter, Mikrotik RouterOS, 自定义嵌入式系统

vs OpenWRT 编译:
    • OpenWRT 设备应使用 build_openwrt.sh (OpenWRT SDK 24.10)
    • 嵌入式设备使用此脚本 (musl-cross)

示例:
    # 编译所有架构
    $0 v1.5.3

    # 只编译 UBNT EdgeRouter (mipsel)
    $0 v1.5.3 --arch embedded:mipsel

    # 编译多个架构
    $0 v1.5.3 --arch embedded:arm64 --arch embedded:mipsel

    # 清理后编译
    $0 v1.5.3 --clean

输出目录:
    临时文件: $BUILD_DIR/<版本号>/embedded/<架构>/
    发布包:   $DIST_DIR/<版本号>/gnb_embedded_<架构>_<版本号>.tar.gz

工具链安装:
    sudo ./install_toolchains.sh --platform=musl --arch=mipsel

EOF
    exit 0
}

# ==================== 参数解析 ====================

VERSION=""
CLEAN=false
SELECTED_ARCHS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        --arch|--arch=*)
            if [[ "$1" == --arch=* ]]; then
                SELECTED_ARCHS+=("${1#*=}")
                shift
            else
                SELECTED_ARCHS+=("$2")
                shift 2
            fi
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        *)
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"
            else
                print_error "未知参数: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# 验证版本号
if [[ -z "$VERSION" ]]; then
    print_error "请指定版本号"
    echo "使用 $0 --help 查看帮助"
    exit 1
fi

# ==================== 编译主流程 ====================

print_info "======================================"
print_info "GNB 嵌入式 musl 编译"
print_info "======================================"
print_info "版本:         $VERSION"
print_info "工具链:       musl-cross"
print_info "链接方式:     静态链接 musl"
print_info "目标平台:     嵌入式 Linux 设备"
print_info "工作空间:     $WORKSPACE_DIR"
print_info "构建目录:     $BUILD_DIR/$VERSION"
print_info "发布目录:     $DIST_DIR/$VERSION"
print_info "======================================"
echo

# 检查依赖
check_dependencies make tar gzip

# 确定要编译的架构
TARGETS_TO_BUILD=()
if [ ${#SELECTED_ARCHS[@]} -gt 0 ]; then
    for target in "${EMBEDDED_TARGETS[@]}"; do
        for selected in "${SELECTED_ARCHS[@]}"; do
            if [[ "$target" == "$selected:"* ]]; then
                TARGETS_TO_BUILD+=("$target")
                break
            fi
        done
    done
    
    if [ ${#TARGETS_TO_BUILD[@]} -eq 0 ]; then
        print_error "未找到匹配的架构"
        exit 1
    fi
    
    print_info "选择编译 ${#TARGETS_TO_BUILD[@]} 个架构"
else
    TARGETS_TO_BUILD=("${EMBEDDED_TARGETS[@]}")
    print_info "编译所有 ${#TARGETS_TO_BUILD[@]} 个架构"
fi

# 清理目录(如果需要)
if [ "$CLEAN" = true ]; then
    print_info "清理构建目录..."
    rm -rf "$BUILD_DIR/$VERSION/embedded"
    rm -rf "$DIST_DIR/$VERSION"
    print_success "清理完成"
    echo
fi

# 编译所有架构
FAILED_BUILDS=()
for target in "${TARGETS_TO_BUILD[@]}"; do
    IFS=':' read -r os arch makefile <<< "$target"
    
    print_info "--------------------------------------------------"
    print_info "编译: $os / $arch"
    print_info "--------------------------------------------------"
    
    # build_arch 参数: (os, arch, makefile, version, workspace_dir, build_dir)
    if build_arch "$os" "$arch" "$makefile" "$VERSION" "$WORKSPACE_DIR" "$BUILD_DIR"; then
        # package_arch 参数: (os, arch, version, build_dir, dist_dir, project)
        if package_arch "$os" "$arch" "$VERSION" "$BUILD_DIR" "$DIST_DIR" "$PROJECT"; then
            print_success "✓ $os/$arch 编译打包成功"
        else
            print_error "✗ $os/$arch 打包失败"
            FAILED_BUILDS+=("$os:$arch:package")
        fi
    else
        print_error "✗ $os/$arch 编译失败"
        FAILED_BUILDS+=("$os:$arch:build")
    fi
    
    # 清理环境变量，防止跨架构污染
    unset CC CXX AR RANLIB STATIC_LINKING ARCH_CFLAGS
    
    echo
done

# ==================== 编译结果汇总 ====================

print_info "======================================"
print_info "嵌入式 musl 编译完成"
print_info "======================================"

if [ ${#FAILED_BUILDS[@]} -eq 0 ]; then
    print_success "所有架构编译成功!"
    print_info "发布包位置: $DIST_DIR/$VERSION/"
    exit 0
else
    print_warning "部分架构编译失败:"
    for failed in "${FAILED_BUILDS[@]}"; do
        IFS=':' read -r os arch stage <<< "$failed"
        echo "  - $os/$arch ($stage)"
    done
    exit 1
fi
