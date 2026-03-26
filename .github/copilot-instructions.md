# MyNet GNB — Copilot 指南

> C (纯 C99) / GNU Make / 多平台交叉编译  
> 版本: v1.6.0.a  
> 上游: gnbdev/opengnb (GitHub)

## 📚 MyNet 生态系统知识库

> **SSOT 知识库**位于 `mynet_ctl/docs/knowledge-base/`：
> - [ecosystem.md](../../mynet_ctl/docs/knowledge-base/ecosystem.md) — 项目全景
> - [conventions.md](../../mynet_ctl/docs/knowledge-base/conventions.md) — 命名规范、平台矩阵
> - [projects/mynet_gnb.md](../../mynet_ctl/docs/knowledge-base/projects/mynet_gnb.md) — 本项目速查卡

## 项目定位

GNB P2P VPN 核心的**构建与发布封装**。源码同步自 opengnb 上游，本仓库负责：
- 跨平台 CI/CD（Linux 9 架构 + macOS + Windows + FreeBSD）
- 统一发布流程（GitHub Actions → CTL 分发）
- MyNet 生态集成

## ⚠️ 强制规则

### 1. 源码管理
- `src/` 目录同步自 opengnb 上游，不在此仓库直接修改源码
- 修改需通过 `scripts/sync_source.sh` 跟踪同步
- `sources/history.ndjson` 记录所有同步历史

### 2. 编译规范
- 零警告编译（`-Wall -Wextra`）
- 纯 C stdlib + 内嵌 libs（无外部依赖）
- 平台专属 Makefile（`Makefile.linux`, `Makefile.Darwin`, `Makefile.mingw_x86_64`）
- 共享编译规则在 `Makefile.inc`

### 3. 命名规范
遵循 CTL conventions（SSOT）：
```
gnb_{platform}_{arch}_{version}.tgz
```
平台: linux / darwin / macos / windows / openwrt  
架构: amd64 / arm64 / armv7 / mipsel / mips-softfp / ...

### 4. 二进制产出
| Binary | 用途 |
|--------|------|
| `gnb` | VPN 主进程 |
| `gnb_ctl` | 控制工具 |
| `gnb_crypto` | 密钥生成 |
| `gnb_es` | ES 服务（UPnP, NAT-PMP） |

## 关键路径

| 路径 | 内容 |
|------|------|
| `src/Makefile.inc` | 共享编译规则 |
| `src/src/` | GNB 核心源码 |
| `src/libs/` | 内嵌库（ed25519, miniupnpc, zlib） |
| `.github/workflows/` | CI/CD 工作流 |
| `scripts/` | 同步与发布脚本 |
| `target.json` | 构建目标矩阵 |
