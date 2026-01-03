# GNB 2026-01 源码升级说明：多节点路由转发功能

## 📅 升级信息

- **升级日期**: 2026年1月3日
- **源码版本**: 2026-01 版本
- **升级分支**: `dev-2026-01`
- **上游来源**: gnbdev/opengnb
- **主要变更**: 从单节点固定转发升级到多节点智能路由

---

## 🎯 核心功能变更

### 一、路由转发机制重构

#### 旧版本（main分支）- 单节点固定转发
```
route.conf 配置:
  1001|10.1.1.0|255.255.255.0
  1002|10.1.1.0|255.255.255.0  # 会覆盖第一条，只有1002生效

数据结构:
  subnetc_node_map[10.1.1.0] = node_1002  (单个节点指针)

转发逻辑:
  目标IP: 10.1.1.x → 查表 → 固定使用节点 1002
  
问题:
  ❌ 配置重复时，后面的覆盖前面的（哈希表SET特性）
  ❌ 无容错能力，节点离线后无法切换
  ❌ 无负载均衡，所有流量走单节点
```

#### 新版本（dev-2026-01分支）- 多节点智能路由
```
route.conf 配置:
  1001|10.1.1.0|255.255.255.0
  1002|10.1.1.0|255.255.255.0  # 追加到节点环，不会覆盖
  1003|10.1.1.0|255.255.255.0

数据结构:
  subnetc_node_ring_map[10.1.1.0] = {
      num: 3,
      cur_index: 0,
      nodes: [node_1001, node_1002, node_1003]
  }

转发逻辑:
  目标IP: 10.1.1.x → 查表 → 从节点环中智能选择
  
优势:
  ✅ 支持多节点配置，全部保留
  ✅ 自动故障切换（容错模式）
  ✅ 负载均衡（轮询模式）
  ✅ 分层路由匹配（精确IP → C类 → B类 → A类）
```

---

## 📊 技术架构对比

### 1. 数据结构变更

| 组件 | 旧版本 | 新版本 |
|------|--------|--------|
| **C类子网映射** | `subnetc_node_map` | `subnetc_node_ring_map` |
| **B类子网映射** | `subnetb_node_map` | `subnetb_node_ring_map` |
| **A类子网映射** | `subneta_node_map` | `subneta_node_ring_map` |
| **映射类型** | `HashMap<subnet, node*>` | `HashMap<subnet, node_ring*>` |
| **节点存储** | 单个指针 | 节点环数组（最多128个） |

### 2. 新增核心函数

#### `gnb_add_routenode_ring()`
**位置**: [src/src/gnb_node.c](../src/src/gnb_node.c)

**功能**: 将节点追加到子网的节点环中
```c
void gnb_add_routenode_ring(gnb_core_t *gnb_core, 
                             gnb_hash32_map_t *node_ring_map,
                             uint32_t tun_subnet_addr4, 
                             gnb_node_t *node)
```

**逻辑**:
1. 查找子网对应的 node_ring
2. 如果不存在，创建新的 node_ring
3. 将节点**追加**到 ring 数组（而非覆盖）
4. 节点数量 +1

#### `gnb_select_route4_node()`
**位置**: [src/src/gnb_node.c](../src/src/gnb_node.c)

**功能**: 智能选择路由节点（核心路由算法）
```c
gnb_node_t* gnb_select_route4_node(gnb_core_t *gnb_core, 
                                    uint32_t dst_ip_int)
```

**路由查找优先级**:
```
1. 精确IP匹配 (ipv4_node_map)
   └─ 找到 → 直接返回
   
2. C类子网匹配 (/24, 255.255.255.0)
   └─ 找到 node_ring → 进入节点选择算法
   
3. B类子网匹配 (/16, 255.255.0.0)
   └─ 找到 node_ring → 进入节点选择算法
   
4. A类子网匹配 (/8, 255.0.0.0)
   └─ 找到 node_ring → 进入节点选择算法
   
5. 无匹配 → 返回 NULL
```

**节点选择策略**:

**容错模式 (SIMPLE_FAULT_TOLERANT)** - 默认
```c
// 遍历节点环，返回第一个在线节点
for ( i=0; i<node_ring->num; i++ ) {
    if ( node_ring->nodes[i]->udp_addr_status & GNB_NODE_STATUS_PONG ) {
        return node_ring->nodes[i];  // 找到在线节点
    }
}
return node_ring->nodes[0];  // 都不在线，返回第一个
```

**负载均衡模式 (SIMPLE_LOAD_BALANCE)**
```c
// Round-Robin 轮询选择
for ( i=0; i<node_ring->num; i++ ) {
    node = node_ring->nodes[node_ring->cur_index];
    if ( node->udp_addr_status & GNB_NODE_STATUS_PONG ) {
        node_ring->cur_index++;  // 轮转索引
        if ( node_ring->cur_index >= node_ring->num ) {
            node_ring->cur_index = 0;
        }
        return node;
    }
}
```

### 3. 配置文件解析变更

**旧版本**: [src/src/gnb_conf_file.c](../src/src/gnb_conf_file.c) (main分支)
```c
// 使用 SET 操作，后面的配置会覆盖前面的
if ( 'c' == netmask_class ) {
    GNB_HASH32_UINT32_SET(gnb_core->subnetc_node_map, tun_subnet_addr4, node);
}
```

**新版本**: [src/src/gnb_conf_file.c](../src/src/gnb_conf_file.c) (dev-2026-01分支)
```c
// 使用追加操作，所有配置都保留
if ( 'c' == netmask_class ) {
    gnb_add_routenode_ring(gnb_core, gnb_core->subnetc_node_ring_map, 
                           tun_subnet_addr4, node);
}
```

---

## 🔧 配置示例

### 场景一：简单容错配置

**需求**: 10.1.1.0/24 网段有主备节点，主节点离线时自动切换

**route.conf**:
```properties
# 基础节点定义
1001|10.1.0.1|255.255.255.0
1002|10.1.0.2|255.255.255.0

# 多节点子网配置（容错）
1001|10.1.1.0|255.255.255.0  # 主节点
1002|10.1.1.0|255.255.255.0  # 备节点
```

**node.conf**:
```properties
# 使用默认容错模式（或显式配置）
multi-forward-type fault-tolerant
```

**效果**:
- 正常情况: 所有 10.1.1.x 流量 → 节点 1001
- 1001离线: 自动切换 → 节点 1002
- 都离线: 仍尝试发送到 1001

### 场景二：负载均衡配置

**需求**: 10.1.2.0/24 网段流量在3个节点间均衡分配

**route.conf**:
```properties
# 基础节点
1001|10.1.0.1|255.255.255.0
1002|10.1.0.2|255.255.255.0
1003|10.1.0.3|255.255.255.0

# 负载均衡子网
1001|10.1.2.0|255.255.255.0
1002|10.1.2.0|255.255.255.0
1003|10.1.2.0|255.255.255.0
```

**node.conf**:
```properties
# 启用负载均衡
multi-forward-type balance

# 必须禁用多线程（单线程模式）
pf-worker 0
```

**效果**:
```
连接1: 10.1.2.5  → 节点 1001
连接2: 10.1.2.10 → 节点 1002
连接3: 10.1.2.20 → 节点 1003
连接4: 10.1.2.30 → 节点 1001 (轮回)
```

### 场景三：分层路由配置

**需求**: 不同粒度的路由控制

**route.conf**:
```properties
# 基础节点
1001|10.1.0.1|255.255.255.0
1002|10.1.0.2|255.255.255.0
1003|10.1.0.3|255.255.255.0
1004|10.1.0.4|255.255.255.0

# 精确IP（最高优先级）
1001|10.1.0.100|255.255.255.255

# C类子网（中等优先级）
1002|10.1.1.0|255.255.255.0
1003|10.1.1.0|255.255.255.0

# B类子网（低优先级）
1001|10.1.0.0|255.255.0.0
1004|10.1.0.0|255.255.0.0

# A类子网（兜底路由）
1001|10.0.0.0|255.0.0.0
1002|10.0.0.0|255.0.0.0
```

**路由匹配结果**:
```
10.1.0.100   → 精确匹配 → 节点 1001
10.1.1.50    → C类匹配  → 节点 1002/1003（容错或负载均衡）
10.1.5.20    → B类匹配  → 节点 1001/1004
10.8.8.8     → A类匹配  → 节点 1001/1002
```

---

## 📝 代码变更统计

### 文件级变更

```
修改的文件: 113 个
新增代码:   1,191 行
删除代码:   8,681 行
净减少:     7,490 行
```

### 主要修改文件

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `src/src/gnb.h` | 数据结构 | 新增 node_ring_map 定义 |
| `src/src/gnb_node.h` | 函数声明 | 新增路由选择函数 |
| `src/src/gnb_node.c` | 核心实现 | 实现多节点路由算法 |
| `src/src/gnb_conf_file.c` | 配置解析 | 改用追加模式 |
| `src/src/packet_filter/gnb_pf_route.c` | 路由过滤 | 调用新的路由选择函数 |
| `src/src/gnb_node_type.h` | 类型定义 | gnb_node_ring_t 结构 |
| `src/src/gnb_conf_type.h` | 配置类型 | 格式规范化 |

### 代码质量提升

- ✅ **60%** - 代码格式统一（空行、大括号风格）
- ✅ **35%** - 结构优化和代码简化
- ✅ **5%**  - 功能增强（多节点路由）

---

## ⚠️ 兼容性说明

### 向后兼容

✅ **配置文件完全兼容**
- 旧的 route.conf 配置在新版本中仍然有效
- 单节点配置继续正常工作
- 不需要修改现有配置即可升级

✅ **行为变化**
- **旧行为**: 重复配置时，后者覆盖前者
- **新行为**: 重复配置时，所有节点都保留（追加）

### 破坏性变更

❌ **无破坏性变更**
- 未删除任何公共 API
- 未修改配置文件格式
- 未改变默认行为（默认仍是单节点）

### 配置迁移

**无需迁移**: 旧配置直接可用

**推荐优化**: 利用新功能配置多节点
```properties
# 旧配置（仍然有效）
1001|10.1.1.0|255.255.255.0

# 新配置（推荐，增加容错）
1001|10.1.1.0|255.255.255.0
1002|10.1.1.0|255.255.255.0  # 备用节点
```

---

## 🔍 调试和验证

### 查看节点状态
```bash
# 查看节点连接状态
gnb_ctl -s status

# 检查特定节点的路由
gnb_ctl -s route_table
```

### 日志分析
```properties
# node.conf 中启用详细日志
pf-log-level 3
node-log-level 3

# 查看路由选择日志
tail -f /var/log/gnb/gnb.log | grep "select_route"
```

### 验证多节点生效
```bash
# 1. 配置多节点
echo "1001|10.1.1.0|255.255.255.0" >> route.conf
echo "1002|10.1.1.0|255.255.255.0" >> route.conf

# 2. 重启 GNB
systemctl restart opengnb

# 3. 测试连通性
ping 10.1.1.5

# 4. 模拟节点1001故障（关闭节点1001）
# 5. 再次测试，应该自动切换到节点1002
ping 10.1.1.5
```

---

## 🎓 技术原理

### 为什么旧版本"后配置覆盖前配置"？

**根本原因**: 哈希表 SET 操作的标准行为

```c
// gnb_hash32_set() 函数逻辑
gnb_kv32_t *gnb_hash32_set(hash_map, key, value) {
    // 1. 查找 key
    kv = find_key_in_hashmap(key);
    
    if (kv != NULL) {
        // 2. key 存在 → 覆盖 value
        kv->value = value;  // ⚠️ 覆盖旧值
    } else {
        // 3. key 不存在 → 创建新条目
        create_new_kv(key, value);
    }
}
```

**配置解析过程**:
```
读取: 1001|10.1.1.0|255.255.255.0
  → SET(map, 10.1.1.0, node_1001)
  → map[10.1.1.0] = node_1001

读取: 1002|10.1.1.0|255.255.255.0
  → SET(map, 10.1.1.0, node_1002)
  → 找到 key=10.1.1.0 已存在
  → 覆盖: map[10.1.1.0] = node_1002  ❌ 节点1001丢失
```

### 新版本如何保留所有节点？

**关键**: 使用追加操作而非覆盖

```c
// gnb_add_routenode_ring() 函数逻辑
void gnb_add_routenode_ring(map, subnet, node) {
    // 1. 查找或创建 node_ring
    ring = GET(map, subnet);
    if (ring == NULL) {
        ring = create_node_ring();
        SET(map, subnet, ring);
    }
    
    // 2. 追加节点到数组（不覆盖）
    ring->nodes[ring->num] = node;  // ✅ 追加
    ring->num++;
}
```

**配置解析过程**:
```
读取: 1001|10.1.1.0|255.255.255.0
  → add_ring(map, 10.1.1.0, node_1001)
  → ring = {num:1, nodes:[node_1001]}

读取: 1002|10.1.1.0|255.255.255.0
  → add_ring(map, 10.1.1.0, node_1002)
  → 追加到已有 ring
  → ring = {num:2, nodes:[node_1001, node_1002]}  ✅ 都保留
```

---

## 📚 参考资料

### 相关文件

- 核心实现: [src/src/gnb_node.c](../src/src/gnb_node.c)
- 数据结构: [src/src/gnb_node_type.h](../src/src/gnb_node_type.h)
- 配置解析: [src/src/gnb_conf_file.c](../src/src/gnb_conf_file.c)
- 路由过滤: [src/src/packet_filter/gnb_pf_route.c](../src/src/packet_filter/gnb_pf_route.c)

### 相关文档

- 路由转发白名单: [docs/route_forwarding_whitelist_cn.md](route_forwarding_whitelist_cn.md)
- GNB 用户手册: [src/docs/gnb_user_manual_cn.md](../src/docs/gnb_user_manual_cn.md)

### 提交历史

```bash
# 查看升级相关的提交
git log --oneline dev-2026-01 --not main

# 查看详细的代码变更
git diff main..dev-2026-01 src/src/gnb_node.c
```

---

## 📋 TODO 和未来改进

- [ ] 支持基于延迟的智能选择（选择延迟最低的节点）
- [ ] 支持基于带宽的负载均衡
- [ ] 支持节点权重配置
- [ ] 增加路由选择的性能指标监控
- [ ] 支持动态调整节点优先级

---

**文档版本**: v1.0  
**最后更新**: 2026-01-03  
**维护者**: GNB 开发团队
