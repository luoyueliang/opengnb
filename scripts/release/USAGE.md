# GNB 编译快速参考

## 最新更新（v4）

### 优化内容
1. ✅ **默认使用 OpenWRT 24.10 通用版**：最新工具链(GCC 13.3.0 + musl 1.2.5) + 向下兼容
2. ✅ 保留精确版本支持：用于解决特定设备兼容性问题
3. ✅ 保留 musl-cross：用于非 OpenWRT 的嵌入式设备(如 UBNT EdgeRouter)
4. ✅ 优化工具链选择策略：更清晰的优先级和使用场景
5. ✅ **统一参数格式**：所有脚本支持 `--param value` 和 `--param=value` 两种格式

### 参数格式规范

所有脚本支持两种参数格式（详见 [PARAMETER_STANDARD.md](PARAMETER_STANDARD.md)）：

- **空格分隔**（推荐）：`--arch arm64`
- **等号连接**（兼容）：`--arch=arm64`
- **可混合使用**：`--arch=arm64 --sdk-version 24.10`

### 工具链选择策略

| 平台 | 推荐工具链 | 使用场景 | 链接方式 |
|------|-----------|---------|---------|
| **OpenWRT** | OpenWRT 24.10 SDK | 所有 OpenWRT 设备（默认） | **静态链接** musl（通用） |
| **OpenWRT** | OpenWRT SDK 指定版本 | 特定版本兼容性问题 | **动态链接**（针对版本） |
| **嵌入式** | musl-cross | UBNT/非OpenWRT设备 | 静态链接 musl |
| **Linux** | GNU gcc | 标准 Linux 发行版 | 静态链接 glibc（默认） |

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

### 嵌入式设备：安装 musl-cross（UBNT 等设备）
```bash
# 为 UBNT EdgeRouter (mipsel) 安装 musl-cross
sudo ./install_toolchains.sh --platform=musl --arch=mipsel
```

### Linux：安装 GNU 工具链
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
# Linux 平台特定架构
./build_and_upload.sh --arch linux:arm64 --arch linux:riscv64 v1.5.3

# OpenWRT 平台特定架构
./build_and_upload.sh --arch openwrt:mipsel --arch openwrt:arm64 v1.5.3

# 嵌入式设备 (UBNT EdgeRouter)
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
- **链接方式**: 静态链接（默认）/ 动态链接（可选 `--dynamic`）
- **架构**: amd64, i386, arm64, armv7, mips, mipsel, mips64, mips64el, riscv64
- **适用**: Ubuntu, Debian, CentOS, Fedora 等标准 Linux 发行版
- **说明**: 默认静态编译，可提供极端情况下的动态版本

### OpenWRT 平台 (openwrt:arch) - `build_openwrt.sh`
- **工具链**: OpenWRT SDK（优先）→ musl-cross（降级）
- **链接方式**: 
  - 默认：静态链接 musl（通用，兼容所有 OpenWRT 版本）
  - 指定版本：动态链接（针对特定 OpenWRT 版本）
- **架构**: amd64, i386, arm64, armv7, armv7-softfp, mips, mips-softfp, mipsel, mipsel-softfp, mips64, mips64el, riscv64
- **适用**: 所有 OpenWRT 路由器设备
- **说明**: 已完成，默认 SDK 24.10 静态编译，向下兼容所有版本

### 嵌入式平台 (embedded:arch) - `build_embedded_musl.sh`
- **工具链**: musl-cross
- **链接方式**: 静态链接 musl
- **架构**: amd64, i386, arm64, armv7, armv7-softfp, mips, mips-softfp, mipsel, mipsel-softfp, mips64, mips64el, riscv64
- **适用**: UBNT EdgeRouter, Mikrotik RouterOS, 自定义嵌入式 Linux 系统
- **说明**: 为非 OpenWRT 的嵌入式设备提供支持

## 输出目录
- 编译临时文件: `~/mynet/gnb/.build/v1.5.3/<平台>/<架构>/`
- 发布包: `~/mynet/gnb/dist/v1.5.3/gnb_<平台>_<架构>_v1.5.3.tar.gz`
