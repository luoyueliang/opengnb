#!/bin/bash
#
# GNB 编译系统 - Makefile 变量打印工具
# 用途：打印 Makefile 中的编译参数，便于调试和验证
#
# 使用方法：
#   ./print_makefile_vars.sh <workspace_src> <makefile> [--eval='...'] [--eval='...']
#
# 参数：
#   workspace_src: Makefile 所在目录（通常是 src/）
#   makefile:      要使用的 Makefile 文件名
#   --eval:        可选的 make --eval 参数（可多个）
#
# 注意：
#   - 此脚本会继承父进程的环境变量（CC, CFLAGS, ARCH_CFLAGS 等）
#   - 通过 make --eval 创建临时打印目标，不修改原始 Makefile
#

if [ $# -lt 2 ]; then
    echo "用法: $0 <workspace_src> <makefile> [--eval='...']" >&2
    exit 1
fi

workspace_src="$1"
makefile="$2"
shift 2  # 移除前两个参数，剩下的是 --eval 参数

if [ ! -d "$workspace_src" ]; then
    echo "错误: 目录不存在: $workspace_src" >&2
    exit 1
fi

if [ ! -f "$workspace_src/$makefile" ]; then
    echo "错误: Makefile 不存在: $workspace_src/$makefile" >&2
    exit 1
fi

echo ""
echo "=========================================="
echo "Makefile 编译参数详情"
echo "=========================================="

# 使用 make 的 --eval 创建临时打印目标
# 关键：通过命令行参数传递当前环境变量给 make
# $@ 包含所有传入的 --eval 参数（已包含 CFLAGS 和 LDFLAGS 的追加）
make -C "$workspace_src" -f "$makefile" \
    "$@" \
    CC="${CC:-cc}" \
    ${CXX:+CXX="$CXX"} \
    ${AR:+AR="$AR"} \
    ${RANLIB:+RANLIB="$RANLIB"} \
    --no-print-directory \
    --eval='
.PHONY: __gnb_print_vars__
__gnb_print_vars__:
	@echo "CC:              $(CC)"
	@echo "CXX:             $(CXX)"
	@echo "AR:              $(AR)"
	@echo "RANLIB:          $(RANLIB)"
	@echo "CFLAGS:          $(CFLAGS)"
	@echo "CLI_LDFLAGS:     $(CLI_LDFLAGS)"
	@echo "GNB_ES_LDFLAGS:  $(GNB_ES_LDFLAGS)"
' \
    __gnb_print_vars__ 2>/dev/null

echo "=========================================="
echo ""
