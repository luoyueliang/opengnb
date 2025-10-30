#!/bin/bash
#
# GNB 编译系统 - OpenWRT 编译脚本
# 使用 OpenWRT SDK 24.10 进行静态链接编译 (musl)
# 目标: OpenWRT 设备 (所有版本,向下兼容)
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

# OpenWRT 配置
# 工具链优先级: OpenWRT SDK (默认 24.10) > musl-cross > 报错
# - 默认使用 OpenWRT SDK 24.10（最新版本，静态链接 musl）
# - 可通过 --sdk-version 指定其他版本（如 23.05, 19.07）
# - 如果 SDK 不存在，自动降级到 musl-cross（静态链接）
export USE_SDK=true  # 默认使用 OpenWRT SDK
export SDK_VERSION="24.10"  # 默认最新稳定版

# ==================== OpenWRT 架构列表 ====================
OPENWRT_TARGETS=(
    "openwrt:amd64:Makefile.openwrt"
    "openwrt:i386:Makefile.openwrt"
    "openwrt:arm64:Makefile.openwrt"
    "openwrt:armv7:Makefile.openwrt"
    "openwrt:armv7-softfp:Makefile.openwrt"
    "openwrt:mips64:Makefile.openwrt"
    "openwrt:mips64el:Makefile.openwrt"
    "openwrt:mips:Makefile.openwrt"
    "openwrt:mips-softfp:Makefile.openwrt"
    "openwrt:mipsel:Makefile.openwrt"
    "openwrt:mipsel-softfp:Makefile.openwrt"
    "openwrt:riscv64:Makefile.openwrt"
)

# ==================== 显示帮助 ====================

show_help() {
    cat << EOF
GNB OpenWRT 编译脚本 (OpenWRT SDK + musl 静态)

使用方法:
    $0 <版本号> [选项]

参数:
    <版本号>        版本号，如 v1.5.3

选项:
    -h, --help                   显示此帮助信息
    --arch ARCH                  仅编译指定架构 (可多次使用，格式: openwrt:arch)
    --arch=ARCH                  同上（等号格式）
    --clean                      编译前清理输出目录
    --sdk-version VERSION        指定 SDK 版本 (默认: 24.10，静态链接)
    --sdk-version=VERSION        同上（等号格式）
                                 可选: 19.07, 21.02, 22.03, 23.05, 24.10
                                 注意: 指定版本将使用动态链接

可用架构:
    - amd64, i386
    - arm64
    - armv7, armv7-softfp
    - mips64, mips64el
    - mips, mips-softfp
    - mipsel, mipsel-softfp
    - riscv64

工具链策略:
    默认使用 OpenWRT SDK 24.10 (GCC 13.3.0 + musl 1.2.5)
    - 静态链接 musl libc (无运行时依赖)
    - 向下兼容 OpenWRT 19.07+ 所有版本
    - 最新编译器优化和 bug 修复
    
    特定版本支持 (解决兼容性问题时使用):
    - --sdk-version=23.05: 针对 OpenWRT 23.05 优化
    - --sdk-version=19.07: 针对 OpenWRT 19.07 优化
    
    工具链降级:
    - 如果指定的 SDK 不存在，自动降级到 musl-cross (静态链接)

示例:
    # 编译所有架构 (使用默认 OpenWRT SDK 24.10，静态链接)
    $0 v1.5.3

    # 使用特定 SDK 版本编译
    $0 v1.5.3 --sdk-version=23.05

    # 只编译特定架构
    $0 v1.5.3 --arch openwrt:arm64 --arch openwrt:mipsel

    # 清理后编译
    $0 v1.5.3 --clean

输出目录:
    临时文件: $BUILD_DIR/<版本号>/openwrt/<架构>/
    发布包:   $DIST_DIR/<版本号>/gnb_openwrt_<架构>_<版本号>.tar.gz

EOF
    exit 0
}

# ==================== 参数解析 ====================

VERSION=""
CLEAN=false
SELECTED_ARCHS=()
CUSTOM_SDK_VERSION=""

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
        --sdk-version|--sdk-version=*)
            if [[ "$1" == --sdk-version=* ]]; then
                CUSTOM_SDK_VERSION="${1#*=}"
                shift
            else
                CUSTOM_SDK_VERSION="$2"
                shift 2
            fi
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

# 如果指定了自定义 SDK 版本，覆盖默认版本
if [[ -n "$CUSTOM_SDK_VERSION" ]]; then
    case "$CUSTOM_SDK_VERSION" in
        19.07|21.02|22.03|23.05|24.10)
            SDK_VERSION="$CUSTOM_SDK_VERSION"
            export SDK_VERSION
            export CUSTOM_SDK_VERSION  # 传递给 toolchain_detection.sh 判断链接方式
            export USE_SDK=true
            print_info "指定使用 OpenWRT SDK $SDK_VERSION (将使用动态链接)"
            ;;
        *)
            print_error "不支持的 SDK 版本: $CUSTOM_SDK_VERSION"
            print_info "支持的版本: 19.07, 21.02, 22.03, 23.05, 24.10"
            exit 1
            ;;
    esac
fi

# 验证版本号
if [[ -z "$VERSION" ]]; then
    print_error "请指定版本号"
    echo "使用 $0 --help 查看帮助"
    exit 1
fi

# ==================== 编译主流程 ====================

print_info "======================================"
print_info "GNB OpenWRT 编译"
print_info "======================================"
print_info "版本:         $VERSION"
if [ -n "$CUSTOM_SDK_VERSION" ]; then
    print_info "SDK 版本:     $SDK_VERSION (用户指定)"
    print_info "链接方式:     动态链接 (针对 OpenWRT $SDK_VERSION)"
else
    print_info "SDK 版本:     $SDK_VERSION (默认)"
    print_info "链接方式:     静态链接 musl (通用，兼容所有版本)"
fi
print_info "工具链:       OpenWRT SDK (优先) → musl-cross (降级)"
print_info "目标平台:     OpenWRT 路由器"
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
    for target in "${OPENWRT_TARGETS[@]}"; do
        for selected in "${SELECTED_ARCHS[@]}"; do
            # 兼容两种格式: "openwrt:arm64" 或 "arm64"
            if [[ "$target" == "$selected:"* ]] || [[ "$target" == "openwrt:${selected}:"* ]]; then
                TARGETS_TO_BUILD+=("$target")
                break
            fi
        done
    done
    
    if [ ${#TARGETS_TO_BUILD[@]} -eq 0 ]; then
        print_error "未找到匹配的架构: ${SELECTED_ARCHS[*]}"
        print_error "可用架构: amd64, i386, arm64, armv7, armv7-softfp, mips, mips-softfp, mipsel, mipsel-softfp, mips64, mips64el, riscv64"
        exit 1
    fi
    
    print_info "选择编译 ${#TARGETS_TO_BUILD[@]} 个架构"
else
    TARGETS_TO_BUILD=("${OPENWRT_TARGETS[@]}")
    print_info "编译所有 ${#TARGETS_TO_BUILD[@]} 个架构"
fi

# 清理目录(如果需要)
if [ "$CLEAN" = true ]; then
    print_info "清理构建目录..."
    rm -rf "$BUILD_DIR/$VERSION/openwrt"
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
    
    if build_arch "$os" "$arch" "$makefile" "$VERSION" "$WORKSPACE_DIR" "$BUILD_DIR"; then
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
    unset CC CXX AR RANLIB STATIC_LINKING STAGING_DIR CUSTOM_SDK_VERSION ARCH_CFLAGS
    
    echo
done

# ==================== 编译结果汇总 ====================

print_info "======================================"
print_info "OpenWRT 编译完成"
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
