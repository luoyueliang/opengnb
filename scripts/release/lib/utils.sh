#!/bin/bash
#
# GNB 编译系统 - 工具函数库
# 提供通用的输出、错误处理等函数
#

# 标记已加载，避免重复加载
UTILS_LOADED=true

# 打印带颜色的信息
print_info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

# 检查依赖工具
check_dependencies() {
    print_info "检查依赖工具..."
    
    local deps=("gcc" "make" "tar" "strip" "file")
    local missing=0
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_error "缺少依赖工具: $dep"
            missing=1
        fi
    done
    
    if [ $missing -ne 0 ]; then
        print_error "请安装缺失的依赖工具"
        return 1
    fi
    
    print_success "依赖工具检查完成"
    return 0
}

# 生成校验和
generate_checksums() {
    local version=$1
    local dist_dir=$2
    
    print_info "生成校验和文件..."
    
    cd "$dist_dir/$version"
    
    # 生成所有 .tgz 文件的校验和
    if ls *.tgz >/dev/null 2>&1; then
        sha256sum *.tgz > checksums.txt
        print_success "校验和已生成"
        echo "校验和内容:"
        cat checksums.txt
        return 0
    else
        print_warning "没有找到 .tgz 文件"
        return 1
    fi
}
