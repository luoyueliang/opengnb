# GNB 编译快速参考

## 核心特性

1. ✅ **OpenWRT 24.10 通用版**：最新工具链 + 静态链接 + 向下兼容所有版本
2. ✅ **精确版本支持**：解决特定设备兼容性问题时使用
3. ✅ **统一参数格式**：支持 `--param value` 和 `--param=value` 两种格式

## 工具链选择策略

| 平台 | 推荐工具链 | 使用场景 | 链接方式 |
|------|-----------|---------|---------|
| **OpenWRT** | OpenWRT 24.10 SDK | 所有 OpenWRT 路由器 | **静态链接** musl（通用） |
| **OpenWRT** | OpenWRT SDK 指定版本 | 特定版本兼容性问题 | **动态链接**（针对版本） |
| **Linux** | GNU gcc + glibc | 标准 Linux 发行版 | 静态链接 glibc |
| **嵌入式** | musl-cross | 自定义嵌入式系统 | 静态链接 musl |

**OpenWRT 编译逻辑**：
```
1. 默认（无 --sdk-version）：使用 OpenWRT SDK 24.10 → 静态链接 musl → 通用版本
2. 指定版本（--sdk-version=XX.XX）：使用对应 SDK → 动态链接 → 针对特定版本
3. SDK 不存在：降级到 musl-cross → 静态链接 musl
```

**何时使用指定版本**：
- ❌ 默认情况：不需要指定，24.10 静态版本可在所有 OpenWRT 版本运行
- ✅ 特殊情况：遇到特定设备崩溃/兼容性问题时，使用 `--sdk-version=19.07` 等

## 工具链安装

### 推荐：安装 OpenWRT 24.10 通用版（所有架构）
```bash
# 默认安装最新稳定版 24.10
sudo ./install_toolchains.sh --platform=openwrt --arch=all
```

### 特定场景：安装精确版本（兼容性问题时）
```bash
# 安装 23.05 精确版
sudo ./install_toolchains.sh --platform=openwrt --arch=all --version=23.05

# 安装 19.07 精确版
sudo ./install_toolchains.sh --platform=openwrt --arch=mipsel --version=19.07
```

### Linux：安装 GNU 工具链（推荐用于非路由设备）
```bash
sudo ./install_toolchains.sh --platform=gnu --arch=all
```

### 快速安装所有工具链
```bash
# 使用批量安装脚本（夜间执行，自动继续失败项）
./install_all_toolchains.sh
```

## 编译命令

### 编译 Linux + OpenWRT 所有架构(默认)
```bash
ssh arthur@192.168.0.32
cd ~/mynet/gnb/scripts/release
./build_and_upload.sh v1.5.3
```

### 只编译特定平台和架构
```bash
# Linux 平台特定架构（GNU glibc，推荐用于非路由Linux设备）
./build_and_upload.sh --arch linux:arm64 --arch linux:riscv64 v1.5.3

# OpenWRT 平台特定架构
./build_and_upload.sh --arch openwrt:mipsel --arch openwrt:arm64 v1.5.3

# 嵌入式设备（自定义嵌入式系统）
./build_and_upload.sh --arch embedded:mipsel v1.5.3
```

### 只编译不上传
```bash
./build_and_upload.sh --no-upload v1.5.3
```

### 清理后编译
```bash
./build_and_upload.sh --clean v1.5.3
```

## 支持的平台和架构

### Linux 平台 (linux:arch) - `build_linux.sh`
- **工具链**: GNU gcc + glibc
- **链接方式**: 静态链接
- **架构**: amd64, i386, arm64, armv7, mips, mipsel, mips64, mips64el, riscv64
- **适用**: 
  - 标准 Linux 发行版（Ubuntu, Debian, CentOS, Fedora等）
  - **非路由器设备**（如服务器、工作站、NAS）
  - **UBNT EdgeRouter** 等基于标准 Linux 的设备（推荐）
- **说明**: 使用 glibc 静态链接，兼容性最好

### OpenWRT 平台 (openwrt:arch) - `build_openwrt.sh`
- **工具链**: OpenWRT SDK（优先）→ musl-cross（降级）
- **链接方式**: 
  - 默认：静态链接 musl（通用，兼容所有 OpenWRT 版本）
  - 指定版本：动态链接（针对特定 OpenWRT 版本）
- **架构**: amd64, i386, arm64, armv7, armv7-softfp, mips, mips-softfp, mipsel, mipsel-softfp, mips64, mips64el, riscv64
- **适用**: **OpenWRT 路由器设备**（各品牌路由器）
- **说明**: 默认 SDK 24.10 静态编译，向下兼容所有版本

### 嵌入式平台 (embedded:arch) - `build_embedded_musl.sh`
- **工具链**: musl-cross
- **链接方式**: 静态链接 musl
- **架构**: amd64, i386, arm64, armv7, armv7-softfp, mips, mips-softfp, mipsel, mipsel-softfp, mips64, mips64el, riscv64
- **适用**: 
  - **自定义嵌入式 Linux 系统**（使用 musl libc）
  - Mikrotik RouterOS（部分型号）
- **说明**: 专为 musl libc 嵌入式系统设计

## 输出目录
- 编译临时文件: `~/mynet/gnb/.build/v1.5.3/<平台>/<架构>/`
- 发布包: `~/mynet/gnb/dist/v1.5.3/gnb_<平台>_<架构>_v1.5.3.tar.gz`
