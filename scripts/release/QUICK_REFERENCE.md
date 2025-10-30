# GNB 编译系统 - 快速参考

## 🚀 快速开始

### 基本用法（推荐）
```bash
# 编译所有架构并上传（使用默认策略）
./build_and_upload.sh ver1.6.0.a

# 仅编译不上传
./build_and_upload.sh --no-upload ver1.6.0.a

# 编译特定架构
./build_and_upload.sh --arch linux:arm64 --arch openwrt:mips64 ver1.6.0.a
```

## 📋 脚本速查

| 脚本 | 用途 | 何时使用 |
|------|------|---------|
| `build_and_upload.sh` | 主入口路由器 | **大部分情况** - 自动选择正确的编译策略 |
| `build_linux.sh` | Linux 平台编译 | 只编译 Linux 版本 |
| `build_openwrt_musl.sh` | OpenWRT musl 编译 | 只编译 OpenWRT（推荐静态链接） |
| `build_openwrt_sdk.sh` | OpenWRT SDK 编译 | 需要 SDK 动态链接版本 |
| `upload.sh` | 独立上传 | 已有编译产物，仅需上传 |

## 🎯 常见场景

### 场景 1: 日常编译发布
```bash
# 使用默认策略编译所有平台
./build_and_upload.sh ver1.6.0.a
```
**结果**: 
- Linux → GNU gcc 静态链接
- OpenWRT → musl 静态链接

---

### 场景 2: 强制使用 SDK（动态链接）
```bash
# OpenWRT 使用 SDK，Linux 仍用 GNU gcc
./build_and_upload.sh --use-sdk --sdk-version=23.05 --sdk-abi=hard ver1.6.0.a
```
**结果**:
- Linux → GNU gcc 静态链接
- OpenWRT → SDK 动态链接

---

### 场景 3: 只编译特定平台
```bash
# 只编译 Linux
./build_linux.sh ver1.6.0.a

# 只编译 OpenWRT（musl）
./build_openwrt_musl.sh ver1.6.0.a

# 只编译 OpenWRT（SDK）
./build_openwrt_sdk.sh ver1.6.0.a --sdk-version=23.05 --sdk-abi=hard
```

---

### 场景 4: 编译单个架构
```bash
# 只编译 Linux arm64
./build_linux.sh --arch linux:arm64 ver1.6.0.a

# 只编译 OpenWRT mipsel
./build_openwrt_musl.sh --arch openwrt:mipsel ver1.6.0.a
```

---

### 场景 5: 仅上传已编译版本
```bash
# 先编译（不上传）
./build_and_upload.sh --no-upload ver1.6.0.a

# 稍后上传
./build_and_upload.sh --upload-only ver1.6.0.a
# 或直接使用上传脚本
./upload.sh ver1.6.0.a
```

## 📊 编译策略对比

| 策略 | 工具链 | 链接方式 | 二进制大小 | 兼容性 | 推荐 |
|------|--------|---------|-----------|--------|-----|
| **Linux GNU** | 系统 gcc | 静态 | 中等 | 高 | ✅ |
| **OpenWRT musl** | 独立 musl | 静态 | 较小 | 最高 | ✅✅ |
| **OpenWRT SDK** | OpenWRT SDK | 动态 | 最小 | 特定版本 | ⚠️ |

## 🔧 参数速查

### 通用参数
```bash
--help              # 显示帮助
--no-upload         # 仅编译不上传
--upload-only       # 仅上传不编译
--arch OS:ARCH      # 指定架构（可多次使用）
--clean             # 编译前清理
```

### SDK 专用参数
```bash
--use-sdk                    # 强制使用 SDK
--sdk-version=<版本>         # SDK 版本（19.07, 21.02, 22.03, 23.05, 24.10）
--sdk-abi=<ABI>              # 浮点 ABI（hard, soft, default）
```

## 📦 架构列表

### x86 系列
- `amd64` - x86_64 64位
- `i386` - x86 32位

### ARM 系列
- `arm64` - ARM 64位
- `armv7` - ARM v7 hard-float（默认）
- `armv7-softfp` - ARM v7 soft-float

### MIPS 系列
- `mips64` - MIPS 64位大端
- `mips64el` - MIPS 64位小端
- `mips` - MIPS 32位大端 hard-float（默认）
- `mips-softfp` - MIPS 32位大端 soft-float
- `mipsel` - MIPS 32位小端 hard-float（默认）
- `mipsel-softfp` - MIPS 32位小端 soft-float

### RISC-V 系列
- `riscv64` - RISC-V 64位

## 🔍 故障排查

### 问题: 工具链未找到
```bash
# 安装 musl 工具链
sudo ./install_toolchains.sh --platform=musl --arch=arm64

# 安装 OpenWRT SDK
sudo ./install_toolchains.sh --platform=openwrt --arch=mipsel --version=23.05
```

### 问题: 编译失败
```bash
# 1. 清理后重试
./build_and_upload.sh --clean --no-upload ver1.6.0.a

# 2. 测试单个架构
./build_linux.sh --arch linux:amd64 test_v1.0

# 3. 查看详细输出（脚本会自动显示）
```

### 问题: 上传失败
```bash
# 1. 检查 SSH 配置
cat config.env

# 2. 测试 SSH 连接
ssh -i ~/.ssh/mynet_release_key admin@download.mynet.club

# 3. 单独运行上传
./upload.sh ver1.6.0.a
```

## 📚 更多信息

- `REFACTOR_COMPLETE.md` - 重构完成说明
- `USAGE.md` - 详细使用文档
- `TOOLCHAIN_STRUCTURE.md` - 工具链架构
- `TOOLCHAIN_COMPARISON.md` - 工具链对比

## 💡 提示

1. **默认推荐**: 直接使用 `build_and_upload.sh`，它会自动选择最佳策略
2. **静态优先**: OpenWRT 默认使用 musl 静态链接（兼容性最好）
3. **SDK 按需**: 只在明确需要 SDK 动态链接时使用 `--use-sdk`
4. **分步调试**: 遇到问题时使用 `--no-upload` + 单独测试各脚本
5. **查看帮助**: 每个脚本都有 `--help` 参数

---

**Happy Building! 🎉**
