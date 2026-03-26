# mynet_gnb (GNB P2P 核心) — v2 升级指南

> 优先级: **P1（第三批升级，与 mynet_utc 并行）**
> 关联文档: `mynet_ctl/docs/v2-upgrade-plan.md`（总规划）

---

## 一、当前状态

| 项目 | 值 |
|------|------|
| 语言 | C |
| 版本 | v1.6.0.a (target.json) |
| 构建 | per-OS Makefile + GitHub Actions CI |
| 产品名 | `gnb` |

**当前 URL 配置（需迁移）：**

| 文件 | 当前 URL | 问题 |
|------|----------|------|
| `.github/workflows/build_*.yml` (×4) | `BASE_URL: https://download.mynet.club/gnb` | ⚠️ CI 上传到废弃站 |
| `target.json` | `https://{{DOWNLOAD_SSH_HOST}}/gnb/v1.6.0.a/` | 模板变量 |

---

## 二、升级任务

### 2.1 CI 改为上传到 CTL release API

**文件: `.github/workflows/build_linux.yml`（及其他 3 个 build_*.yml）**

移除旧的 SSH/SCP 上传步骤，改为 HTTP POST 到 CTL：

```yaml
# 旧方式 (SSH 上传到 download.mynet.club):
# - name: Upload to download server
#   uses: appleboy/scp-action@...
#   with:
#     host: ${{ secrets.DOWNLOAD_SSH_HOST }}
#     ...

# 新方式 (POST 到 CTL release API):
- name: Upload to CTL
  run: |
    for f in build/output/*.tgz; do
      filename=$(basename "$f")
      # 从文件名解析: gnb_linux_amd64_v1.6.0.a.tgz
      platform=$(echo "$filename" | cut -d'_' -f2)
      arch=$(echo "$filename" | cut -d'_' -f3)
      version=$(echo "$filename" | cut -d'_' -f4 | sed 's/.tgz$//')

      curl -X POST "https://ctl.mynet.club/api/v2/releases" \
        -H "Authorization: Bearer ${{ secrets.CTL_RELEASE_TOKEN }}" \
        -F "product=gnb" \
        -F "version=${version}" \
        -F "platform=${platform}" \
        -F "arch=${arch}" \
        -F "file=@${f}" \
        -F "changelog=CI build $(date +%Y-%m-%d)" \
        -F "is_stable=1"
    done
```

### 2.2 配置 GitHub Secrets

在 `mynet_gnb` 仓库的 Settings → Secrets 中添加：

| Secret | 值 | 说明 |
|--------|------|------|
| `CTL_RELEASE_TOKEN` | 具有 `release:upload` 权限的 API Token | 从 CTL Admin 创建 |

### 2.3 更新 target.json（可选）

```jsonc
{
  // 旧值:
  // "download_base": "https://{{DOWNLOAD_SSH_HOST}}/gnb/v1.6.0.a/",
  // 新值:
  "download_base": "https://ctl.mynet.club/api/v2/releases"
}
```

---

## 三、需要修改的文件清单

| 文件 | 操作 | 变更 |
|------|------|------|
| `.github/workflows/build_linux.yml` | 编辑 | 替换 SCP 为 CTL API POST |
| `.github/workflows/build_openwrt.yml` | 编辑 | 同上 |
| `.github/workflows/build_macos.yml` | 编辑 | 同上 |
| `.github/workflows/build_windows.yml` | 编辑 | 同上 |
| `target.json` | 编辑（可选） | 更新 download_base |

---

## 四、验证方法

```bash
# 1. 本地测试 CI 上传（模拟）
# 先在 CTL admin 创建一个具有 release:upload 权限的 token
# 用 curl 手动上传一个测试文件到本地 CTL:

curl -X POST http://ctl.mynet.local/api/v2/releases \
  -H "Authorization: Bearer {your-token}" \
  -F "product=gnb" \
  -F "version=v1.6.0.a-test" \
  -F "platform=linux" \
  -F "arch=amd64" \
  -F "file=@/path/to/gnb_linux_amd64_v1.6.0.a.tgz"

# 2. 确认 CTL 返回 201 + release 数据
# 3. 确认 manifest 中出现新版本:
curl http://ctl.mynet.local/api/v2/gnb/manifest

# 4. GitHub Actions 测试: 推一个 tag 触发 CI，确认上传到 CTL 成功
```

---

## 五、回滚方案

如果 CTL 上传失败，CI workflow 中添加 fallback 到旧 SCP 方式。

---

## 六、注意事项

- GNB 是纯 C binary，**运行时无网络请求**，只有 CI 构建时上传
- 所有已发布的 binary 已在 CTL 中有记录（手动导入/测试数据），只需让 CI 自动上传新版本
- GNB 版本号格式特殊: `v1.6.0.a`（含字母后缀），CTL 的 `validateVersion()` 需要兼容
  - 当前正则: `/^v?\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?$/` — **不匹配** `v1.6.0.a`
  - 需要在 CTL 中修改正则为: `/^v?\d+\.\d+\.\d+([.\-][a-zA-Z0-9.]+)?$/`

**预计工作量**: 中（2-3 小时，含 CI 调试）
