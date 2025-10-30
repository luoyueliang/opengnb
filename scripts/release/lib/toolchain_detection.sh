#!/bin/bash
#
# GNB 编译系统 - 工具链检测函数库
# 提供 musl、OpenWRT SDK、GNU 工具链的检测和配置
#

# 需要先加载 utils.sh
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$UTILS_LOADED" ]; then
    source "$LIB_DIR/utils.sh"
fi

# ==================== 工具链检测函数 ====================

# 检测 musl 工具链
find_musl_gcc() {
    local target_arch=$1
    local musl_dirs=(
        "/opt/musl"
        "/opt/musl-cross"
        "/usr/local/musl"
    )
    
    for musl_dir in "${musl_dirs[@]}"; do
        if [ -d "$musl_dir" ]; then
            local gcc_path="$musl_dir/${target_arch}-cross/bin/${target_arch}-gcc"
            if [ -x "$gcc_path" ]; then
                echo "$gcc_path"
                return 0
            fi
        fi
    done
    
    # 也检查 PATH 中的命令
    if command -v "${target_arch}-gcc" &>/dev/null; then
        echo "${target_arch}-gcc"
        return 0
    fi
    
    return 1
}

# 检测 OpenWRT SDK 工具链（指定版本）
find_openwrt_sdk_gcc() {
    local target_arch=$1
    local sdk_version=$2
    
    # 如果指定了版本，只在特定版本目录查找
    if [ -n "$sdk_version" ]; then
        local sdk_dirs=(
            "/opt/openwrt-sdk/${sdk_version}/openwrt-sdk-*"
        )
    else
        local sdk_dirs=(
            "/opt/openwrt-sdk/*/openwrt-sdk-*"
            "/opt/openwrt_sdk/openwrt-sdk-*"
        )
    fi
    
    for sdk_pattern in "${sdk_dirs[@]}"; do
        for sdk in $sdk_pattern; do
            [ -d "$sdk/staging_dir" ] || continue
            
            for toolchain_dir in "$sdk/staging_dir"/toolchain-*; do
                [ -d "$toolchain_dir/bin" ] || continue
                
                # 根据架构查找对应的 gcc
                case "$target_arch" in
                    arm64|aarch64)
                        for gcc in "$toolchain_dir/bin"/*-openwrt-linux-*gcc; do
                            if [ -x "$gcc" ] && [[ "$gcc" == *"aarch64"* ]]; then
                                echo "$gcc"
                                return 0
                            fi
                        done
                        ;;
                    armv7|arm)
                        for gcc in "$toolchain_dir/bin"/*-openwrt-linux-*gcc; do
                            if [ -x "$gcc" ] && [[ "$gcc" == *"arm"* ]] && [[ "$gcc" != *"aarch64"* ]]; then
                                echo "$gcc"
                                return 0
                            fi
                        done
                        ;;
                    mips|mipsel|mips64|mips64el)
                        for gcc in "$toolchain_dir/bin"/*-openwrt-linux-*gcc; do
                            if [ -x "$gcc" ] && [[ "$gcc" == *"$target_arch"* ]]; then
                                echo "$gcc"
                                return 0
                            fi
                        done
                        ;;
                    riscv64)
                        for gcc in "$toolchain_dir/bin"/*-openwrt-linux-*gcc; do
                            if [ -x "$gcc" ] && [[ "$gcc" == *"riscv64"* ]]; then
                                echo "$gcc"
                                return 0
                            fi
                        done
                        ;;
                esac
            done
        done
    done
    return 1
}

# 检测 GNU 系统工具链
find_gnu_gcc() {
    local target_arch=$1
    if command -v "${target_arch}" &>/dev/null; then
        echo "${target_arch}"
        return 0
    fi
    return 1
}

# ==================== 通用架构工具链配置 ====================
# 根据平台和架构自动选择工具链
setup_arch_toolchain() {
    local arch=$1
    local musl_target=$2
    local gnu_target=$3
    local sdk_arch=$4  # OpenWRT SDK 架构名
    local is_openwrt=$5  # 是否为 OpenWRT 平台
    local use_sdk=${USE_SDK:-false}  # 是否强制使用 SDK
    local sdk_version=${SDK_VERSION:-}  # SDK 版本
    
    if [ "$is_openwrt" = true ]; then
        # OpenWRT 平台编译 - 优先级：OpenWRT SDK > musl-cross
        if [ "$use_sdk" = true ]; then
            # 优先使用 OpenWRT SDK
            sdk_gcc=$(find_openwrt_sdk_gcc "$sdk_arch" "$sdk_version")
            if [ -n "$sdk_gcc" ]; then
                export CC="$sdk_gcc"
                
                # 根据是否用户指定版本号决定链接方式
                # CUSTOM_SDK_VERSION 为空表示使用默认版本
                if [ -n "${CUSTOM_SDK_VERSION:-}" ]; then
                    # 用户指定版本号 → 动态链接（针对特定 OpenWRT 版本）
                    export STATIC_LINKING=false
                    print_info "使用 OpenWRT SDK $sdk_version (动态链接，针对版本): $CC"
                else
                    # 默认版本 → 静态链接（通用版本，兼容所有 OpenWRT）
                    export STATIC_LINKING=true
                    print_info "使用 OpenWRT SDK $sdk_version (静态链接 musl，通用版本): $CC"
                fi
                
                # 设置 STAGING_DIR 以消除 OpenWRT SDK 的警告
                local sdk_base_dir=$(dirname $(dirname $(dirname "$sdk_gcc")))
                export STAGING_DIR="$sdk_base_dir/staging_dir"
                
                print_info "STAGING_DIR: $STAGING_DIR"
                return 0
            else
                print_error "未找到 OpenWRT SDK $sdk_version 的 $arch 工具链"
                print_info ""
                print_info "请安装 OpenWRT SDK 工具链："
                print_info "  sudo ./scripts/release/install_toolchains.sh --platform=openwrt --arch=$arch --version=$sdk_version"
                print_info ""
                print_info "或者使用嵌入式平台编译（musl-cross）："
                print_info "  ./scripts/release/build_and_upload.sh --arch embedded:$arch <版本号>"
                return 1
            fi
        fi
        
        # 不应该到这里
        print_error "OpenWRT 平台必须使用 OpenWRT SDK"
        print_info "请安装 OpenWRT SDK: sudo ./scripts/release/install_toolchains.sh --platform=openwrt --arch=$arch --version=$sdk_version"
        return 1
    else
        # Linux 平台编译：GNU + 静态链接
        gnu_gcc=$(find_gnu_gcc "$gnu_target")
        if [ -n "$gnu_gcc" ]; then
            export CC="$gnu_gcc"
            export STATIC_LINKING=true  # 静态链接
            print_info "使用 GNU 工具链 (静态链接): $CC"
            return 0
        else
            print_error "未找到 GNU $gnu_target 工具链"
            print_info "请安装: sudo apt-get install gcc-${gnu_target%-gcc}"
            return 1
        fi
    fi
}

# ==================== 架构工具链配置主函数 ====================
# 根据架构设置对应的工具链和编译参数
setup_toolchain() {
    local arch=$1
    local os=$2  # OS 参数: linux 或 openwrt
    
    print_info "设置工具链: $arch (OS: ${os:-linux})"
    
    # 清理所有编译相关的环境变量，避免循环编译时前一个架构的设置污染后一个架构
    # CFLAGS 和 LDFLAGS 也需要清空，让 Makefile 使用自己定义的默认值
    # 清理环境变量，确保每次架构编译独立
    unset CC CXX AR RANLIB STATIC_LINKING ARCH_CFLAGS
    
    # 判断是否为 OpenWRT 编译
    local is_openwrt=false
    if [ "$os" = "openwrt" ]; then
        is_openwrt=true
    fi
    
    case "$arch" in
        amd64)
            # x86_64 架构使用本地 gcc
            export CC=gcc
            export STATIC_LINKING=true
            print_info "使用本地 gcc (x86_64)"
            ;;
            
        i386)
            # i386 架构使用本地 gcc -m32
            export CC=gcc
            export STATIC_LINKING=true
            export ARCH_CFLAGS="-m32"
            
            # 检查32位编译支持
            if ! gcc -m32 -E - </dev/null >/dev/null 2>&1; then
                print_error "未找到32位编译支持"
                print_info "请安装32位开发库:"
                print_info "  sudo apt-get install gcc-multilib g++-multilib libc6-dev-i386"
                return 1
            fi
            print_info "使用本地 gcc -m32 (i386)"
            ;;
            
        arm64)
            setup_arch_toolchain "arm64" "aarch64-linux-musl" "aarch64-linux-gnu-gcc" "aarch64" "$is_openwrt" || return 1
            ;;
            
        armv7|armv7-softfp)
            # 判断 float ABI
            local is_softfp=false
            local musl_target="arm-linux-musleabihf"
            local gnu_target="arm-linux-gnueabihf-gcc"
            
            if [[ "$arch" == *"softfp"* ]]; then
                is_softfp=true
                musl_target="arm-linux-musleabi"
                gnu_target="arm-linux-gnueabi-gcc"
            fi
            
            setup_arch_toolchain "armv7" "$musl_target" "$gnu_target" "arm" "$is_openwrt" || return 1
            
            # 设置 ABI 编译参数（CFLAGS 包含链接时需要的 ABI 标志）
            if [ "$is_softfp" = true ]; then
                export ARCH_CFLAGS="-march=armv7-a -mfloat-abi=soft"
            else
                export ARCH_CFLAGS="-march=armv7-a -mfloat-abi=hard -mfpu=vfpv3-d16"
            fi
            ;;
            
        mips|mips-softfp)
            # 判断 float ABI
            local is_softfp=false
            local musl_target="mips-linux-musl"
            local gnu_target="mips-linux-gnu-gcc"
            
            if [[ "$arch" == *"softfp"* ]]; then
                is_softfp=true
                musl_target="mips-linux-muslsf"  # soft-float variant
            fi
            
            setup_arch_toolchain "mips" "$musl_target" "$gnu_target" "mips" "$is_openwrt" || return 1
            
            # 设置 soft-float 参数
            if [ "$is_softfp" = true ]; then
                export ARCH_CFLAGS="-msoft-float"
            fi
            ;;
            
        mipsel|mipsel-softfp)
            # 判断 float ABI
            local is_softfp=false
            local musl_target="mipsel-linux-musl"
            local gnu_target="mipsel-linux-gnu-gcc"
            
            if [[ "$arch" == *"softfp"* ]]; then
                is_softfp=true
                musl_target="mipsel-linux-muslsf"
            fi
            
            setup_arch_toolchain "mipsel" "$musl_target" "$gnu_target" "mipsel" "$is_openwrt" || return 1
            
            # 设置 soft-float 参数
            if [ "$is_softfp" = true ]; then
                export ARCH_CFLAGS="-msoft-float"
            fi
            ;;
            
        mips64)
            setup_arch_toolchain "mips64" "mips64-linux-musl" "mips64-linux-gnuabi64-gcc" "mips64" "$is_openwrt" || return 1
            ;;
            
        mips64el)
            setup_arch_toolchain "mips64el" "mips64el-linux-musl" "mips64el-linux-gnuabi64-gcc" "mips64el" "$is_openwrt" || return 1
            ;;
            
        riscv64)
            setup_arch_toolchain "riscv64" "riscv64-linux-musl" "riscv64-linux-gnu-gcc" "riscv64" "$is_openwrt" || return 1
            ;;
            
        *)
            print_error "不支持的架构: $arch"
            return 1
            ;;
    esac
    
    print_success "工具链设置完成: $CC"
    return 0
}
