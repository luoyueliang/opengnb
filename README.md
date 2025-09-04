opengnb 构建与发布
=================

这个仓库提供 gnb 的统一构建与发布工作流，按不同 OS 选择对应 Makefile，并输出多架构产物，同时可上传到自定义下载站点。

工作流位置
---------

- `.github/workflows/build.yml`

触发方式
------

- 推送 tag 形如 `v*` 会自动触发（例如 `v1.6.0.a`）。
- 也可从 Actions 页面手动运行，并传入 `tag` 输入参数。

Makefile 约定
-----------

为支持不同操作系统，工作流会选择对应的 Makefile：

- Linux: `Makefile.linux`
- OpenWrt: `Makefile.openwrt`
- Windows: `Makefile.windows`
- macOS (Darwin): `Makefile.darwin`
- FreeBSD: `Makefile.freebsd`

每个 Makefile 需支持以下变量：

- `OS`：目标系统（如 linux/openwrt/windows/darwin/freebsd）
- `ARCH`：目标架构（如 amd64/arm64/armv7-softfp/armv7-hardfp/mips/...）
- `VERSION`：版本（来自 tag）
- `OUT_DIR`：输出目录（中间产物目录，按 `{tag}/{os}/{arch}` 分层），需将构建产物放入该目录
  

产物与校验
--------

- 打包规则：
	- Windows 使用 `zip`
	- 其他平台使用 `tgz`
- 发布布局（不创建 latest，版本体现在目录层级）：
	- 远端目录：`{DOWNLOAD_SSH_REMOTE_DIR}/{tag}/`
	- 包文件名：`gnb_{os}_{arch}.{ext}`（文件名不含版本）
- 发布阶段会生成 `checksums.txt`（sha256），与所有包一起上传。

远程上传（rsync）
-------------

工作流支持通过 rsync 上传到远端服务器，目录结构为：`$DOWNLOAD_SSH_REMOTE_DIR/{tag}`。

在仓库 Settings → Secrets and variables → Actions 中配置以下 Secrets：

- `DOWNLOAD_SSH_HOST`：SSH 主机名
- `DOWNLOAD_SSH_USER`：SSH 用户名
- `DOWNLOAD_SSH_KEY`：私钥内容（PEM）
- `DOWNLOAD_SSH_REMOTE_DIR`：远端基础目录（不含 tag）

当以上四个 Secrets 均配置时，发布 Job 会自动上传；否则跳过上传，仅保留 GitHub Artifacts。

变量语义（OS/ARCH/VERSION/OUT_DIR/SRC_DIR）
------------------------------

- `OS`：目标系统，用于选择工具链、依赖和打包方式。
- `ARCH`：目标架构，用于交叉编译时设定编译器/ABI/指令集变体（如 armv7-softfp/hardfp）。
- `VERSION`：发布版本号，来源于 tag（如 v1.6.0.a），用于内嵌版本信息和产物命名。
- `OUT_DIR`：本地构建输出目录（按 `{tag}/{os}/{arch}` 分层），Makefile 需将产物放入该目录。
- `SRC_DIR`：源码目录，固定为本仓库 `src/`。

注意：不生成 `latest` 目录，发布与远程目录严格按版本命名（如 `{REMOTE_DIR}/v1.6.0.a/`）。

目标平台矩阵
--------

当前默认版本：`v1.6.0.a`

平台与架构：

- linux/openwrt（platform=linux）：`amd64, arm64, armv7-softfp, armv7-hardfp, mips, mipsel, mips64, mips64el, riscv64`
- windows（platform=windows）：`amd64, arm64, 386`
- darwin（platform=darwin）：`amd64, arm64`
- freebsd（platform=freebsd）：`amd64, arm64`

注意事项
-----

1. 请确保各平台对应 Makefile 已存在并可在 Ubuntu 构建环境下进行交叉编译（或在 Makefile 内自行拉取工具链）。
2. 如需变更版本矩阵或命名，可编辑工作流矩阵或打包步骤。
3. 远端下载站点的 checksums 路径可为：`https://download.mynet.club/gnb/{tag}/checksums.txt`（需与服务器目录对应）。

同步外部源码到本仓库
--------------

为减少外部仓库变动带来的不确定性，使用脚本将外部公开仓库指定版本同步到本仓库 `src/`，并记录来源与本地追踪信息：

用法（在仓库根目录运行）：

```bash
bash scripts/sync_source.sh --repo owner/repo --ref v1.6.0.a --subdir path/in/repo --version v1.6.0.a
```

脚本行为：
- 将外部仓库指定 `ref`（tag/branch/sha）的代码（可选 `subdir`）同步到 `src/`
- 提交到当前仓库，提交信息包含来源仓库与来源 commit 短 SHA
- 创建本地 tag：`src-sync/<version|ref>`（若重复则自动加时间戳后缀）
- 在 `sources/history.ndjson` 追加一行 JSON（ndjson）用于追踪：来源仓库/引用/来源 commit、本地提交/标签、创建时间与 diffstat

之后，Actions 构建总是从本仓库 `src/` 进行编译。
# opengnb