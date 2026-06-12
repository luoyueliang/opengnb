# mynet_gnb v1.6.5 CI 问题根因分析

## 概述

升级 v1.6.5 时 OpenWrt CI 构建全部失败，经过 4 轮迭代修复后解决。
**所有问题均源自上游 gnbdev/opengnb 的 `Makefile.openwrt` 缺陷，而非我们自己的 CI 配置错误。**

---

## CI 实际编译指令

### 第一步：构建依赖库（zlib / miniupnpc / libnatpmp）

OpenWrt SDK 不包含这三个开发库，`Makefile.openwrt` 用 `-lz -lnatpmp -lminiupnpc` 链接系统库，
但 SDK 中没有。我们从 `src/libs/` bundled sources 构建静态库：

```bash
DEP_LIB="/tmp/dep-libs"
mkdir -p "$DEP_LIB"

# zlib（注意 -DNO_GZIP，避免 crc32 undefined）
for f in adler32 deflate inffast inflate inftrees trees zutil; do
  $CC -c -fPIC -DNO_GZIP -o src/libs/zlib/${f}.o src/libs/zlib/${f}.c
done
$AR_BIN rcs "$DEP_LIB/libz.a" src/libs/zlib/*.o

# miniupnpc
for f in miniwget minixml igd_desc_parse minisoap miniupnpc \
         upnpreplyparse upnpcommands upnperrors connecthostport portlistingparse \
         receivedata upnpdev addr_is_reserved minissdpc; do
  $CC -c -fPIC -o src/libs/miniupnpc/${f}.o src/libs/miniupnpc/${f}.c
done
$AR_BIN rcs "$DEP_LIB/libminiupnpc.a" src/libs/miniupnpc/*.o

# libnatpmp
for f in natpmp getgateway; do
  $CC -c -fPIC -o src/libs/libnatpmp/${f}.o src/libs/libnatpmp/${f}.c
done
$AR_BIN rcs "$DEP_LIB/libnatpmp.a" src/libs/libnatpmp/*.o
```

### 第二步：编译 gnb

通过 make 变量覆盖 `Makefile.openwrt` 的缺陷：

```bash
make -C src -f Makefile.openwrt install \
  CC="$CC" \
  CFLAGS="-ffunction-sections -fdata-sections -I./src -I./libs -I./libs/miniupnpc -I./libs/libnatpmp -I./libs/zlib -DGNB_OPENWRT_BUILD=1 -DNO_GZIP=1 -O2" \
  CLI_LDFLAGS="-Wl,--gc-sections -s -L${DEP_LIB}" \
  GNB_ES_LDFLAGS="-Wl,--gc-sections -s -L${DEP_LIB}" \
  DEBUG=0
```

其中 `CFLAGS` 修复问题 1、3、5；`CLI_LDFLAGS` / `GNB_ES_LDFLAGS` 修复问题 2、4。

---

## 问题一：`ed25519/ed25519.h: No such file or directory`

### 现象
OpenWrt 编译 `gnb_node_worker.c` 时找不到头文件。

### 根因
`Makefile.openwrt` 缺少 CFLAGS 定义：

| 文件 | CFLAGS |
|------|--------|
| `Makefile.linux`（正常） | `CFLAGS=-I./src -I./libs -I./libs/miniupnpc ...` |
| `Makefile.openwrt`（缺陷） | 无初始 CFLAGS，仅有 `CFLAGS += -g`（DEBUG 模式） |

源码中 `#include "ed25519/ed25519.h"` 需要 `-I./libs` 才能找到 `libs/ed25519/ed25519.h`。

### 为什么 Linux 没这个问题
`Makefile.linux` 第一行就定义了完整的 CFLAGS，包含所有必要的 include 路径。

### 对应 CI 修复
CFLAGS 中加入 `-I./src -I./libs`。

---

## 问题二：`cannot find -lz`（zlib）

### 现象
链接 `gnb` 时找不到 `-lz`（zlib 库）。

### 根因
`Makefile.openwrt` 第 42 行硬编码了 `-lz`：
```makefile
$(GNB_CLI): $(GNB_OBJS) $(GNB_CLI_OBJS) $(GNB_PF_OBJS) ${CRYPTO_OBJS}
	${CC} -o ${GNB_CLI} ... -lz ${CLI_LDFLAGS}
```

OpenWrt SDK 不包含 zlib 开发库（只有运行时 .so）。项目 `libs/zlib/` 目录有完整的 zlib 源码，但 `Makefile.openwrt.inc` 没有定义 `ZLIB_OBJS`。

### 为什么 Linux 没这个问题
`Makefile.inc`（Linux 使用）定义了 `ZLIB_OBJS`，将 zlib 编译为 .o 文件直接链接：
```makefile
ZLIB_OBJS = ./libs/zlib/adler32.o ./libs/zlib/deflate.o ...
$(GNB_CLI): ... ${ZLIB_OBJS}  # 直接链接 .o，不依赖系统 libz
```

### 对应 CI 修复
从 bundled sources 构建 `libz.a`，通过 `CLI_LDFLAGS="-L${DEP_LIB}"` 让链接器找到。

---

## 问题三：`undefined reference to crc32`

### 现象
链接 zlib 时 `deflate.c` 中的 `crc32()` 函数未定义。

### 根因
bundled `libs/zlib/` 缺少 `crc32.c` 源文件。`deflate.c` 中的 `crc32()` 调用被 `#ifdef GZIP` 条件编译包裹。

### 为什么 Linux 没这个问题
`Makefile.linux` CFLAGS 包含 `-D NO_GZIP=1`，编译时排除了所有 GZIP/crc32 代码路径。

### 对应 CI 修复
CFLAGS 加入 `-DNO_GZIP=1`，zlib 构建时也加 `-DNO_GZIP`。

---

## 问题四：`cannot find -lnatpmp / -lminiupnpc`

### 现象
链接 `gnb_es` 时找不到 natpmp 和 miniupnpc 库。

### 根因
`Makefile.openwrt` 第 34 行：
```makefile
$(GNB_ES): $(GNB_ES_OBJS) ${CRYPTO_OBJS}
	${CC} -o ${GNB_ES} ... -lnatpmp -lminiupnpc ${GNB_ES_LDFLAGS}
```

与 zlib 同理，SDK 不包含这些开发库。

### 为什么 Linux 没这个问题
`Makefile.inc` 定义了 `MINIUPNP_OBJS` 和 `LIBNATPMP_OBJS`，直接编译 .o 链接：
```makefile
MINIUPNP_OBJS = ./libs/miniupnpc/miniwget.o ./libs/miniupnpc/minixml.o ...
LIBNATPMP_OBJS = ./libs/libnatpmp/natpmp.o ./libs/libnatpmp/getgateway.o ...
$(GNB_ES): ... ${MINIUPNP_OBJS} ${LIBNATPMP_OBJS}  # 直接链接 .o
```

### 对应 CI 修复
从 bundled sources 构建 `libminiupnpc.a` 和 `libnatpmp.a`，通过 `GNB_ES_LDFLAGS="-L${DEP_LIB}"` 链接。

---

## 问题五：`miniupnpc.h: No such file or directory`

### 现象
编译 `gnb_es_upnp.c` 时找不到 `miniupnpc.h`。

### 根因
源码使用 `#include "miniupnpc.h"`（无路径前缀），头文件在 `libs/miniupnpc/` 子目录。
`Makefile.linux` 有 `-I./libs/miniupnpc`，但 `Makefile.openwrt` 没有。

### 为什么 Linux 没这个问题
同问题一，`Makefile.linux` CFLAGS 包含完整的 include 路径。

### 对应 CI 修复
CFLAGS 加入 `-I./libs/miniupnpc -I./libs/libnatpmp -I./libs/zlib`。

---

## 问题总结

| # | 问题 | 来源 | Linux 为何没问题 | CI 修复对应 |
|---|------|------|------------------|-------------|
| 1 | 缺少 CFLAGS include 路径 | 上游 Makefile.openwrt | Makefile.linux 有完整 CFLAGS | CFLAGS 加 `-I./src -I./libs` |
| 2 | 缺少 zlib 链接库 | 上游 Makefile.openwrt 用 -lz 而非 ZLIB_OBJS | Makefile.inc 用 ZLIB_OBJS | 构建 libz.a，`-L${DEP_LIB}` |
| 3 | crc32 undefined | bundled zlib 缺 crc32.c | Makefile.linux 有 -DNO_GZIP=1 | CFLAGS 加 `-DNO_GZIP=1` |
| 4 | 缺少 natpmp/miniupnpc | 上游 Makefile.openwrt 用 -l 而非 _OBJS | Makefile.inc 用 MINIUPNP_OBJS | 构建 .a，`-L${DEP_LIB}` |
| 5 | 缺少子目录 include 路径 | 上游 Makefile.openwrt | Makefile.linux 有 -I./libs/miniupnpc | CFLAGS 加 `-I./libs/miniupnpc` |

**核心结论**：`Makefile.openwrt` 在 v1.6.5 中存在系统性缺陷——
- 缺少 CFLAGS 定义（Makefile.linux 有）
- 用系统库 `-l` 而非 bundled objects（Makefile.inc 用 _OBJS）
- 假设所有依赖库已预装在系统/SDK 中

这些问题在 v1.6.4 中不存在，因为当时使用了不同的 Makefile 结构。
