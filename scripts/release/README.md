# GNB 编译系统

GNB 多平台交叉编译系统，支持 Linux、OpenWRT、嵌入式平台的自动化编译。

## 快速开始

```bash
# 1. 安装工具链（首次使用）
sudo ./install_toolchains.sh --platform=openwrt --arch=all
sudo ./install_toolchains.sh --platform=gnu --arch=all

# 2. 编译并上传（默认编译 Linux + OpenWRT 所有架构）
./build_and_upload.sh v1.5.3

# 3. 只编译特定平台
./build_and_upload.sh --arch linux:arm64 --arch openwrt:mipsel v1.5.3
```

## 平台说明

| 平台 | 工具链 | 适用场景 |
|------|--------|---------|
| **Linux** | GNU gcc + glibc | 标准 Linux 发行版、服务器、NAS、**UBNT EdgeRouter** 等 |
| **OpenWRT** | OpenWRT SDK + musl | OpenWRT 路由器（各品牌） |
| **Embedded** | musl-cross | 使用 musl libc 的自定义嵌入式系统 |

## 重要说明

### UBNT EdgeRouter 用户
**推荐使用 Linux 平台编译**（GNU glibc 版本），而不是嵌入式 musl 版本：
```bash
./build_and_upload.sh --arch linux:mipsel v1.5.3
```

UBNT EdgeRouter 基于标准 Debian，使用 glibc，因此 Linux 版本兼容性最好。

### OpenWRT 用户
默认使用 OpenWRT SDK 24.10 静态链接，向下兼容所有版本：
```bash
./build_and_upload.sh --arch openwrt:mipsel v1.5.3
```

遇到兼容性问题时可指定特定版本：
```bash
./build_and_upload.sh --sdk-version=19.07 --arch openwrt:mipsel v1.5.3
```

## 文档

- [USAGE.md](USAGE.md) - 详细使用说明
- [TOOLCHAIN_STRUCTURE.md](TOOLCHAIN_STRUCTURE.md) - 工具链目录结构
- [TOOLCHAIN_COMPARISON.md](TOOLCHAIN_COMPARISON.md) - 工具链对比

## 脚本说明

- `build_and_upload.sh` - 主入口，自动路由到对应编译脚本
- `build_linux.sh` - Linux 平台编译（GNU glibc）
- `build_openwrt.sh` - OpenWRT 平台编译（SDK + musl）
- `build_embedded_musl.sh` - 嵌入式平台编译（musl-cross）
- `install_toolchains.sh` - 工具链安装
- `upload.sh` - 上传脚本

## 参数格式

所有脚本支持两种参数格式：
- `--param value`（推荐）
- `--param=value`（兼容）

可混合使用：`--arch linux:arm64 --sdk-version=23.05`
