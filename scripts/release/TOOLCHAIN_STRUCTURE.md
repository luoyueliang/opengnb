# GNB 工具链目录结构说明

## 目录命名约定

按照 OpenWRT 官方命名规范，使用 **`openwrt-sdk`**（带连字符）作为目录名。

## 三平台共存架构

```
/opt/
├── openwrt-sdk/                    # OpenWRT SDK (官方命名约定)
│   ├── 19.07/                      # 大版本分类
│   │   └── openwrt-sdk-19.07.10-ramips-mt7621_gcc-7.5.0_musl.Linux-x86_64/
│   │       ├── build_dir/          # 编译临时目录
│   │       ├── dl/                 # 下载缓存
│   │       ├── feeds/              # 软件包源
│   │       ├── package/            # 软件包构建脚本
│   │       ├── staging_dir/        # ★ 核心工具链目录
│   │       │   ├── host/           # 主机工具 (x86_64)
│   │       │   │   ├── bin/        # 构建工具
│   │       │   │   └── lib/
│   │       │   ├── target-mipsel_24kc_musl/  # 目标环境 (运行时库)
│   │       │   │   ├── usr/
│   │       │   │   │   ├── include/     # musl libc 头文件
│   │       │   │   │   └── lib/         # musl libc 库文件
│   │       │   │   └── root-ramips/     # rootfs
│   │       │   └── toolchain-mipsel_24kc_gcc-7.5.0_musl/  # ★ 交叉编译工具链
│   │       │       ├── bin/              # GCC 编译器
│   │       │       │   ├── mipsel-openwrt-linux-gcc       # ★ 核心编译器
│   │       │       │   ├── mipsel-openwrt-linux-g++
│   │       │       │   ├── mipsel-openwrt-linux-ar
│   │       │       │   ├── mipsel-openwrt-linux-ld
│   │       │       │   ├── mipsel-openwrt-linux-musl-gcc  # musl 特定
│   │       │       │   └── ...
│   │       │       ├── lib/              # GCC 库
│   │       │       │   └── gcc/mipsel-openwrt-linux-musl/7.5.0/
│   │       │       └── mipsel-openwrt-linux-musl/  # sysroot
│   │       │           ├── include/      # C/C++ 标准头文件
│   │       │           │   ├── c++/7.5.0/         # C++ STL
│   │       │           │   ├── stdio.h            # musl libc
│   │       │           │   └── ...
│   │       │           └── lib/          # musl 运行时库
│   │       │               ├── libc.so            # ★ musl libc (动态)
│   │       │               ├── libc.a             # ★ musl libc (静态)
│   │       │               ├── libgcc_s.so.1      # GCC 运行时
│   │       │               ├── libstdc++.so.6     # C++ 标准库
│   │       │               └── ...
│   │       ├── scripts/            # SDK 脚本
│   │       └── target/             # 目标平台配置
│   │
│   ├── 23.05/                      # LTS 版本 (推荐)
│   │   └── openwrt-sdk-23.05.5-armsr-armv8_gcc-12.3.0_musl.Linux-x86_64/
│   │       └── staging_dir/
│   │           └── toolchain-aarch64_generic_gcc-12.3.0_musl/
│   │               ├── bin/
│   │               │   ├── aarch64-openwrt-linux-gcc          # ★ ARM64 编译器
│   │               │   └── aarch64-openwrt-linux-musl-gcc
│   │               └── aarch64-openwrt-linux-musl/
│   │                   └── lib/
│   │                       ├── libc.so            # musl (ARM64)
│   │                       └── libpthread.so      # musl 线程库
│   │
│   └── 24.10/                      # 最新版本
│       └── openwrt-sdk-24.10.0-ramips-mt7621_gcc-13.3.0_musl.Linux-x86_64/
│
├── musl/                           # 独立 musl 工具链
│   ├── aarch64-linux-musl-cross/   # 纯 musl 交叉编译器
│   │   ├── bin/
│   │   │   ├── aarch64-linux-musl-gcc     # ★ 编译器
│   │   │   └── aarch64-linux-musl-g++
│   │   └── aarch64-linux-musl/
│   │       ├── include/            # musl 头文件
│   │       └── lib/
│   │           ├── libc.a          # ★ 静态链接专用
│   │           └── libc.so
│   ├── arm-linux-musleabihf-cross/ # ARM v7 hard-float
│   ├── mips-linux-musl-cross/
│   └── mipsel-linux-musl-cross/
│
└── (系统目录)
    └── usr/
        ├── bin/
        │   ├── aarch64-linux-gnu-gcc     # ★ GNU 系统工具链
        │   ├── arm-linux-gnueabihf-gcc
        │   └── mipsel-linux-gnu-gcc
        └── lib/x86_64-linux-gnu/
            └── libgcc_s.so.1
```

## OpenWRT SDK 核心特性

### 1. SDK 内部是 GCC + musl 的组合

**OpenWRT SDK 自带完整的 musl 工具链**，不依赖系统 glibc：

```
staging_dir/toolchain-<arch>_gcc-<version>_musl/
├── bin/
│   ├── <target>-openwrt-linux-gcc       # 编译器入口
│   └── <target>-openwrt-linux-musl-gcc  # 明确指定 musl
├── lib/gcc/<target>-musl/<gcc-version>/ # GCC 库
└── <target>-musl/
    ├── include/                         # musl 头文件
    └── lib/
        ├── libc.so                      # ★ musl C 库 (动态)
        ├── libc.a                       # ★ musl C 库 (静态)
        ├── libpthread.so                # 线程库 (musl 内置)
        ├── libm.so                      # 数学库 (musl 内置)
        └── libgcc_s.so.1                # GCC 运行时
```

### 2. 三种 C 库的区别

| 特性 | glibc | musl | uclibc |
|------|-------|------|--------|
| **目标** | 通用桌面/服务器 | 嵌入式/静态链接 | 旧式嵌入式 |
| **大小** | ~2.5 MB | ~600 KB | ~1 MB |
| **性能** | 高 | 中高 | 中 |
| **兼容性** | 最广 | 较好 | 一般 |
| **静态链接** | 不推荐 | ★ 优秀 | 较好 |
| **OpenWRT** | ✗ 不用 | ★ 默认 | 旧版本用 |

### 3. 工具链对比

| 工具链 | GCC 版本 | C 库 | 用途 | 静态链接 |
|--------|---------|------|------|---------|
| **OpenWRT SDK** | 版本相关 | musl | OpenWRT 固件 | ✓ 优秀 |
| **独立 musl** | 最新 | musl | 通用静态编译 | ✓ 最佳 |
| **GNU 系统工具链** | 系统版本 | glibc | Linux 发行版 | ✗ 不推荐 |

### 4. 小版本检测策略

脚本使用**自动检测最新小版本**策略：

```bash
# 用户指定: --version=23.05
# 脚本行为:
1. 访问 https://downloads.openwrt.org/releases/23.05/targets/<target>/
2. 解析目录列表，查找 openwrt-sdk-23.05.*-xxx.tar.xz
3. 按版本号排序，选择最新 (如 23.05.5)
4. 下载并安装到 /opt/openwrt-sdk/23.05/openwrt-sdk-23.05.5-xxx/
```

**优势**：
- 用户只需关心大版本 (23.05)
- 自动获取最新安全更新和修复
- 多次安装同一大版本时，自动跳过已存在的目录

### 5. 编译时库的选择

#### OpenWRT 编译：
```bash
# SDK 工具链自带 musl，无需额外指定
$ aarch64-openwrt-linux-gcc main.c -o gnb
# 动态链接: ldd gnb
#   libc.so => /lib/ld-musl-aarch64.so.1

$ aarch64-openwrt-linux-gcc main.c -o gnb -static
# 静态链接: 包含完整 musl libc (约 600KB)
```

#### 独立 musl 编译：
```bash
# 专为静态链接优化
$ aarch64-linux-musl-gcc main.c -o gnb -static
# 生成纯静态二进制，无任何依赖
```

#### GNU glibc 编译：
```bash
# 系统工具链
$ aarch64-linux-gnu-gcc main.c -o gnb
# 动态链接: ldd gnb
#   libc.so.6 => /lib/aarch64-linux-gnu/libc.so.6 (glibc 2.31)

$ aarch64-linux-gnu-gcc main.c -o gnb -static
# ⚠️ 不推荐! glibc 静态链接体积大且可能有兼容性问题
```

## OpenWRT 主要版本

按照大版本分类，支持以下主要版本：

| 版本号 | 发布时间 | GCC 版本 | musl 版本 | 状态 |
|--------|---------|---------|----------|------|
| 19.07  | 2020-01 | 7.5.0   | 1.1.24   | 旧版本 |
| 21.02  | 2021-02 | 8.4.0   | 1.2.2    | 稳定版 |
| 22.03  | 2022-03 | 11.2.0  | 1.2.3    | 稳定版 |
| 23.05  | 2023-05 | 12.3.0  | 1.2.4    | LTS (推荐) |
| 24.10  | 2024-10 | 13.3.0  | 1.2.5    | 最新版 |

### 版本命名规则

- 小版本号（如 23.05.2, 23.05.5）统一归类到大版本目录（23.05/）
- SDK 文件名保留完整版本号
- 目录结构按大版本分类，便于管理和升级

## 工具链优先级

### OpenWRT 编译
1. OpenWRT SDK（首选，版本匹配）
2. musl 工具链（备选）
3. 不使用 GNU（避免兼容性问题）

### Linux 编译
1. GNU 系统工具链（系统 APT 管理）
2. 不使用 musl 或 OpenWRT SDK

## 安装示例

```bash
# 安装 OpenWRT SDK 23.05 (LTS)
sudo ./install_toolchains.sh --platform=openwrt --arch=aarch64,mipsel --version=23.05

# 安装 OpenWRT SDK 19.07 (旧版本)
sudo ./install_toolchains.sh --platform=openwrt --arch=mipsel --version=19.07

# 安装 musl 工具链
sudo ./install_toolchains.sh --platform=musl --arch=all

# 安装 GNU 工具链
sudo ./install_toolchains.sh --platform=gnu --arch=aarch64,armv7
```

## 向后兼容

`build_and_upload.sh` 同时支持新旧目录名：
- `/opt/openwrt-sdk/` (新，推荐)
- `/opt/openwrt_sdk/` (旧，兼容)

如果系统中同时存在两个目录，优先使用新目录。
