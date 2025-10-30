#!/bin/bash
#
# GNB 交叉编译工具链安装脚本
# 支持 OpenWRT SDK、musl、GNU 三种工具链
#

set -e

# 默认配置
INSTALL_DIR="/opt"
OPENWRT_SDK_DIR="$INSTALL_DIR/openwrt-sdk"
MUSL_DIR="$INSTALL_DIR/musl"

# 默认参数
PLATFORM=""
ARCH="all"
OPENWRT_VERSION="24.10"  # 默认使用最新稳定版(推荐)
MUSL_VERSION="latest"
FLOAT_ABI="default"

# 显示帮助信息
show_help() {
    cat << EOF
GNB 交叉编译工具链安装脚本

用法: $0 --platform=<platform> [选项]

必需参数:
  --platform=<platform>    指定工具链平台
                           可选: openwrt, musl, gnu

可选参数:
  --arch=<arch>            指定架构 (默认: all)
                           可选: all, amd64, i386, aarch64, arm, armv7, 
                                 mips, mipsel, mips64, mips64el, riscv64
                           (amd64 也支持别名 x86_64)
  
  --version=<version>      指定版本 (仅 openwrt)
                           默认: 24.10 (推荐最新稳定版)
                           可选: 19.07, 21.02, 22.03, 23.05, 24.10
                           注意: 旧版本仅用于解决特定设备兼容性问题
  
  --float=<float>          浮点 ABI (默认: default)
                           可选: hard, soft, default
                           - hard: 硬件浮点 (hardfp)
                           - soft: 软件浮点 (softfp)
                           - default: 架构默认

工具链选择策略:
  --platform=openwrt    OpenWRT SDK (推荐)
                        • 默认 24.10 通用版: 最新工具链 + 静态编译 + 向下兼容
                        • 精确版本: 用于解决特定设备兼容性问题
                        • 优先级: OpenWRT SDK > musl-cross > 报错
  
  --platform=musl       musl-cross 工具链
                        • 用于非 OpenWRT 的嵌入式设备 (如 UBNT EdgeRouter)
                        • 静态编译，无运行时依赖
  
  --platform=gnu        系统 GNU gcc
                        • 用于标准 Linux 发行版
                        • 动态链接 glibc

示例:
  # 安装 OpenWRT 24.10 通用版 (推荐)
  sudo $0 --platform=openwrt --arch=all

  # 安装 OpenWRT 23.05 精确版 (兼容性问题时使用)
  sudo $0 --platform=openwrt --arch=aarch64 --version=23.05

  # 安装 musl 工具链 (用于 UBNT 等非 OpenWRT 设备)
  sudo $0 --platform=musl --arch=mipsel

  # 安装 GNU 工具链
  sudo $0 --platform=gnu --arch=all

EOF
    exit 0
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo "错误: 请使用 sudo 运行此脚本"
        exit 1
    fi
}

# 检查必需的解压工具
check_dependencies() {
    local missing_tools=()
    
    # 检查基本工具
    if ! command -v wget &> /dev/null; then
        missing_tools+=("wget")
    fi
    
    if ! command -v tar &> /dev/null; then
        missing_tools+=("tar")
    fi
    
    # 检查 zstd (24.10 SDK 需要)
    if [[ "$OPENWRT_VERSION" == 24.10* ]]; then
        if ! command -v zstd &> /dev/null && ! command -v unzstd &> /dev/null; then
            missing_tools+=("zstd")
        fi
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo "错误: 缺少必需工具: ${missing_tools[*]}"
        echo ""
        echo "请先安装:"
        if [[ " ${missing_tools[@]} " =~ " zstd " ]]; then
            echo "  Ubuntu/Debian: sudo apt-get install wget tar zstd"
            echo "  CentOS/RHEL:   sudo yum install wget tar zstd"
            echo "  macOS:         brew install wget zstd"
        else
            echo "  Ubuntu/Debian: sudo apt-get install ${missing_tools[*]}"
            echo "  CentOS/RHEL:   sudo yum install ${missing_tools[*]}"
            echo "  macOS:         brew install ${missing_tools[*]}"
        fi
        exit 1
    fi
}

# 解析逗号分隔的架构列表
parse_arch_list() {
    local arch_input=$1
    if [ "$arch_input" = "all" ]; then
        echo "amd64 i386 aarch64 armv7 mips mipsel mips64 mips64el riscv64"
    else
        echo "$arch_input" | tr ',' ' '
    fi
}

# 获取架构对应的 musl 工具链名称
get_musl_arch_name() {
    local arch=$1
    local float=$2
    
    case "$arch" in
        aarch64|arm64)
            echo "aarch64-linux-musl"
            ;;
        armv7|arm)
            if [ "$float" = "soft" ]; then
                echo "arm-linux-musleabi"
            else
                echo "arm-linux-musleabihf"
            fi
            ;;
        mips)
            if [ "$float" = "soft" ]; then
                echo "mips-linux-muslsf"
            else
                echo "mips-linux-musl"
            fi
            ;;
        mipsel)
            if [ "$float" = "soft" ]; then
                echo "mipsel-linux-muslsf"
            else
                echo "mipsel-linux-musl"
            fi
            ;;
        mips64)
            echo "mips64-linux-musl"
            ;;
        mips64el)
            echo "mips64el-linux-musl"
            ;;
        riscv64)
            echo "riscv64-linux-musl"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 获取架构对应的 GNU 工具链包名
get_gnu_package_name() {
    local arch=$1
    
    case "$arch" in
        aarch64|arm64)
            echo "gcc-aarch64-linux-gnu g++-aarch64-linux-gnu"
            ;;
        armv7|arm)
            echo "gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf gcc-arm-linux-gnueabi g++-arm-linux-gnueabi"
            ;;
        mips)
            echo "gcc-mips-linux-gnu g++-mips-linux-gnu"
            ;;
        mipsel)
            echo "gcc-mipsel-linux-gnu g++-mipsel-linux-gnu"
            ;;
        mips64)
            echo "gcc-mips64-linux-gnuabi64 g++-mips64-linux-gnuabi64"
            ;;
        mips64el)
            echo "gcc-mips64el-linux-gnuabi64 g++-mips64el-linux-gnuabi64"
            ;;
        riscv64)
            echo "gcc-riscv64-linux-gnu g++-riscv64-linux-gnu"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 安装 OpenWRT SDK
install_openwrt_sdk() {
    local version=$1
    local arch_list=$2
    
    echo ""
    echo "==================================="
    echo "安装 OpenWRT SDK ($version)"
    echo "==================================="
    
    mkdir -p "$OPENWRT_SDK_DIR"
    
    # 获取 OpenWRT 版本目标平台映射
    # OpenWRT 主要版本: 19.07, 21.02, 22.03, 23.05, 24.10
    get_openwrt_target_info() {
        local ver=$1
        local arch=$2
        
        # 统一架构别名
        case "$arch" in
            arm64) arch="aarch64" ;;
            arm) arch="armv7" ;;
            x86_64) arch="amd64" ;;
        esac
        
        case "$ver" in
            19.07*)
                local gcc_ver="7.5.0"
                case "$arch" in
                    amd64|x86_64) echo "x86/64|x86-64|musl" ;;
                    i386)    echo "x86/generic|x86-generic|musl" ;;
                    aarch64) echo "armsr/armv8|armsr-armv8|musl" ;;
                    armv7)   echo "bcm27xx/bcm2709|bcm27xx-bcm2709|musl_eabi" ;;
                    mips)    echo "ath79/generic|ath79-generic|musl" ;;
                    mipsel)  echo "ramips/mt7621|ramips-mt7621|musl" ;;
                    *) echo "" ;;
                esac
                ;;
            21.02*)
                local gcc_ver="8.4.0"
                case "$arch" in
                    amd64|x86_64) echo "x86/64|x86-64|musl" ;;
                    i386)    echo "x86/generic|x86-generic|musl" ;;
                    aarch64) echo "armsr/armv8|armsr-armv8|musl" ;;
                    armv7)   echo "bcm27xx/bcm2709|bcm27xx-bcm2709|musl_eabi" ;;
                    mips)    echo "ath79/generic|ath79-generic|musl" ;;
                    mipsel)  echo "ramips/mt7621|ramips-mt7621|musl" ;;
                    *) echo "" ;;
                esac
                ;;
            22.03*)
                local gcc_ver="11.2.0"
                case "$arch" in
                    amd64|x86_64) echo "x86/64|x86-64|musl" ;;
                    i386)    echo "x86/generic|x86-generic|musl" ;;
                    aarch64) echo "armsr/armv8|armsr-armv8|musl" ;;
                    armv7)   echo "bcm27xx/bcm2709|bcm27xx-bcm2709|musl_eabi" ;;
                    mips)    echo "ath79/generic|ath79-generic|musl" ;;
                    mipsel)  echo "ramips/mt7621|ramips-mt7621|musl" ;;
                    *) echo "" ;;
                esac
                ;;
            23.05*)
                local gcc_ver="12.3.0"
                case "$arch" in
                    amd64|x86_64) echo "x86/64|x86-64|musl" ;;
                    i386)    echo "x86/generic|x86-generic|musl" ;;
                    aarch64) echo "armsr/armv8|armsr-armv8|musl" ;;
                    armv7)   echo "bcm27xx/bcm2709|bcm27xx-bcm2709|musl_eabi" ;;
                    mips)    echo "ath79/generic|ath79-generic|musl" ;;
                    mipsel)  echo "ramips/mt7621|ramips-mt7621|musl" ;;
                    *) echo "" ;;
                esac
                ;;
            24.10*)
                local gcc_ver="13.3.0"
                case "$arch" in
                    amd64|x86_64) echo "x86/64|x86-64|musl" ;;
                    i386)    echo "x86/generic|x86-generic|musl" ;;
                    aarch64) echo "armsr/armv8|armsr-armv8|musl" ;;
                    armv7)   echo "bcm27xx/bcm2709|bcm27xx-bcm2709|musl_eabi" ;;
                    mips)    echo "ath79/generic|ath79-generic|musl" ;;
                    mipsel)  echo "ramips/mt7621|ramips-mt7621|musl" ;;
                    *) echo "" ;;
                esac
                ;;
            *)
                echo ""
                ;;
        esac
    } 
    # 自动检测最新小版本号
    detect_latest_subversion() {
        local major_ver=$1
        local target_path=$2
        
        # OpenWRT 通用版策略：默认使用最新稳定版 24.10.0
        # 优点：最新工具链(GCC 13.3.0 + musl 1.2.5) + 静态编译 + 向下兼容
        # 保留精确版本支持，用于解决特定设备的兼容性问题
        case "$major_ver" in
            # 已知稳定版本映射
            19.07) echo "19.07.10" ;;
            21.02) echo "21.02.7" ;;
            22.03) echo "22.03.7" ;;
            23.05) echo "23.05.5" ;;
            24.10) echo "24.10.0" ;;
            *) 
                # 未知版本，尝试动态检测
                local base_url="https://downloads.openwrt.org/releases/${major_ver}/targets/${target_path}"
                local latest=$(wget -qO- "$base_url/" 2>/dev/null | grep -o "openwrt-sdk-${major_ver}\.[0-9][^\"]*\.tar\.xz" | sort -V | tail -1)
                
                if [ -n "$latest" ]; then
                    # 从文件名提取完整版本号
                    echo "$latest" | grep -o "${major_ver}\.[0-9]*" | head -1
                else
                    # 如果检测失败，使用大版本号
                    echo "$major_ver"
                fi
                ;;
        esac
    }
    
    # 构建 SDK 下载 URL
    get_openwrt_sdk_url() {
        local ver=$1
        local arch=$2
        
        local target_info=$(get_openwrt_target_info "$ver" "$arch")
        if [ -z "$target_info" ]; then
            echo ""
            return 1
        fi
        
        IFS='|' read -r target_path target_name libc <<< "$target_info"
        
        # 获取 GCC 版本
        local gcc_ver
        case "$ver" in
            19.07*) gcc_ver="7.5.0" ;;
            21.02*) gcc_ver="8.4.0" ;;
            22.03*) gcc_ver="11.2.0" ;;
            23.05*) gcc_ver="12.3.0" ;;
            24.10*) gcc_ver="13.3.0" ;;
            *) gcc_ver="unknown" ;;
        esac
        
        # 检测最新小版本
        local full_version=$(detect_latest_subversion "$ver" "$target_path")
        
        # 24.10 开始使用 .tar.zst 压缩格式,之前版本使用 .tar.xz
        local extension
        case "$ver" in
            24.10*) extension="tar.zst" ;;
            *) extension="tar.xz" ;;
        esac
        
        local base_url="https://downloads.openwrt.org/releases/${full_version}/targets/${target_path}"
        echo "${base_url}/openwrt-sdk-${full_version}-${target_name}_gcc-${gcc_ver}_${libc}.Linux-x86_64.${extension}"
    }
    
    for arch in $arch_list; do
        local url=$(get_openwrt_sdk_url "$version" "$arch")
        if [ -z "$url" ]; then
            echo "⚠️  OpenWRT SDK $version 暂不支持架构: $arch"
            continue
        fi
        
        local filename=$(basename "$url")
        # 处理不同压缩格式的目录名
        local dirname
        if [[ "$filename" == *.tar.zst ]]; then
            dirname="${filename%.tar.zst}"
        else
            dirname="${filename%.tar.xz}"
        fi
        local install_path="$OPENWRT_SDK_DIR/$version/$dirname"
        
        if [ -d "$install_path" ]; then
            echo "✓ $arch SDK ($version) 已存在: $install_path"
            continue
        fi
        
        echo "下载 $arch SDK ($version)..."
        cd /tmp
        if wget -q --show-progress -O "$filename" "$url"; then
            echo "解压 $filename..."
            mkdir -p "$OPENWRT_SDK_DIR/$version"
            # 根据压缩格式选择解压命令
            if [[ "$filename" == *.tar.zst ]]; then
                tar --use-compress-program=unzstd -xf "$filename" -C "$OPENWRT_SDK_DIR/$version/"
            else
                tar -xJf "$filename" -C "$OPENWRT_SDK_DIR/$version/"
            fi
            rm "$filename"
            echo "✓ $arch SDK 安装完成"
        else
            echo "✗ 下载失败: $arch"
        fi
    done
    
    echo ""
    echo "✓ OpenWRT SDK 安装完成"
    echo "  位置: $OPENWRT_SDK_DIR"
}

# 安装 musl 工具链
install_musl_toolchain() {
    local arch_list=$1
    local float=$2
    
    echo ""
    echo "==================================="
    echo "安装 musl 工具链"
    echo "==================================="
    
    mkdir -p "$MUSL_DIR"
    
    for arch in $arch_list; do
        local musl_arch=$(get_musl_arch_name "$arch" "$float")
        if [ -z "$musl_arch" ]; then
            echo "⚠️  musl 不支持架构: $arch"
            continue
        fi
        
        local url="https://musl.cc/${musl_arch}-cross.tgz"
        local filename="${musl_arch}-cross.tgz"
        
        if [ -d "$MUSL_DIR/${musl_arch}-cross" ]; then
            echo "✓ $musl_arch 已存在"
            continue
        fi
        
        echo "下载 $musl_arch..."
        cd /tmp
        if wget -q --show-progress -O "$filename" "$url"; then
            echo "解压 $filename..."
            tar -xzf "$filename" -C "$MUSL_DIR/"
            rm "$filename"
            echo "✓ $musl_arch 安装完成"
        else
            echo "✗ 下载失败: $musl_arch"
        fi
    done
    
    echo ""
    echo "✓ musl 工具链安装完成"
    echo "  位置: $MUSL_DIR"
}

# 安装 GNU 工具链
install_gnu_toolchain() {
    local arch_list=$1
    
    echo ""
    echo "==================================="
    echo "安装 GNU 工具链"
    echo "==================================="
    
    echo ""
    echo "⚠️  警告: gcc-multilib 与交叉编译器包可能冲突"
    echo ""
    
    read -p "是否继续安装 GNU 工具链？[y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "取消安装"
        return
    fi
    
    # 更新包列表
    echo "更新包列表..."
    apt-get update -qq
    
    # 收集所有要安装的包
    local packages=""
    for arch in $arch_list; do
        local pkg=$(get_gnu_package_name "$arch")
        if [ -n "$pkg" ]; then
            packages="$packages $pkg"
        fi
    done
    
    if [ -z "$packages" ]; then
        echo "没有可安装的包"
        return
    fi
    
    echo "安装交叉编译器: $packages"
    apt-get install -y $packages || true
    
    echo ""
    echo "✓ GNU 工具链安装完成"
}

# 显示安装摘要
show_summary() {
    echo ""
    echo "==================================="
    echo "安装摘要"
    echo "==================================="
    echo ""
    
    # 检查 musl
    if [ -d "$MUSL_DIR" ] && [ "$(ls -A $MUSL_DIR 2>/dev/null)" ]; then
        echo "--- musl 工具链 (位于 $MUSL_DIR) ---"
        for cross_dir in "$MUSL_DIR"/*-cross; do
            if [ -d "$cross_dir/bin" ]; then
                for gcc in "$cross_dir/bin"/*-gcc; do
                    if [ -x "$gcc" ] && [[ ! "$gcc" == *"-c++"* ]]; then
                        local version=$("$gcc" --version 2>/dev/null | head -n1 || echo "")
                        echo "✓ $(basename $gcc): $version"
                        break
                    fi
                done
            fi
        done
    fi
    
    # 检查 OpenWRT SDK
    if [ -d "$OPENWRT_SDK_DIR" ] && [ "$(ls -A $OPENWRT_SDK_DIR 2>/dev/null)" ]; then
        echo ""
        echo "--- OpenWRT SDK (位于 $OPENWRT_SDK_DIR) ---"
        find "$OPENWRT_SDK_DIR" -name "*-openwrt-linux-*gcc" 2>/dev/null | while read gcc; do
            if [ -x "$gcc" ]; then
                echo "✓ $gcc"
            fi
        done | head -5
    fi
    
    # 检查 GNU
    echo ""
    echo "--- 系统 GNU 工具链 ---"
    for gcc_name in "aarch64-linux-gnu-gcc" "arm-linux-gnueabihf-gcc" "mips-linux-gnu-gcc" "mipsel-linux-gnu-gcc" "riscv64-linux-gnu-gcc"; do
        if command -v "$gcc_name" &>/dev/null; then
            local version=$($gcc_name --version 2>/dev/null | head -n1)
            echo "✓ $gcc_name: $version"
        fi
    done
    
    echo ""
    echo "==================================="
    echo "使用提示"
    echo "==================================="
    echo ""
    echo "构建脚本会自动检测并使用合适的工具链:"
    echo "  - OpenWRT 编译: 优先 OpenWRT SDK > musl > 报错"
    echo "  - Linux 编译:   使用 GNU 工具链"
    echo ""
}

# 主函数
main() {
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --platform=*)
                PLATFORM="${1#*=}"
                shift
                ;;
            --arch=*)
                local new_arch="${1#*=}"
                if [ "$ARCH" = "all" ]; then
                    # 第一次指定架构,替换默认值
                    ARCH="$new_arch"
                else
                    # 追加架构
                    ARCH="$ARCH,$new_arch"
                fi
                shift
                ;;
            --version=*)
                OPENWRT_VERSION="${1#*=}"
                shift
                ;;
            --float=*)
                FLOAT_ABI="${1#*=}"
                shift
                ;;
            -h|--help)
                show_help
                ;;
            *)
                echo "错误: 未知参数 '$1'"
                echo "使用 --help 查看帮助"
                exit 1
                ;;
        esac
    done
    
    # 检查必需参数
    if [ -z "$PLATFORM" ]; then
        echo "错误: 必须指定 --platform 参数"
        echo ""
        echo "示例:"
        echo "  sudo $0 --platform=musl --arch=all"
        echo "  sudo $0 --platform=openwrt --arch=aarch64"
        echo "  sudo $0 --platform=gnu --arch=all"
        echo ""
        echo "使用 --help 查看完整帮助"
        exit 1
    fi
    
    # 验证平台
    if [[ ! "$PLATFORM" =~ ^(openwrt|musl|gnu)$ ]]; then
        echo "错误: 不支持的平台 '$PLATFORM'"
        echo "可选: openwrt, musl, gnu"
        exit 1
    fi
    
    check_root
    check_dependencies
    
    # 解析架构列表
    local arch_list=$(parse_arch_list "$ARCH")
    
    echo "==================================="
    echo "GNB 交叉编译工具链安装"
    echo "==================================="
    echo "平台:   $PLATFORM"
    echo "架构:   $arch_list"
    [ "$PLATFORM" = "openwrt" ] && echo "版本:   $OPENWRT_VERSION"
    [ "$FLOAT_ABI" != "default" ] && echo "浮点:   $FLOAT_ABI"
    echo "==================================="
    
    # 安装基础工具
    echo ""
    echo "安装基础工具..."
    apt-get update -qq
    # 24.10 需要 zstd 解压工具
    local extra_tools=""
    [[ "$OPENWRT_VERSION" == 24.10* ]] && extra_tools="zstd"
    apt-get install -y -qq build-essential make tar gzip rsync file wget curl xz-utils $extra_tools
    
    # 根据平台安装
    case "$PLATFORM" in
        openwrt)
            install_openwrt_sdk "$OPENWRT_VERSION" "$arch_list"
            ;;
        musl)
            install_musl_toolchain "$arch_list" "$FLOAT_ABI"
            ;;
        gnu)
            install_gnu_toolchain "$arch_list"
            ;;
    esac
    
    show_summary
}

# 执行主函数
main "$@"
