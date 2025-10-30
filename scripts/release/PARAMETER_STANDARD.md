# 参数格式规范

## 统一标准

所有脚本支持**两种参数格式**，任选其一：

### 格式 1：空格分隔（推荐）
```bash
--param value
```

### 格式 2：等号连接（兼容）
```bash
--param=value
```

## 适用脚本

- ✅ `build_openwrt.sh`
- ✅ `build_linux.sh`
- ✅ `build_embedded_musl.sh`
- ✅ `build_and_upload.sh`
- ✅ `upload.sh`
- ✅ `install_toolchains.sh`

## 示例

### 单个参数
```bash
# 空格分隔
./build_openwrt.sh v1.6.0.a --arch arm64

# 等号连接
./build_openwrt.sh v1.6.0.a --arch=arm64
```

### 多个参数
```bash
# 空格分隔
./build_openwrt.sh v1.6.0.a --arch arm64 --sdk-version 24.10 --clean

# 等号连接
./build_openwrt.sh v1.6.0.a --arch=arm64 --sdk-version=24.10 --clean

# 混合使用（也支持）
./build_openwrt.sh v1.6.0.a --arch=arm64 --sdk-version 24.10 --clean
```

### 重复参数（数组）
```bash
# 空格分隔
./build_and_upload.sh v1.6.0.a --arch linux:arm64 --arch linux:amd64

# 等号连接
./build_and_upload.sh v1.6.0.a --arch=linux:arm64 --arch=linux:amd64

# 混合使用
./build_and_upload.sh v1.6.0.a --arch=linux:arm64 --arch linux:amd64
```

## 布尔标志

布尔标志不需要值，只有一种格式：

```bash
--clean
--no-upload
--upload-only
```

## 短选项

短选项使用单个破折号：

```bash
-h        # 帮助
```

## 实现技巧

在 shell 脚本中实现双格式支持：

```bash
case $1 in
    --param|--param=*)
        if [[ "$1" == --param=* ]]; then
            # 等号格式：提取等号后的值
            value="${1#*=}"
            shift
        else
            # 空格格式：使用 $2
            value="$2"
            shift 2
        fi
        ;;
esac
```

## 好处

1. **向后兼容**: `install_toolchains.sh` 原本只支持 `--param=value`，现在也支持空格格式
2. **用户友好**: 用户可以选择自己习惯的格式
3. **一致性**: 所有脚本行为统一
4. **灵活性**: 可以混合使用两种格式
