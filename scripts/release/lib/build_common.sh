#!/bin/bash
#
# GNB 编译系统 - 通用编译函数库
# 提供编译、打包等通用功能
#

# 需要先加载依赖库
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$UTILS_LOADED" ]; then
    source "$LIB_DIR/utils.sh"
fi
source "$LIB_DIR/toolchain_detection.sh"

# ==================== 编译函数 ====================

# 编译指定架构
build_arch() {
    local os=$1
    local arch=$2
    local makefile=$3
    local version=$4
    local workspace_dir=$5
    local build_dir=$6
    
    print_info "开始编译: $os/$arch"
    
    # 设置工具链，传递 OS 参数以便判断是否为 OpenWRT
    if ! setup_toolchain "$arch" "$os"; then
        print_error "工具链设置失败，跳过 $os/$arch"
        return 1
    fi
    
    local out_dir="$build_dir/$version/$os/$arch/bin"
    mkdir -p "$out_dir"
    
    # 清理
    print_info "清理编译目录..."
    make -C "$workspace_dir/src" -f "$makefile" clean || true
    
    # ==================== 生成临时 Makefile（如果需要） ====================
    # 策略：最简单最安全
    # 1. DEBUG=0 传给 make（让 ifeq 块追加 -s）
    # 2. 静态链接时：sed 在 LDFLAGS 头部定义追加 -static
    # 3. 架构特定 CFLAGS：通过 sed 追加到 Makefile 的 CFLAGS 定义
    local actual_makefile="$makefile"
    local temp_makefile_path=""
    local need_temp_makefile=false
    
    # 检查是否需要临时 Makefile
    if [ "${STATIC_LINKING:-false}" = "true" ] || [ -n "${ARCH_CFLAGS:-}" ]; then
        need_temp_makefile=true
    fi
    
    if [ "$need_temp_makefile" = "true" ]; then
        print_info "生成临时 Makefile..."
        local temp_makefile="${makefile}.tmp.$$"
        temp_makefile_path="$workspace_dir/src/$temp_makefile"
        
        local sed_commands=()
        
        # 1. 静态链接：在 LDFLAGS 头部定义追加 -static
        if [ "${STATIC_LINKING:-false}" = "true" ]; then
            sed_commands+=(-e "s|^\(CLI_LDFLAGS=.*\)$|\1 -static|")
            sed_commands+=(-e "s|^\(GNB_ES_LDFLAGS=.*\)$|\1 -static|")
            print_info "  → 静态链接：追加 -static"
        fi
        
        # 2. 架构特定 CFLAGS：追加到 CFLAGS 头部定义
        if [ -n "${ARCH_CFLAGS:-}" ]; then
            sed_commands+=(-e "s|^\(CFLAGS=.*\)$|\1 ${ARCH_CFLAGS}|")
            print_info "  → 架构特定编译标志：${ARCH_CFLAGS}"
        fi
        
        # 执行 sed
        sed "${sed_commands[@]}" "$workspace_dir/src/$makefile" > "$temp_makefile_path"
        
        actual_makefile="$temp_makefile"
        print_success "临时 Makefile 已生成: $temp_makefile"
    else
        print_info "使用原始 Makefile（动态链接）"
    fi
    
    # ==================== 打印编译环境和参数 ====================
    echo ""
    echo "=========================================="
    echo "编译环境信息"
    echo "=========================================="
    echo "OS/ARCH:          $os/$arch"
    echo "原始 Makefile:    $makefile"
    echo "临时 Makefile:    $actual_makefile (删除 ifeq 块，追加 $ldflags_append)"
    echo "工作目录:         $workspace_dir/src"
    echo "输出目录:         $out_dir"
    echo ""
    echo "【环境变量 - 传递给 Make】"
    echo "CC:               ${CC:-未设置}"
    echo "CXX:              ${CXX:-未设置}"
    echo "AR:               ${AR:-未设置}"
    echo "RANLIB:           ${RANLIB:-未设置}"
    echo "DEBUG:            0 (固定值，让 Makefile 追加 -s)"
    echo "STATIC_LINKING:   ${STATIC_LINKING:-false}"
    echo "STAGING_DIR:      ${STAGING_DIR:-(未设置)}"
    echo ""
    echo "【临时 Makefile 修改】"
    if [ "${STATIC_LINKING:-false}" = "true" ]; then
        echo "  - LDFLAGS 追加 -static"
    fi
    if [ -n "${ARCH_CFLAGS:-}" ]; then
        echo "  - CFLAGS 追加架构标志: ${ARCH_CFLAGS}"
    fi
    if [ "$need_temp_makefile" = "false" ]; then
        echo "  - 无修改，使用原始 Makefile"
    fi
    echo "=========================================="
    echo ""
    
    # 调用独立脚本打印 Makefile 内部变量（显示最终值）
    print_info "调用参数打印脚本（显示 Makefile 最终变量值）..."
    "$LIB_DIR/print_makefile_vars.sh" "$workspace_dir/src" "$actual_makefile" || true
    
    # ==================== 开始编译 ====================
    print_info "开始编译..."
    
    # DEBUG=0：让 Makefile 的 ifeq 块走 else 分支（追加 -s）
    # 临时 Makefile 已处理：静态链接 -static + 架构 CFLAGS
    local make_result=0
    if ! make -C "$workspace_dir/src" -f "$actual_makefile" \
        CC="$CC" \
        DEBUG=0 \
        install; then
        make_result=1
    fi
    
    # 清理临时 Makefile
    rm -f "$temp_makefile_path"
    print_info "已清理临时 Makefile"
    
    # 检查编译结果
    if [ $make_result -ne 0 ]; then
        print_error "编译失败: $os/$arch"
        return 1
    fi
    
    # 移动二进制文件
    if [ -d "$workspace_dir/src/bin" ]; then
        mv "$workspace_dir/src/bin"/* "$out_dir/" 2>/dev/null || true
    elif [ -d "$workspace_dir/bin" ]; then
        mv "$workspace_dir/bin"/* "$out_dir/" 2>/dev/null || true
    fi
    
    # 验证二进制文件
    print_info "验证二进制文件..."
    local missing=0
    for binary in gnb_ctl gnb_es gnb_crypto gnb; do
        if [ -f "$out_dir/$binary" ]; then
            local info=$(file -b "$out_dir/$binary")
            local size=$(stat -c%s "$out_dir/$binary" 2>/dev/null || stat -f%z "$out_dir/$binary" 2>/dev/null || echo "unknown")
            print_info "  $binary: $info (大小: $size 字节)"
            
            # Strip 二进制文件
            strip "$out_dir/$binary" 2>/dev/null || true
            local new_size=$(stat -c%s "$out_dir/$binary" 2>/dev/null || stat -f%z "$out_dir/$binary" 2>/dev/null || echo "unknown")
            print_info "  Strip 后大小: $new_size 字节"
            
            # 验证链接类型
            if [ "${STATIC_LINKING:-false}" = "true" ]; then
                if echo "$info" | grep -qi "statically linked\|static-pie linked"; then
                    print_success "  ✓ $binary 是静态链接"
                else
                    print_error "  ✗ $binary 不是静态链接"
                    missing=1
                fi
            fi
        else
            print_error "  ✗ 未找到二进制文件: $binary"
            missing=1
        fi
    done
    
    if [ $missing -ne 0 ]; then
        print_error "编译验证失败: $os/$arch"
        return 1
    fi
    
    print_success "编译完成: $os/$arch"
    return 0
}

# ==================== 打包函数 ====================

# 打包指定架构
package_arch() {
    local os=$1
    local arch=$2
    local version=$3
    local build_dir=$4
    local dist_dir=$5
    local project=${6:-gnb}
    
    print_info "打包: $os/$arch"
    
    local out_parent="$build_dir/$version/$os/$arch"
    local pkg_dir="$dist_dir/$version"  # 直接放在版本目录下，不分 linux/openwrt 子目录
    local archive="${project}_${os}_${arch}_${version}.tgz"  # 使用 .tgz 扩展名
    
    mkdir -p "$pkg_dir"
    
    if [ ! -d "$out_parent/bin" ]; then
        print_error "输出目录不存在: $out_parent/bin"
        return 1
    fi
    
    tar -czvf "$pkg_dir/$archive" -C "$out_parent" bin
    
    if [ -f "$pkg_dir/$archive" ]; then
        print_success "打包完成: $archive"
        return 0
    else
        print_error "打包失败: $os/$arch"
        return 1
    fi
}
