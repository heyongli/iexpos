# GDB stub 自实现 — iexpos

> 不依赖 QEMU，在真机上通过串口提供 GDB 调试能力。

需要在内核中嵌入一个 GDB stub，通过**串口**与 GDB 通信，协议为 GDB Remote Serial Protocol。

## 需要实现的最小功能集

GDB 通过串口发送 `$packet#checksum` 格式的请求，stub 回复 `$reply#checksum`。

| 命令 | 方向 | 作用 |
|------|------|------|
| `?` | 查询 | 返回目标当前状态 (`S05` = SIGTRAP) |
| `c` | 继续 | 恢复执行 (需要能响应后续断点) |
| `s` | 单步 | 设置 EFLAGS.TF, 恢复执行 |
| `g` | 读寄存器 | 返回所有 CPU 寄存器 (eax, ecx, ..., eip, eflags, seg regs) |
| `G` | 写寄存器 | 恢复保存的寄存器值 |
| `m addr,len` | 读内存 | 返回 `addr` 起始 `len` 字节的 hex 编码 |
| `M addr,len:...` | 写内存 | 写入 hex 数据到内存 |
| `Z0,addr,kind` | 设软件断点 | 保存原字节, 写 `0xCC`(INT3) 到 `addr` |
| `z0,addr,kind` | 删软件断点 | 恢复原字节 |
| `k` | 杀死 | 复位/停机 |

## 需要的内核基础设施

```
异常处理 (IDT)
├── INT1 (单步) → save registers → rep "S05" via serial → wait GDB command
├── INT3 (断点) → save registers → restore original byte at address
│               → single-step past it → re-insert 0xCC → rep "S05"
│               → wait GDB command
└── INT3 handler entry: pushfd / pusha / mov eax,cr2 / push eax → call c_stub

串口收发 (COM1)
├── 接收: 轮询或 IRQ4, 直到收到 '$', 累加直到 '#', 校验 checksum
├── 发送: "S05", 附 '$' 前缀 + '#' + 2 hex checksum
└── ACK: 收到 '+' 继续, 收到 '-' 重发

注册保存
├── 断点表: 32 条目, 每项 { addr, saved_byte, active }
├── breakpoint_insert(addr): 读原字节 → 存表 → 写 0xCC
└── breakpoint_remove(addr): 读表 → 写回原字节 → 清表项
```

## 最小串口协议交互示例

```
GDB → stub:    $?#00                 (查询状态)
stub → GDB:    $S05#00               (SIGTRAP, 停下)

GDB → stub:    $g#00                 (读寄存器)
stub → GDB:    $00000000....#00      (72 字节 hex: 全部寄存器)

GDB → stub:    $m7e00,10#00          (读 0x7E00 起 16 字节)
stub → GDB:    $0f....#00            (hex 编码的内存内容)

GDB → stub:    $Z0,888f,1#00         (在 0x888f 设 INT3 断点)
stub → GDB:    $OK#00

GDB → stub:    $c#00                 (继续执行)
```

## 估算工作量

| 模块 | 代码量 | 难度 |
|------|--------|------|
| IDT 异常处理 (INT1/INT3) | ~20 行 asm | 低 |
| 串口收发 + checksum | ~40 行 C | 低 |
| GDB 命令解析/回复 | ~80 行 C | 中 |
| 寄存器打包/解包 | ~60 行 C | 中 |
| 断点表管理 | ~30 行 C | 低 |
| 单步逻辑 (TF + restore + re-insert) | ~30 行 C | 高 |

总计 ~260 行。GDB Remote Serial Protocol 的完整参考见
[dev.ti.com/gdb_remote_protocol](https://dev.ti.com/gdb_remote_protocol)。
