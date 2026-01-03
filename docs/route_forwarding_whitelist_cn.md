# GNB 路由转发白名单机制分析

## 概述

GNB 的路由转发采用**白名单策略**，只有在 `route.conf` 中配置的 IP 地址或网段才会被转发。这是一个**放行策略**而非路由策略，实际的路由决策由系统路由表完成。

## 核心机制

### 两级检查机制

GNB 的转发白名单包含两个独立的检查点：

#### 检查点1：TUN → INET 方向（发送检查）
**位置**：`src/src/packet_filter/gnb_pf_route.c` - `pf_tun_frame_cb()` 函数

**作用**：检查目标节点是否在白名单中

```c
// 从 TUN 设备读取数据包后
pf_ctx->dst_node = gnb_query_route4(gnb_core, dst_ip_int);

if ( NULL == pf_ctx->dst_node ) {
    return GNB_PF_DROP;  // 目标节点不在 route.conf 中，丢弃
}
```

**用途**：确保只向 `route.conf` 中配置的节点发送数据

#### 检查点2：INET → TUN 方向（接收检查）
**位置**：`src/src/packet_filter/gnb_pf_route.c` - `pf_inet_fwd_cb()` 函数

**作用**：检查接收到的数据包的目标 IP 是否在白名单中

```c
// 从网络接收数据包，准备写入 TUN 设备前
dst_node = gnb_query_route4(gnb_core, dst_ip_int);

if ( NULL == dst_node ) {
    pf_ctx->pf_status = GNB_PF_NOROUTE;  // 目标 IP 不在白名单中，拒绝
}
```

**用途**：验证是否允许将数据包写入 TUN 设备

### 路由查询机制

**核心函数**：`gnb_query_route4()` - 位于 `src/src/gnb_pf.c`

查询优先级（从高到低）：

```c
gnb_node_t* gnb_query_route4(gnb_core_t *gnb_core, uint32_t dst_ip_int) {
    gnb_node_t *node = NULL;

    // 1. 精确主机 IP 匹配
    node = GNB_HASH32_UINT32_GET_PTR(gnb_core->ipv4_node_map, dst_ip_int);
    if (node) return node;

    // 2. C 类子网匹配 (/24)
    uint32_t key = dst_ip_int & htonl(IN_CLASSC_NET);  // 255.255.255.0
    node = GNB_HASH32_UINT32_GET_PTR(gnb_core->subnetc_node_map, key);
    if (node) return node;

    // 3. B 类子网匹配 (/16)
    key = dst_ip_int & htonl(IN_CLASSB_NET);  // 255.255.0.0
    node = GNB_HASH32_UINT32_GET_PTR(gnb_core->subnetb_node_map, key);
    if (node) return node;

    // 4. A 类子网匹配 (/8)
    key = dst_ip_int & htonl(IN_CLASSA_NET);  // 255.0.0.0
    node = GNB_HASH32_UINT32_GET_PTR(gnb_core->subneta_node_map, key);
    if (node) return node;

    return NULL;  // 未找到，不在白名单中
}
```

## route.conf 配置规范

### 支持的网络类型

GNB 支持 **5 种标准网段**：

| 类型 | CIDR | 子网掩码 | 配置示例 | 存储位置 |
|------|------|---------|---------|---------|
| **主机IP** | /32 | 任意 | `1002\|8.8.8.8\|255.255.255.255` | `ipv4_node_map` |
| **C类网络** | /24 | 255.255.255.0 | `1002\|192.168.1.0\|255.255.255.0` | `subnetc_node_map` |
| **B类网络** | /16 | 255.255.0.0 | `1002\|172.16.0.0\|255.255.0.0` | `subnetb_node_map` |
| **A类网络** | /8 | 255.0.0.0 | `1002\|10.0.0.0\|255.0.0.0` | `subneta_node_map` |
| **默认路由** | /0 | 0.0.0.0 | `1002\|0.0.0.0\|0.0.0.0` | `subneta_node_map` |

### 配置格式

```
节点ID|IP地址|子网掩码
```

### 判断逻辑

**位置**：`src/src/gnb_conf_file.c` - `load_route_config()` 函数

```c
char *p = (char *)&tun_addr4;

if (0 != p[3] && 0 == node->tun_addr4.s_addr) {
    // IP 最后一位不为 0 → 主机 IP
    GNB_HASH32_UINT32_SET(gnb_core->ipv4_node_map, node->tun_addr4.s_addr, node);
} else {
    // IP 最后一位为 0 → 网络地址，根据掩码分类
    netmask_class = get_netmask_class(tun_netmask_addr4);
    
    if ('c' == netmask_class) {
        GNB_HASH32_UINT32_SET(gnb_core->subnetc_node_map, tun_subnet_addr4, node);
    } else if ('b' == netmask_class) {
        GNB_HASH32_UINT32_SET(gnb_core->subnetb_node_map, tun_subnet_addr4, node);
    } else if ('a' == netmask_class) {
        GNB_HASH32_UINT32_SET(gnb_core->subneta_node_map, tun_subnet_addr4, node);
    }
    // 其他掩码（返回 'n'）：静默忽略，不存储
}
```

### 掩码分类函数

**位置**：`src/src/gnb_address.c` - `get_netmask_class()` 函数

```c
char get_netmask_class(uint32_t addr4) {
    if (!(~(IN_CLASSA_NET) & ntohl(addr4)))  // 255.0.0.0
        return 'a';
    if (!(~(IN_CLASSB_NET) & ntohl(addr4)))  // 255.255.0.0
        return 'b';
    if (!(~(IN_CLASSC_NET) & ntohl(addr4)))  // 255.255.255.0
        return 'c';
    return 'n';  // 非标准掩码
}
```

## 配置示例

### 示例 1：客户端访问外网

**场景**：节点 A 通过节点 B 作为代理访问外网

**节点 A 的 route.conf**
```conf
# 节点 B 的 VPN 地址
1002|10.1.0.2|255.255.255.0

# 默认路由，所有外网流量走节点 B
1002|0.0.0.0|0.0.0.0
```

**节点 B 的 route.conf**
```conf
# 节点 A 的 VPN 地址
1001|10.1.0.1|255.255.255.0

# 节点 B 自己（用于接收来自 A 的外网请求）
1002|10.1.0.2|255.255.255.0

# 代理所有外网流量（可选，如果需要）
1002|0.0.0.0|0.0.0.0
```

**节点 B 的系统配置**
```bash
# 启用 IP 转发
echo 1 > /proc/sys/net/ipv4/ip_forward

# 对从 TUN 出去的流量做 NAT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

**数据流向**：
```
节点A访问 8.8.8.8:
1. gnb_query_route4(8.8.8.8) → 匹配 0.0.0.0/0 → 节点B ✅
2. 通过 GNB 加密隧道发送到节点B

节点B处理:
3. 从网络接收，dst_uuid64 = 1002（节点B自己）
4. pf_inet_route_cb: 判断目标是本地节点，设置为写入 TUN
5. pf_inet_fwd_cb: gnb_query_route4(8.8.8.8) → 匹配 0.0.0.0/0 → 节点B ✅
6. 写入 TUN: src=10.1.0.1, dst=8.8.8.8
7. 系统 NAT: src=节点B公网IP, dst=8.8.8.8
8. 发送到外网

返回流程:
9. 外网 → 节点B，NAT 反向转换: dst=10.1.0.1
10. 系统路由决定走 TUN 设备
11. GNB 从 TUN 读取: dst=10.1.0.1
12. gnb_query_route4(10.1.0.1) → 节点A ✅
13. 转发回节点A
```

### 示例 2：访问特定网段

**场景**：只代理特定的网络服务

**节点 A 的 route.conf**
```conf
# 节点 B
1002|10.1.0.2|255.255.255.0

# 只代理 Google DNS
1002|8.8.8.0|255.255.255.0

# 只代理 Cloudflare DNS
1002|1.1.1.0|255.255.255.0

# 代理公司内网
1002|192.168.50.0|255.255.255.0
1002|192.168.51.0|255.255.255.0
```

### 示例 3：多节点分流

**场景**：不同网络走不同的代理节点

```conf
# 节点 B - 代理 Google 服务
1002|10.1.0.2|255.255.255.0
1002|8.8.8.0|255.255.255.0

# 节点 C - 代理 Cloudflare 服务
1003|10.1.0.3|255.255.255.0
1003|1.1.1.0|255.255.255.0

# 节点 D - 代理公司网络
1004|10.1.0.4|255.255.255.0
1004|192.168.100.0|255.255.0.0
```

## 常见问题

### Q1: /27、/28、/29 等 CIDR 掩码是否支持？

**答**：❌ 不支持

- 配置不会报错
- 不会自动回退到 /24
- **会被静默忽略**，路由不生效

**示例**：
```conf
# ❌ 这条配置会被忽略
1002|192.168.1.0|255.255.255.248

# 原因：
# get_netmask_class(255.255.255.248) 返回 'n'
# 所有 if 条件都不满足，不存入任何哈希表
```

### Q2: 单个主机 IP (/32) 是否支持？

**答**：✅ 有条件支持

**情况 A**：IP 最后一位不为 0（支持）
```conf
✅ 1002|8.8.8.8|255.255.255.255      # 精确匹配 8.8.8.8
✅ 1002|1.1.1.1|255.255.255.255      # 精确匹配 1.1.1.1
```

**情况 B**：IP 最后一位为 0（不支持）
```conf
❌ 1002|192.168.1.0|255.255.255.255  # 会被静默忽略
```

### Q3: 如何配置默认路由？

**答**：使用 `0.0.0.0/0.0.0.0`

```conf
1002|0.0.0.0|0.0.0.0
```

- 匹配所有未明确配置的 IP
- 存储在 `subneta_node_map` 中
- 查询时：任何 IP & 0.0.0.0 = 0.0.0.0，总能匹配

### Q4: 配置了非标准掩码为什么不生效？

**答**：因为被静默忽略了

**问题**：代码中没有错误提示或警告

**建议的改进**（可选）：
```c
// 在 gnb_conf_file.c 中添加警告日志
if ('n' == netmask_class) {
    GNB_LOG1(gnb_core->log, GNB_LOG_ID_CORE, 
             "route.conf: unsupported netmask %s for %s, entry ignored\n", 
             tun_netmask_string, tun_ipv4_string);
}
```

### Q5: 路由策略和放行策略的区别？

**答**：

**放行策略（GNB 的白名单）**：
- 决定是否允许数据包通过 GNB 隧道
- 配置在 `route.conf` 中
- 只是"放行"或"拒绝"的开关

**路由策略（系统路由表）**：
- 决定数据包实际走哪条路径
- 配置在系统路由表中（`ip route`）
- 提供灵活的路由决策

**配合使用**：
```bash
# GNB 配置：允许访问节点 B
# route.conf
1002|10.1.0.2|255.255.255.0

# 系统路由：决定哪些流量走节点 B
ip route add 8.8.8.0/24 via 10.1.0.2 dev gnb0
ip route add 1.1.1.0/24 via 10.1.0.2 dev gnb0
ip route add default via 10.1.0.2 dev gnb0  # 所有流量
```

## 技术限制

### 内存和容量限制

| 限制项 | 数值 | 说明 |
|--------|------|------|
| 单行长度 | 1024 字节 | `fscanf(file,"%1024s\n",line_buffer)` |
| 节点数量 | 256 个 | 不同的节点 ID 数量 |
| 主机IP映射 | 1024 条 | `ipv4_node_map` 哈希表容量 |
| C类子网映射 | 1024 条 | `subnetc_node_map` 容量 |
| B类子网映射 | 1024 条 | `subnetb_node_map` 容量 |
| A类子网映射 | 1024 条 | `subneta_node_map` 容量 |

**实际容量**：
- 同一节点 ID 可配置多条路由（只占用 1 个节点槽位）
- 但每条 IP/网段会占用哈希表的一个条目
- 建议使用更大的网段掩码减少条目数

**优化建议**：
```conf
# ❌ 不推荐：逐个配置 C 类网段（占用 256 个条目）
1002|192.168.0.0|255.255.255.0
1002|192.168.1.0|255.255.255.0
...
1002|192.168.255.0|255.255.255.0

# ✅ 推荐：使用 B 类网段（只占用 1 个条目）
1002|192.168.0.0|255.255.0.0
```

## 代码位置索引

| 功能 | 文件 | 函数/行号 |
|------|------|----------|
| 路由配置加载 | `src/src/gnb_conf_file.c` | `load_route_config()` 第 1298 行 |
| 路由查询 | `src/src/gnb_pf.c` | `gnb_query_route4()` 第 30 行 |
| TUN 发送检查 | `src/src/packet_filter/gnb_pf_route.c` | `pf_tun_frame_cb()` 第 83 行 |
| INET 接收检查 | `src/src/packet_filter/gnb_pf_route.c` | `pf_inet_fwd_cb()` 第 636 行 |
| 掩码分类 | `src/src/gnb_address.c` | `get_netmask_class()` 第 92 行 |
| 哈希表初始化 | `src/src/gnb_core.c` | `gnb_core_create()` 第 531 行 |

## 最佳实践

### 1. 使用标准网段

```conf
✅ 1002|192.168.1.0|255.255.255.0   # /24 C类
✅ 1002|172.16.0.0|255.255.0.0      # /16 B类
✅ 1002|10.0.0.0|255.0.0.0          # /8  A类
✅ 1002|0.0.0.0|0.0.0.0             # /0  默认路由

❌ 1002|192.168.1.0|255.255.255.248 # /29 不支持
```

### 2. 灵活使用系统路由

```bash
# GNB 只配置节点和大网段
# route.conf
1002|10.1.0.2|255.255.255.0
1002|0.0.0.0|0.0.0.0

# 系统路由实现精细控制
ip route add 8.8.8.8/32 via 10.1.0.2 dev gnb0       # 单个IP
ip route add 192.168.1.0/27 via 10.1.0.2 dev gnb0   # /27 子网
ip route add 10.20.0.0/22 via 10.1.0.2 dev gnb0     # /22 子网
```

### 3. 配置验证

启用日志查看路由匹配情况：
```bash
gnb -c /etc/gnb/1001 --if-dump
```

### 4. 节点作为网关的完整配置

**网关节点配置**：
```bash
# 1. route.conf 配置
1001|10.1.0.1|255.255.255.0     # 客户端节点
1002|10.1.0.2|255.255.255.0     # 网关自己
1002|0.0.0.0|0.0.0.0            # 代理所有流量

# 2. 系统配置
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# 3. 持久化（可选）
# Debian/Ubuntu
iptables-save > /etc/iptables/rules.v4
# CentOS/RHEL
service iptables save
```

## 安全建议

1. **最小权限原则**：只配置必需的网段，避免使用 `0.0.0.0/0` 除非确实需要
2. **分层防护**：结合防火墙规则和 GNB 白名单
3. **定期审计**：检查 `route.conf` 中的配置是否仍然需要
4. **监控流量**：使用 `--if-dump` 选项监控异常流量

## 总结

GNB 的路由转发白名单机制设计简洁高效：

- ✅ **双向保护**：TUN→INET 和 INET→TUN 双向检查
- ✅ **性能优良**：基于哈希表的快速查询
- ✅ **配置简单**：支持标准的 /32、/24、/16、/8、/0 网段
- ⚠️ **需要注意**：非标准掩码会被静默忽略
- 💡 **灵活扩展**：白名单+系统路由的组合提供最大灵活性

**核心理念**：GNB 提供"放行策略"，系统路由提供"路由策略"，两者配合实现安全灵活的网络访问控制。

---

文档版本：v1.0  
更新日期：2025-10-31  
适用版本：openGNB main 分支
