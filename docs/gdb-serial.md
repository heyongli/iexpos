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

---

## 调试实录 (最耗时的 Bug)

### 1. 串口 I/O 误用内存访问（耗时最长）

**现象**：`gdb_break()` 调用后内核完全卡死，无任何串口输出。

**根因**：x86 GCC 中 `*(volatile unsigned char *)0x3F8 = c` 生成的是 `mov` 指令（内存访问）而非 `outb`（端口 I/O）。I/O 端口 0x3F8 属于独立的 I/O 地址空间，不能用内存指令访问。所有 stub 内的串口读写都在操作内存地址 0x3F8（恰好落在实模式 IVT 区域或保护模式未映射区域），而不操作真正的 UART。

**解决**：全部替换为内联汇编 `__asm__ volatile("outb %0, %1" : : "a"(c), "Nd"(0x3F8))` 和 `__asm__ volatile("inb %1, %0" : "=a"(v) : "Nd"(0x3FD))`。

**教训**：不要相信 `volatile` 指针能生成端口 I/O；x86 上必须显式使用 `in`/`out` 指令。

### 2. KVM 下 I/O 读循环极慢

**现象**：`gdb_break()` 中 2 000 000 次 `inb(0x3FD)` 循环需要数秒甚至更长。

**根因**：KVM 下每次 `inb` 都会触发 VM‑exit，开销 ~5–100 µs。2 M 次即可达 10 s+，导致内核在等待 GDB 超时前就被外部 `timeout` 杀掉。

**解决**：改用纯内存计数器循环，每 65 536 次迭代才检查一次 LSR。600 M 次内存迭代 + ~9 k 次 I/O 读 ≈ ~6 s 总超时，正常启动时仍可接受。

### 3. `-nographic` 模式下 DR 误触发

**现象**：`gdb_break()` 读 LSR 发现 DR=1，执行 `int $3`，GDB handler 等待串口命令永远不返回。

**根因**：QEMU `-nographic` 将串口连接到终端 stdin。终端上任何数据（包括 shell pipe 残余、按键等）都会设置 UART 的 Data Ready 位。

**解决**：测试场景改用 `-serial tcp:<PORT>,server,nowait` 隔离串口与终端。`gdb_break()` 先 drain 接收缓冲再检查，避免误触发。

### 4. 内核体积超出引导扇区加载能力

**现象**：串口只输出 `PMOK`，之后无任何输出（内核未加载完整）。

**根因**：GDB stub 使 kernel.bin 达到 37 扇区，但 boot 扇区的 DAP 只加载 30 扇区。后 7 扇区未加载，代码执行到缺失部分即崩溃。

**解决**：`boot/boot.asm` 中 DAP block count 从 30 改为 40。

### 5. MCR Loopback 导致串口 RX 不通

详见 `docs/serial.md` §调试实录。

### 6. `gdb_poll` 错误消费触发字节

**现象**：触发 INT3 后 GDB handler 卡死在 `serial_in()` 中，`$T05` 能发出但之后不发任何数据。

**根因**：`gdb_poll()` 在调用 `int $3` 前通过 `serial_in()` 读走了串口触发字节（`+`）。`gdb_handler` 中的 `gdb_recv()` 再调用 `serial_in()` 时 RBR 已空，导致永久阻塞。

**解决**：`gdb_poll` 只检查 LSR.DR 位，不消费字节。INT3 触发后由 `gdb_recv()` 自行读取 RBR。触发字节（如 `+`）会在 `gdb_recv()` 的 `while ((c = serial_in()) != '$')` 循环中被丢弃，不影响后续协议。

### 7. 软件 `int $3` 的 EIP 偏移不应执行

**现象**：continue 后内核崩溃或行为异常。

**根因**：`gdb_handler` 无条件执行 `r->eip--`。对于 0xCC 断点（CPU 将 EIP 指向断点的下一条指令），需要减 1 以重新执行断点处的指令。但对于 `gdb_poll` 中主动执行的 `__asm__("int $3")`，EIP 已指向 `int $3` 的下一条指令，不应该再减。

**解决**：引入 `gdb_from_poll` 标志，仅在非 poll 触发的 INT3 时执行 `r->eip--`：

```c
// gdb_poll: 软件 int3，不需 EIP 回退
void gdb_poll(void) {
    if (inb(0x3FD) & 1) {
        gdb_active = 1;  gdb_from_poll = 1;
        __asm__ volatile("int $3");
        gdb_from_poll = 0;  gdb_active = 0;
    }
}
// gdb_handler: 0xCC 断点时回退，poll 触发的跳过
if (!gdb_from_poll) r->eip--;
```

### 串口调试方法论总结

| 操作 | 工具/方法 |
|------|-----------|
| 检查 UART 状态 | 在关键路径加 LSR 全量输出（`serial_out(hex(lsr & 0xFF))`） |
| 检查 loopback | 读 MCR (0x3FC) bit 4 |
| 检查 RX 通路 | 写测试数据到 chardev，确认 LSR.DR 翻转 + RBR 可读 |
| 检查 TX 通路 | `serial_out` 写字节，确认 TCP 侧收到 |
| 测试完整协议 | Python `socket` 模拟 GDB client：`+` → 等 `$T05` → `+$c#63` → 确认回复 `+`

## 调试示例

### 启动步骤

**终端 1** — 启动 QEMU (串口重定向到 TCP):
```bash
qemu-system-x86_64 \
  -enable-kvm -m 2G -nographic -smp 2 -vga std \
  -drive file=build/vm-raw.img,format=raw \
  -net none \
  -serial tcp::12346,server,nowait
```

**终端 2** — 使用 Python 模拟 GDB 客户端:
```python
import socket, time

s = socket.socket()
s.connect(('localhost', 12346))
s.settimeout(10)

# 等待内核启动
buf = b''
while b'Graphics test complete' not in buf:
    d = s.recv(4096)
    if not d: break
    buf += d

# 发送触发字符
s.sendall(b'+')
time.sleep(0.5)

# 读取响应
resp = s.recv(4096)
print(f"Response: {resp}")
```

**终端 2** — 或使用 GDB 连接串口:

方法 A: 用 socat 创建虚拟串口:
```bash
# 终端 2: 创建 pty 桥接
socat PTY,link=/tmp/gdb-serial,rawer TCP:localhost:12346 &

# 终端 3: GDB 连接 pty
gdb build/kernel.elf
(gdb) target remote /tmp/gdb-serial
(gdb) break setup_main
(gdb) continue
```

方法 B: 用 Python 测试串口通信 (推荐):
```python
import socket, time

s = socket.socket()
s.connect(('localhost', 12346))
s.settimeout(10)

# 等待内核启动
buf = b''
while b'Graphics test complete' not in buf:
    d = s.recv(4096)
    if not d: break
    buf += d

# 发送触发字符
s.sendall(b'+')
time.sleep(0.5)

# 读取响应
resp = s.recv(4096)
print(f"Response: {resp}")
```

### 串口 GDB 协议

内核中的 GDB stub 实现了最小 Remote Serial Protocol:

```
# 状态查询
GDB → stub:  $?#00             # 查询状态
stub → GDB:  $S05#00           # SIGTRAP (已停止)

# 继续执行
GDB → stub:  $c#00             # continue
stub → GDB:  $OK#00

# 读寄存器
GDB → stub:  $g#00             # 读全部寄存器
stub → GDB:  $00000000...#72   # 72 字节 hex

# 读内存
GDB → stub:  $m7e00,10#00     # 读 0x7E00 起 16 字节
stub → GDB:  $0f...#00        # hex 编码数据
```

### GDB 命令行工具

使用 socat 创建虚拟串口连接:
```bash
# 安装 socat
sudo apt install socat

# 创建 pty 桥接
socat PTY,link=/tmp/gdb-serial,rawer TCP:localhost:12346 &

# GDB 连接 pty
gdb build/kernel.elf
(gdb) target remote /tmp/gdb-serial
(gdb) break setup_main
(gdb) continue
```

### 检查串口状态

在内核代码中添加调试输出:
```c
// 检查 LSR 状态
unsigned char lsr;
__asm__ volatile("inb %1, %0" : "=a"(lsr) : "Nd"(0x3FD));
bm_puts("LSR: 0x");
bm_put_hex(lsr);
bm_puts("\n");
```

### 常见问题

**串口收不到数据?**
```bash
# 检查串口配置
stty -F /dev/ttyS0 115200 cs8 -cstopb -parenb

# 检查权限
ls -l /dev/ttyS0
sudo chmod 666 /dev/ttyS0
```

**如何在真机上调试?**
1. 使用 USB-to-Serial 适配器连接目标机串口
2. 在目标机上运行 iexpos
3. 在主机上使用 GDB 连接串口
4. 设置断点、单步调试
