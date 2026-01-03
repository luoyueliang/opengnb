# GNB Map 数据可视化实现提示词文档

## 文档概述
本文档为实现 OpenGNB 控制块(gnb.map)数据可视化提供完整的数据字典、分析逻辑和技术规范。适用于开发 Web Dashboard、监控面板或命令行工具。

---

## 一、GNB Map 数据字典

### 1.1 核心数据结构

#### **ctl_block (控制块根结构)**
```
gnb_ctl_block_t {
  ├── conf_zone      配置区域
  ├── core_zone      核心区域
  ├── status_zone    状态区域  
  └── node_zone      节点区域
}
```

### 1.2 配置区域 (conf_zone)

| 字段名 | 类型 | 说明 | 示例 |
|--------|------|------|------|
| conf_dir | string | 配置文件目录路径 | /usr/local/opt/mynet/driver/gnb/conf/3764021915150630 |

### 1.3 核心区域 (core_zone)

| 字段名 | 类型 | 说明 | 示例 | 更新频率 |
|--------|------|------|------|----------|
| local_uuid | uint64 | 本地节点唯一标识 | 3764021915150630 | 固定 |
| wan4_addr | byte[4] | WAN IPv4地址 | 114.246.236.254 | 变化时更新 |
| wan4_port | uint16 | WAN IPv4端口(网络字节序) | 34202 | 变化时更新 |
| wan6_addr | byte[16] | WAN IPv6地址 | 2408:8409:78c1:... | 变化时更新 |
| wan6_port | uint16 | WAN IPv6端口(网络字节序) | 9001 | 变化时更新 |
| ifname | string[256] | 虚拟网卡名称 | tun0 | 固定 |
| ed25519_private_key | byte[64] | Ed25519私钥 | (加密) | 固定 |
| ed25519_public_key | byte[32] | Ed25519公钥 | (十六进制) | 固定 |

### 1.4 状态区域 (status_zone)

| 字段名 | 类型 | 说明 | 更新频率 | 用途 |
|--------|------|------|----------|------|
| keep_alive_ts_sec | uint64 | 进程心跳时间戳(秒) | 实时更新 | 判断GNB进程是否运行 |

**关键常量**: `GNB_CTL_KEEP_ALIVE_TS = 15秒`

**判断逻辑**:
```
进程状态 = (当前时间 - keep_alive_ts_sec) < 15秒 ? "运行中" : "已停止"
```

### 1.5 节点区域 (node_zone)

#### **节点基础信息**

| 字段名 | 类型 | 说明 | 示例值 |
|--------|------|------|--------|
| uuid64 | uint64 | 节点唯一标识 | 8283289760467957 |
| tun_addr4 | in_addr | 虚拟网络IPv4地址 | 10.182.236.182 |
| tun_ipv6_addr | in6_addr | 虚拟网络IPv6地址 | 64:ff9b::ab6:ecb6 |
| type | uint8 | 节点类型位掩码 | 见下表 |

**节点类型常量**:
```c
GNB_NODE_TYPE_STD         = 0x0     // 标准节点
GNB_NODE_TYPE_IDX         = 0x1     // 索引节点
GNB_NODE_TYPE_FWD         = 0x2     // 转发节点
GNB_NODE_TYPE_RELAY       = 0x4     // 中继节点
GNB_NODE_TYPE_SLIENCE     = 0x8     // 静默节点
GNB_NODE_TYPE_STATIC_ADDR = 0x10    // 静态地址节点
```

#### **流量统计**

| 字段名 | 类型 | 说明 | 更新时机 |
|--------|------|------|----------|
| in_bytes | uint64 | 接收字节总数 | 收到数据包时累加 |
| out_bytes | uint64 | 发送字节总数 | 发送数据包时累加 |

#### **连接状态**

| 字段名 | 类型 | 说明 | 取值 |
|--------|------|------|------|
| udp_addr_status | uint | UDP连接状态位掩码 | 见下表 |

**状态位定义**:
```c
GNB_NODE_STATUS_UNREACHABL = 0x0   // 0000 不可达
GNB_NODE_STATUS_IPV4_PING  = 0x1   // 0001 已发送IPv4 PING
GNB_NODE_STATUS_IPV6_PING  = 0x2   // 0010 已发送IPv6 PING
GNB_NODE_STATUS_IPV4_PONG  = 0x4   // 0100 收到IPv4 PONG (直连)
GNB_NODE_STATUS_IPV6_PONG  = 0x8   // 1000 收到IPv6 PONG (直连)
```

**状态判断逻辑**:
```javascript
function getConnectionStatus(udp_addr_status) {
  const ipv4_direct = (udp_addr_status & 0x4) !== 0;
  const ipv6_direct = (udp_addr_status & 0x8) !== 0;
  
  if (ipv4_direct && ipv6_direct) return "双栈直连";
  if (ipv4_direct) return "IPv4直连";
  if (ipv6_direct) return "IPv6直连";
  return "未连接/中继";
}
```

#### **延迟指标**

| 字段名 | 类型 | 单位 | 说明 | 计算方式 |
|--------|------|------|------|----------|
| addr4_ping_latency_usec | int64 | 微秒 | IPv4延迟 | PONG时间 - PING时间 |
| addr6_ping_latency_usec | int64 | 微秒 | IPv6延迟 | PONG时间 - PING时间 |

**延迟等级划分**:
```javascript
function getLatencyLevel(usec) {
  const ms = usec / 1000;
  if (ms === 0) return { level: "未连接", color: "gray" };
  if (ms < 50) return { level: "优秀", color: "green" };
  if (ms < 100) return { level: "良好", color: "blue" };
  if (ms < 200) return { level: "一般", color: "orange" };
  return { level: "较差", color: "red" };
}
```

#### **时间戳字段**

| 字段名 | 类型 | 说明 | 更新时机 | 超时阈值 |
|--------|------|------|----------|----------|
| ping_ts_sec | uint64 | 最后发送PING时间 | 发送PING包时 | 37秒 |
| addr4_update_ts_sec | uint64 | 最后收到IPv4包时间 | 收到IPv4 PING/PONG | 75秒 |
| addr6_update_ts_sec | uint64 | 最后收到IPv6包时间 | 收到IPv6 PING/PONG | 75秒 |
| last_request_addr_sec | uint64 | 最后请求地址时间 | 向index查询地址 | - |
| last_push_addr_sec | uint64 | 最后推送地址时间 | 推送地址到其他节点 | - |
| last_detect_sec | uint64 | 最后探测时间 | 发送地址探测包 | - |

**关键时间常量**:
```c
GNB_NODE_PING_INTERVAL_SEC = 37                    // PING间隔
GNB_NODE_UPDATE_INTERVAL_SEC = 75                  // 更新超时(37*2+1)
GNB_NODE_MAX_DETECT_TIMES = 32                     // 最大探测失败次数
```

#### **网络地址信息**

| 字段名 | 类型 | 说明 | 最大数量 |
|--------|------|------|----------|
| udp_sockaddr4 | sockaddr_in | 当前IPv4地址端口 | 1 |
| udp_sockaddr6 | sockaddr_in6 | 当前IPv6地址端口 | 1 |
| static_address_block | gnb_address_list_t | 静态配置地址列表 | 6 |
| dynamic_address_block | gnb_address_list_t | 动态发现地址列表 | 16 |
| resolv_address_block | gnb_address_list_t | 域名解析地址列表 | 6 |
| push_address_block | gnb_address_list_t | Index推送地址列表 | 6 |
| available_address4_list3_block | gnb_address_list_t | 可用IPv4地址(最近3个) | 3 |
| available_address6_list3_block | gnb_address_list_t | 可用IPv6地址(最近3个) | 3 |

#### **地址列表条目 (gnb_address_t)**

| 字段名 | 类型 | 说明 |
|--------|------|------|
| type | int | AF_INET(IPv4) 或 AF_INET6(IPv6) |
| socket_idx | uint8 | 更新该地址的socket索引 |
| ts_sec | uint64 | 地址最后更新时间戳 |
| latency_usec | uint64 | 该地址的延迟(微秒) |
| address | union | IPv4(4字节) 或 IPv6(16字节) |
| port | uint16 | 端口号(网络字节序) |

#### **探测统计**

| 字段名 | 类型 | 说明 | 临界值 |
|--------|------|------|--------|
| detect_count | uint32 | 连续探测失败次数 | 32 (达到表示失联) |

**失联判断**:
```javascript
function isNodeOffline(node) {
  return node.detect_count >= 32;
}
```

#### **加密密钥**

| 字段名 | 类型 | 说明 | 长度 |
|--------|------|------|------|
| public_key | byte[] | Ed25519公钥 | 32字节 |
| shared_secret | byte[] | 共享密钥 | 32字节 |
| crypto_key | byte[] | 当前通信密钥 | 64字节 |
| pre_crypto_key | byte[] | 上一个通信密钥 | 64字节 |
| key512 | byte[] | 512位密钥 | 64字节 |

#### **统一转发 (Unified Forwarding)**

| 字段名 | 类型 | 说明 | 大小 |
|--------|------|------|------|
| unified_forwarding_nodeid | uint64 | 当前转发节点ID | - |
| unified_forwarding_node_ts_sec | uint64 | 转发节点时间戳 | - |
| unified_forwarding_node_array | array | 转发节点数组 | 32 |
| unified_forwarding_send_seq | uint64 | 发送序列号 | - |
| unified_forwarding_recv_seq | uint64 | 接收序列号 | - |
| unified_forwarding_recv_seq_array | array | 接收序列数组 | 32 |

**转发节点超时常量**:
```c
GNB_UNIFIED_FORWARDING_NODE_EXPIRED_SEC = 15       // 单节点过期
GNB_UNIFIED_FORWARDING_NODE_ARRAY_EXPIRED_SEC = 90 // 数组过期
```

---

## 二、数据分析逻辑与断言规则

### 2.1 节点在线状态判断

#### **算法流程**
```
1. 读取 udp_addr_status
2. 检查位掩码:
   - udp_addr_status & 0x4 (IPv4_PONG)
   - udp_addr_status & 0x8 (IPv6_PONG)
3. 判断:
   IF (IPv4_PONG OR IPv6_PONG) THEN
     状态 = "在线"
   ELSE
     状态 = "离线"
```

#### **代码实现示例**
```javascript
function isNodeOnline(node) {
  const IPV4_PONG = 0x4;
  const IPV6_PONG = 0x8;
  return (node.udp_addr_status & (IPV4_PONG | IPV6_PONG)) !== 0;
}
```

### 2.2 节点活跃度判断

#### **多维度评分模型**
```javascript
function calculateNodeActivity(node, currentTime) {
  let score = 0;
  
  // 1. 连接状态 (40分)
  if (node.udp_addr_status & 0x4) score += 20; // IPv4直连
  if (node.udp_addr_status & 0x8) score += 20; // IPv6直连
  
  // 2. 数据传输 (30分)
  if (node.in_bytes > 0 || node.out_bytes > 0) {
    const totalBytes = node.in_bytes + node.out_bytes;
    score += Math.min(30, Math.log10(totalBytes) * 5);
  }
  
  // 3. 时间新鲜度 (30分)
  const timeSinceUpdate = currentTime - node.ping_ts_sec;
  if (timeSinceUpdate < 60) score += 30;
  else if (timeSinceUpdate < 120) score += 20;
  else if (timeSinceUpdate < 300) score += 10;
  
  return {
    score: score,
    level: score > 80 ? "活跃" : score > 50 ? "一般" : "不活跃"
  };
}
```

### 2.3 连接质量评估

#### **综合质量指标**
```javascript
function evaluateConnectionQuality(node) {
  const quality = {
    latency: 0,      // 延迟得分
    stability: 0,    // 稳定性得分
    throughput: 0,   // 吞吐量得分
    overall: 0       // 综合得分
  };
  
  // 1. 延迟评分 (0-40分)
  const latency_ms = node.addr4_ping_latency_usec / 1000 || 
                     node.addr6_ping_latency_usec / 1000;
  if (latency_ms > 0) {
    if (latency_ms < 50) quality.latency = 40;
    else if (latency_ms < 100) quality.latency = 30;
    else if (latency_ms < 200) quality.latency = 20;
    else quality.latency = 10;
  }
  
  // 2. 稳定性评分 (0-30分)
  if (node.detect_count === 0) {
    quality.stability = 30;
  } else if (node.detect_count < 10) {
    quality.stability = 20;
  } else if (node.detect_count < 20) {
    quality.stability = 10;
  }
  
  // 3. 吞吐量评分 (0-30分)
  const totalTraffic = node.in_bytes + node.out_bytes;
  if (totalTraffic > 1024 * 1024) quality.throughput = 30;      // >1MB
  else if (totalTraffic > 100 * 1024) quality.throughput = 20;  // >100KB
  else if (totalTraffic > 10 * 1024) quality.throughput = 10;   // >10KB
  
  quality.overall = quality.latency + quality.stability + quality.throughput;
  
  return {
    ...quality,
    grade: quality.overall > 80 ? "A" :
           quality.overall > 60 ? "B" :
           quality.overall > 40 ? "C" : "D"
  };
}
```

### 2.4 网络拓扑健康度

#### **网络指标计算**
```javascript
function calculateNetworkHealth(nodes) {
  const total = nodes.length;
  const online = nodes.filter(n => isNodeOnline(n)).length;
  const direct = nodes.filter(n => (n.udp_addr_status & 0xC) !== 0).length;
  const avgLatency = nodes
    .map(n => n.addr4_ping_latency_usec || n.addr6_ping_latency_usec)
    .filter(l => l > 0)
    .reduce((sum, l) => sum + l, 0) / online / 1000; // 转换为ms
  
  return {
    onlineRate: (online / total * 100).toFixed(1) + "%",
    directRate: (direct / online * 100).toFixed(1) + "%",
    avgLatency: avgLatency.toFixed(1) + "ms",
    healthScore: Math.min(100, 
      (online / total * 50) + 
      (direct / online * 30) + 
      (Math.max(0, 200 - avgLatency) / 200 * 20)
    )
  };
}
```

### 2.5 异常检测规则

#### **异常类型定义**
```javascript
const ANOMALY_RULES = [
  {
    name: "完全失联",
    severity: "critical",
    check: (node) => node.detect_count >= 32,
    message: "节点探测失败次数达到上限"
  },
  {
    name: "高延迟",
    severity: "warning",
    check: (node) => {
      const latency = node.addr4_ping_latency_usec || node.addr6_ping_latency_usec;
      return latency > 200000; // 200ms
    },
    message: "节点延迟超过200ms"
  },
  {
    name: "长期无流量",
    severity: "info",
    check: (node, currentTime) => {
      const inactive = currentTime - node.ping_ts_sec > 600; // 10分钟
      const noTraffic = node.in_bytes === 0 && node.out_bytes === 0;
      return inactive && noTraffic;
    },
    message: "节点10分钟内无数据传输"
  },
  {
    name: "单向流量",
    severity: "warning",
    check: (node) => {
      return (node.in_bytes > 1000 && node.out_bytes === 0) ||
             (node.out_bytes > 1000 && node.in_bytes === 0);
    },
    message: "节点只有单向流量"
  },
  {
    name: "无可用地址",
    severity: "critical",
    check: (node) => {
      return node.detect_count > 0 && 
             node.static_address_list.num === 0 &&
             node.dynamic_address_list.num === 0 &&
             node.push_address_list.num === 0;
    },
    message: "节点没有任何可用地址"
  }
];

function detectAnomalies(node, currentTime) {
  return ANOMALY_RULES
    .filter(rule => rule.check(node, currentTime))
    .map(rule => ({
      nodeId: node.uuid64,
      type: rule.name,
      severity: rule.severity,
      message: rule.message,
      timestamp: currentTime
    }));
}
```

---

## 三、Map数据刷新机制与配置

### 3.1 数据更新频率

#### **核心时间常量**
```c
// 1. 进程心跳
GNB_CTL_KEEP_ALIVE_TS = 15秒          // map文件刷新间隔

// 2. 节点通信
GNB_NODE_PING_INTERVAL_SEC = 37秒     // PING发送间隔
GNB_NODE_UPDATE_INTERVAL_SEC = 75秒   // 节点超时判定(37*2+1)

// 3. 统一转发
GNB_UNIFIED_FORWARDING_NODE_EXPIRED_SEC = 15秒        // 转发节点过期
GNB_UNIFIED_FORWARDING_NODE_ARRAY_EXPIRED_SEC = 90秒  // 转发数组过期

// 4. 中继节点
GNB_LAST_RELAY_NODE_EXPIRED_SEC = 145秒  // 中继节点过期

// 5. 外部服务
GNB_EXEC_ES_INTERVAL_TIME_SEC = 300秒    // gnb_es执行间隔(5分钟)
```

#### **数据新鲜度等级**
```javascript
function getDataFreshness(timestamp, currentTime) {
  const age = currentTime - timestamp;
  
  if (age < 15) return { level: "实时", color: "green", reliability: 100 };
  if (age < 37) return { level: "新鲜", color: "blue", reliability: 90 };
  if (age < 75) return { level: "较新", color: "orange", reliability: 70 };
  if (age < 300) return { level: "陈旧", color: "red", reliability: 40 };
  return { level: "过期", color: "gray", reliability: 0 };
}
```

### 3.2 数据更新触发机制

#### **自动更新事件**
```
1. 进程主循环 (每秒)
   └─> 更新 keep_alive_ts_sec
   
2. 收到数据包
   ├─> 更新 in_bytes / out_bytes
   ├─> 更新 addr4_update_ts_sec / addr6_update_ts_sec
   └─> 计算 addr4_ping_latency_usec / addr6_ping_latency_usec

3. PING定时器 (每37秒)
   └─> 更新 ping_ts_sec
   
4. 地址发现
   ├─> dynamic_address_list (handle_detect_addr_frame)
   ├─> push_address_list (handle_push_addr_frame)
   └─> resolv_address_list (DNS解析异步)
   
5. 统一转发更新 (收到转发数据包时)
   └─> unified_forwarding_node_array
```

### 3.3 影响数据刷新的配置项

#### **命令行参数**
```bash
# 1. 基础配置
-b, --ctl-block <file>        # 指定map文件路径 (必需)
-c, --conf <dir>              # 配置目录
-i, --ifname <name>           # 虚拟网卡名称

# 2. 网络配置
-l, --listen <addr:port>      # 监听地址 (影响wan4_port/wan6_port)
-4, --ipv4-only              # 仅IPv4 (影响IPv6相关字段)
-6, --ipv6-only              # 仅IPv6 (影响IPv4相关字段)

# 3. 转发模式
-U, --unified-forwarding <mode>  # off/force/auto/super/hyper
                                 # 影响unified_forwarding_*字段

# 4. 日志级别 (影响更新频率)
-V, --verbose                # 详细模式
-T, --trace                  # 跟踪模式
```

#### **配置文件影响**
```
1. node.conf
   - uuid64, tun_addr4, tun_ipv6_addr
   - type (节点类型)
   
2. address.conf
   - static_address_block (静态地址列表)
   - resolv_address_block (需DNS解析的域名)
   
3. route.conf
   - route_node (路由配置)
   - selected_route_node
```

### 3.4 数据读取建议

#### **最佳实践**
```javascript
// 1. 检查进程状态
function checkMapValidity(statusZone, currentTime) {
  const age = currentTime - statusZone.keep_alive_ts_sec;
  if (age > 15) {
    console.warn(`Map数据可能过期: ${age}秒前更新`);
    return { valid: false, staleness: age };
  }
  return { valid: true, staleness: age };
}

// 2. 批量读取优化
function readMapData(mapFile) {
  // 使用mmap或一次性读取，避免频繁IO
  const buffer = fs.readFileSync(mapFile);
  
  // 验证magic number
  const magic = buffer.slice(0, 16);
  if (!validateMagic(magic)) {
    throw new Error("Invalid map file format");
  }
  
  return parseMapData(buffer);
}

// 3. 增量更新策略
const cache = new Map();
function updateNodeCache(nodeId, newData) {
  const cached = cache.get(nodeId);
  if (!cached || newData.ping_ts_sec > cached.ping_ts_sec) {
    cache.set(nodeId, newData);
    return { updated: true, changes: diffNode(cached, newData) };
  }
  return { updated: false };
}
```

#### **推荐轮询间隔**
```
实时监控面板:  5-10秒  (适中)
健康检查:      30-60秒 (推荐)
日志记录:      5分钟   (节省资源)
告警检测:      15秒    (与keep_alive同步)
```

---

## 四、可视化实现建议

### 4.1 数据展示维度

#### **概览视图**
```
┌─────────────────────────────────────┐
│  GNB 网络状态 Dashboard              │
├─────────────────────────────────────┤
│  在线节点: 9/11  (81.8%)            │
│  平均延迟: 131ms                     │
│  总流量: ↑ 56KB  ↓ 23KB             │
│  进程状态: ● 运行中 (2秒前更新)     │
└─────────────────────────────────────┘
```

#### **节点列表视图**
```
节点ID          | 虚拟IP         | 状态      | 延迟    | 流量
----------------|----------------|-----------|---------|----------
3764021915...   | 10.182.236.181 | 🟢 本地   | -       | ↑23KB ↓56KB
8283289760...   | 10.182.236.182 | 🟢 IPv4直连| 95.5ms  | ↑54KB ↓20KB
4997342800...   | 10.182.236.180 | 🟢 IPv6直连| 163.1ms | ↑588B ↓588B
6802325343...   | 10.182.236.179 | 🔴 失联   | -       | ↑0B ↓0B
```

#### **拓扑图视图**
```
建议使用D3.js或ECharts绘制:

中心节点(本地) ─── 直连节点1 (绿色实线)
     │          
     ├─── 直连节点2 (绿色实线)
     │
     └─── 中继节点 ─── 间接节点 (橙色虚线)
```

### 4.2 关键指标监控

#### **仪表盘指标**
```javascript
const dashboardMetrics = {
  // 1. 核心KPI
  onlineRate: "81.8%",           // 在线率
  avgLatency: "131ms",           // 平均延迟
  directConnRate: "88.9%",       // 直连率
  
  // 2. 流量统计
  totalInbound: "56.0KB",        // 总入站
  totalOutbound: "23.4KB",       // 总出站
  trafficRate: "2.4 KB/s",       // 实时速率
  
  // 3. 健康指标
  healthScore: 85,               // 健康评分(0-100)
  criticalNodes: 2,              // 严重问题节点数
  warningNodes: 1,               // 警告节点数
  
  // 4. 系统状态
  processUptime: "2h 34m",       // 进程运行时间
  lastUpdate: "2秒前",           // 最后更新
  mapFreshness: "实时"           // 数据新鲜度
};
```

#### **告警阈值配置**
```javascript
const alertThresholds = {
  latency: {
    warning: 200,      // 200ms
    critical: 500      // 500ms
  },
  detectCount: {
    warning: 10,       // 10次失败
    critical: 32       // 最大值
  },
  trafficStall: {
    duration: 600      // 10分钟无流量
  },
  processStale: {
    duration: 15       // keep_alive超时
  }
};
```

### 4.3 API接口设计

#### **RESTful API示例**
```javascript
// GET /api/v1/nodes
// 返回所有节点列表
{
  "timestamp": 1733234093,
  "nodes": [
    {
      "id": "8283289760467957",
      "ip": "10.182.236.182",
      "status": "online",
      "connection": "ipv4_direct",
      "latency": 95.5,
      "traffic": { "in": 21073, "out": 55793 },
      "lastSeen": 1733234053
    }
  ]
}

// GET /api/v1/nodes/:id
// 获取单个节点详情
{
  "id": "8283289760467957",
  "basic": { ... },
  "network": {
    "wan_address": "221.216.142.185:9016",
    "available_addresses": [ ... ]
  },
  "stats": {
    "latency": { "ipv4": 95530, "ipv6": 0 },
    "traffic": { "in": 21073, "out": 55793 }
  },
  "health": {
    "score": 85,
    "quality": "A",
    "anomalies": []
  }
}

// GET /api/v1/metrics/summary
// 获取网络摘要指标
{
  "network": {
    "total_nodes": 11,
    "online_nodes": 9,
    "health_score": 85
  },
  "performance": {
    "avg_latency_ms": 131,
    "total_traffic_kb": 79.4
  }
}

// GET /api/v1/alerts
// 获取告警列表
{
  "alerts": [
    {
      "severity": "critical",
      "type": "node_offline",
      "node_id": "6802325343720556",
      "message": "节点探测失败次数达到32次",
      "timestamp": 1733234053
    }
  ]
}
```

### 4.4 WebSocket实时推送

```javascript
// 连接WebSocket
const ws = new WebSocket('ws://localhost:8080/api/v1/stream');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  
  switch(data.type) {
    case 'node_update':
      updateNodeDisplay(data.node);
      break;
    case 'alert':
      showAlert(data.alert);
      break;
    case 'metrics':
      updateDashboard(data.metrics);
      break;
  }
};

// 推送格式
{
  "type": "node_update",
  "timestamp": 1733234093,
  "node": {
    "id": "8283289760467957",
    "changes": {
      "latency": { "old": 95000, "new": 98000 },
      "traffic": { "in": 21073, "out": 55793 }
    }
  }
}
```

---

## 五、技术实现参考

### 5.1 解析Map文件

#### **C/C++ 实现**
```c
#include "gnb_ctl_block.h"

// 读取map文件
gnb_ctl_block_t* load_map(const char *path) {
    return gnb_get_ctl_block(path, 0);  // 0 = readonly
}

// 获取节点列表
void list_nodes(gnb_ctl_block_t *ctl) {
    int node_num = ctl->node_zone->node_num;
    for (int i = 0; i < node_num; i++) {
        gnb_node_t *node = &ctl->node_zone->node[i];
        printf("Node %llu: %s\n", node->uuid64, 
               is_online(node) ? "online" : "offline");
    }
}

// 在线判断
int is_online(gnb_node_t *node) {
    return (node->udp_addr_status & 0xC) != 0;  // IPv4_PONG | IPv6_PONG
}
```

#### **Python实现**
```python
import struct
import mmap

class GNBMapReader:
    def __init__(self, map_path):
        self.map_path = map_path
        self.load()
    
    def load(self):
        with open(self.map_path, 'r+b') as f:
            self.mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
            self.parse_header()
            self.parse_nodes()
    
    def parse_header(self):
        # 跳过entry_table和magic_number
        offset = 256 * 4 + 16
        # 读取conf_zone, core_zone, status_zone
        # ...实现细节
    
    def get_node(self, node_id):
        return self.nodes.get(node_id)
    
    def get_online_nodes(self):
        return [n for n in self.nodes.values() if self.is_online(n)]
    
    @staticmethod
    def is_online(node):
        return (node['udp_addr_status'] & 0xC) != 0

# 使用示例
reader = GNBMapReader('/path/to/gnb.map')
online = reader.get_online_nodes()
print(f"Online nodes: {len(online)}")
```

#### **Go实现**
```go
package gnbmap

import (
    "encoding/binary"
    "os"
    "syscall"
)

type MapReader struct {
    data []byte
    nodes []Node
}

func (m *MapReader) Load(path string) error {
    f, err := os.Open(path)
    if err != nil {
        return err
    }
    defer f.Close()
    
    stat, _ := f.Stat()
    m.data, err = syscall.Mmap(int(f.Fd()), 0, int(stat.Size()),
        syscall.PROT_READ, syscall.MAP_SHARED)
    
    return m.parse()
}

func (m *MapReader) GetOnlineNodes() []Node {
    var online []Node
    for _, node := range m.nodes {
        if node.UdpAddrStatus & 0xC != 0 {
            online = append(online, node)
        }
    }
    return online
}
```

### 5.2 Web前端实现

#### **React + TypeScript**
```typescript
// types.ts
export interface GNBNode {
  uuid64: string;
  tun_addr4: string;
  tun_ipv6_addr: string;
  udp_addr_status: number;
  in_bytes: number;
  out_bytes: number;
  addr4_ping_latency_usec: number;
  addr6_ping_latency_usec: number;
  detect_count: number;
  ping_ts_sec: number;
}

// NodeList.tsx
import React, { useEffect, useState } from 'react';

export const NodeList: React.FC = () => {
  const [nodes, setNodes] = useState<GNBNode[]>([]);
  
  useEffect(() => {
    const fetchNodes = async () => {
      const res = await fetch('/api/v1/nodes');
      const data = await res.json();
      setNodes(data.nodes);
    };
    
    fetchNodes();
    const interval = setInterval(fetchNodes, 5000);
    return () => clearInterval(interval);
  }, []);
  
  return (
    <table>
      <thead>
        <tr>
          <th>节点ID</th>
          <th>状态</th>
          <th>延迟</th>
          <th>流量</th>
        </tr>
      </thead>
      <tbody>
        {nodes.map(node => (
          <NodeRow key={node.uuid64} node={node} />
        ))}
      </tbody>
    </table>
  );
};

// NodeRow.tsx
const NodeRow: React.FC<{ node: GNBNode }> = ({ node }) => {
  const isOnline = (node.udp_addr_status & 0xC) !== 0;
  const latency = node.addr4_ping_latency_usec / 1000;
  
  return (
    <tr className={isOnline ? 'online' : 'offline'}>
      <td>{node.uuid64}</td>
      <td>
        <StatusBadge status={isOnline ? 'online' : 'offline'} />
      </td>
      <td>{latency.toFixed(1)}ms</td>
      <td>↑{formatBytes(node.out_bytes)} ↓{formatBytes(node.in_bytes)}</td>
    </tr>
  );
};
```

#### **Vue 3 + Composition API**
```vue
<!-- NodeDashboard.vue -->
<template>
  <div class="dashboard">
    <div class="metrics">
      <MetricCard title="在线节点" :value="onlineCount" :total="totalCount" />
      <MetricCard title="平均延迟" :value="avgLatency + 'ms'" />
      <MetricCard title="健康评分" :value="healthScore" />
    </div>
    
    <NodeTable :nodes="nodes" @select="onNodeSelect" />
    
    <NodeDetail v-if="selectedNode" :node="selectedNode" />
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useGNBMap } from '@/composables/useGNBMap';

const { nodes, loading, error, refresh } = useGNBMap();

const onlineCount = computed(() => 
  nodes.value.filter(n => (n.udp_addr_status & 0xC) !== 0).length
);

const avgLatency = computed(() => {
  const latencies = nodes.value
    .map(n => n.addr4_ping_latency_usec || n.addr6_ping_latency_usec)
    .filter(l => l > 0);
  return (latencies.reduce((a, b) => a + b, 0) / latencies.length / 1000).toFixed(1);
});

let intervalId: number;
onMounted(() => {
  refresh();
  intervalId = setInterval(refresh, 5000);
});

onUnmounted(() => clearInterval(intervalId));
</script>
```

### 5.3 命令行工具实现

#### **Shell脚本**
```bash
#!/bin/bash
# gnb_monitor.sh - GNB节点监控脚本

GNB_CTL="/usr/local/bin/gnb_ctl"
MAP_FILE="/usr/local/opt/mynet/driver/gnb/conf/*/gnb.map"

# 检查在线节点
check_online() {
    local output=$($GNB_CTL -s -b $MAP_FILE -o 2>/dev/null)
    local online_count=$(echo "$output" | grep -c "Direct Point to Point")
    local total_count=$(echo "$output" | grep -c "^node ")
    
    echo "在线: $online_count/$total_count"
}

# 检查异常节点
check_anomalies() {
    local output=$($GNB_CTL -s -b $MAP_FILE 2>/dev/null)
    
    # 检查失联节点 (detect_count = 32)
    echo "$output" | grep "detect_count 32" | while read line; do
        local node_id=$(echo "$line" | grep -oP 'node \K\d+')
        echo "⚠️  节点 $node_id 已失联"
    done
    
    # 检查高延迟节点 (> 200ms)
    echo "$output" | grep -E "addr4_ping_latency_usec [0-9]{6,}" | while read line; do
        local node_id=$(echo "$line" | grep -oP 'node \K\d+')
        local latency=$(echo "$line" | grep -oP 'addr4_ping_latency_usec \K\d+')
        local latency_ms=$((latency / 1000))
        if [ $latency_ms -gt 200 ]; then
            echo "⚠️  节点 $node_id 高延迟: ${latency_ms}ms"
        fi
    done
}

# 主循环
while true; do
    clear
    echo "=== GNB 节点监控 ==="
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    check_online
    echo ""
    echo "异常检测:"
    check_anomalies
    echo ""
    echo "按 Ctrl+C 退出"
    sleep 10
done
```

---

## 六、完整实现示例 (Node.js + Express)

```javascript
// server.js
const express = require('express');
const { spawn } = require('child_process');
const app = express();

const GNB_CTL = '/usr/local/bin/gnb_ctl';
const MAP_FILE = '/usr/local/opt/mynet/driver/gnb/conf/3764021915150630/gnb.map';

// 解析gnb_ctl输出
function parseGnbCtlOutput(output) {
  const nodes = [];
  const blocks = output.split('====================\n').slice(1);
  
  blocks.forEach(block => {
    const node = {};
    const lines = block.split('\n');
    
    lines.forEach(line => {
      const match = line.match(/^(\w+)\s+(.+)$/);
      if (match) {
        const [, key, value] = match;
        if (key === 'node') {
          node.uuid64 = value;
        } else if (key === 'tun_ipv4') {
          node.tun_addr4 = value;
        } else if (key === 'addr4_ping_latency_usec') {
          node.latency = parseInt(value);
        } else if (key === 'in') {
          node.in_bytes = parseInt(value.split(' ')[0]);
        } else if (key === 'out') {
          node.out_bytes = parseInt(value.split(' ')[0]);
        } else if (line.includes('Direct Point to Point')) {
          node.status = 'online';
          node.connection = line.includes('ipv4') ? 'ipv4' : 'ipv6';
        }
      }
    });
    
    if (node.uuid64) nodes.push(node);
  });
  
  return nodes;
}

// API端点
app.get('/api/v1/nodes', (req, res) => {
  const gnbCtl = spawn(GNB_CTL, ['-s', '-b', MAP_FILE]);
  let output = '';
  
  gnbCtl.stdout.on('data', data => output += data);
  gnbCtl.on('close', () => {
    const nodes = parseGnbCtlOutput(output);
    res.json({
      timestamp: Math.floor(Date.now() / 1000),
      nodes: nodes
    });
  });
});

app.get('/api/v1/metrics/summary', (req, res) => {
  // ... 实现汇总指标
});

app.listen(3000, () => {
  console.log('GNB Dashboard API listening on port 3000');
});
```

---

## 七、监控部署建议

### 7.1 系统架构

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│  GNB进程    │──▶   │ gnb.map文件  │──▶   │ 监控服务    │
│  (C程序)    │      │  (共享内存)  │      │ (API Server)│
└─────────────┘      └──────────────┘      └─────────────┘
                            │                      │
                            │                      ▼
                            │              ┌─────────────┐
                            └──────────▶   │  Web前端    │
                                          │ (Dashboard) │
                                          └─────────────┘
```

### 7.2 性能优化

1. **使用mmap读取**: 避免完整文件读取
2. **增量更新**: 只更新变化的节点
3. **缓存策略**: Redis缓存频繁访问的数据
4. **WebSocket**: 实时推送而非轮询
5. **数据压缩**: gzip压缩API响应

### 7.3 安全建议

1. **只读访问**: gnb_ctl使用readonly模式打开map
2. **权限控制**: API添加认证机制
3. **限流**: 防止频繁查询
4. **敏感信息**: 不暴露密钥字段

---

## 八、附录

### 8.1 快速检查清单

```
✅ 进程状态: keep_alive_ts_sec < 15秒
✅ 节点在线: udp_addr_status & 0xC != 0
✅ 连接质量: latency < 200ms && detect_count < 10
✅ 数据新鲜: ping_ts_sec 在最近37秒内更新
✅ 地址可用: available_address_list.num > 0
```

### 8.2 常见问题排查

| 问题 | 检查项 | 解决方案 |
|------|--------|----------|
| map文件读取失败 | 文件权限、进程运行状态 | `chmod 644 gnb.map` |
| 节点状态不更新 | keep_alive_ts_sec | 检查GNB进程是否正常 |
| 所有节点离线 | wan4_port/wan6_port | 检查网络配置 |
| 延迟为0 | udp_addr_status | 节点未建立连接 |

### 8.3 参考资源

- GNB源码: https://github.com/gnbdev/opengnb
- 官方文档: `src/docs/gnb_user_manual_cn.md`
- 诊断工具: `src/docs/gnb_diagnose_cn.md`

---

**文档版本**: v1.0
**最后更新**: 2025-12-03
**适用版本**: OpenGNB 1.6.0+
