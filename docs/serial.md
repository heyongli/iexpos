# 串口子系统 — iexpos

## 硬件

| 项目 | 值 |
|------|-----|
| UART | 16550A 兼容 (QEMU 模拟) |
| 基址 (COM1) | 0x3F8 |
| IRQ | IRQ 4 (当前未使用，轮询模式) |
| 默认波特率 | SeaBIOS 设定 115200 (QEMU 默认) |

## 寄存器布局 (COM1 基址 0x3F8)

| 偏移 | DLAB=0 读 | DLAB=0 写 | DLAB=1 读/写 |
|------|-----------|-----------|--------------|
| +0 (0x3F8) | RBR (接收缓冲) | THR (发送保持) | DLL (除数低字节) |
| +1 (0x3F9) | IER (中断使能) | IER | DLM (除数高字节) |
| +2 (0x3FA) | IIR (中断标识) | FCR (FIFO 控制) | — |
| +3 (0x3FB) | LCR (线控制) | LCR | LCR |
| +4 (0x3FC) | MCR (调制解调器控制) | MCR | MCR |
| +5 (0x3FD) | LSR (线状态) | — | — |
| +6 (0x3FE) | MSR (调制解调器状态) | — | — |

**关键寄存器**：
- **COM1+5 / LSR**：Bit 0 = Data Ready (DR)，Bit 5 = THR Empty (THRE)，Bit 6 = Transmitter Empty (TEMT)
- **COM1+4 / MCR**：Bit 4 = Loopback (LOOP)，置 1 时 TX 内部连接至 RX
- **COM1+3 / LCR**：Bit 7 = DLAB，置 1 时访问 +0/+1 变为波特率除数

## 读写函数

两个变体分别用于控制台和 GDB stub，但最终都走同样的 `outb`/`inb` 汇编：

### 控制台 (`console.c`)

```c
static void serial_write(const char *s, int len) {
    for (int i = 0; i < len; i++)
        __asm__ volatile("outb %0, %1"
            : : "a"((unsigned char)s[i]), "Nd"((unsigned short)0x3F8));
}
```

- 写操作：直接 `outb` 到 THR，**不检查** LSR.THRE
- 批量写入依赖 16550A 的 16 字节 TX FIFO 防止溢出
- 无读操作（控制台为只写）

### GDB stub (`gdb_stub.c`)

```c
static void serial_out(char c) {
    __asm__ volatile("outb %0, %1"
        : : "a"((unsigned char)c), "Nd"((unsigned short)COM1));
}

static char serial_in(void) {
    unsigned char lsr;
    do {
        __asm__ volatile("inb %1, %0" : "=a"(lsr) : "Nd"((unsigned short)0x3FD));
    } while (!(lsr & 1));
    unsigned char c;
    __asm__ volatile("inb %1, %0" : "=a"(c) : "Nd"((unsigned short)COM1));
    return c;
}
```

- `serial_out`：同上直接写 THR，不检查 THRE
- `serial_in`：**忙等** LSR.DR 置位后读 RBR，读后自动清除 DR
- 这套函数在 GDB 协议上下文中也用于发送 `$T05`/接收 GDB 命令包

## Loopback 自测 (`serial_rw_test`)

位于 `gdb_stub.c`，在 `gdb_stub_init()` 后调用。

```
MCR ← 0x10           ; 启用 Loopback
循环 4 次:
  THR ← test_byte    ; 写已知字节
  等待 LSR.DR         ; 等字节自环到接收缓冲
  RBR → got          ; 读回对比
MCR ← 0x00           ; 关闭 Loopback
输出 SRW:P/F          ; 标记
```

测试字节 `0x55, 0xAA, '!', '\n'` 覆盖交替位及 ASCII 边界。

## 调试实录

### 串口 RX 不通 — MCR Loopback

**现象**：向 TCP 串口发送字节，内核 `gdb_poll()` 检查 LSR.DR 始终为 0。同样字节会在 TCP 侧回显，表明 UART 处于自环模式。

**根因**：16550A MCR (0x3FC) bit 4 (LOOP) 默认为 1。内部 TX→RX 短接，来自 chardev 的 RX 信号被隔离，外部数据无法进入 RBR。

排查经过：

1. 在 `gdb_poll` 中每 1 000 000 轮输出一次 LSR → 稳定出现 `#60`（DR=0, THRE=1, TEMT=1）
2. 对照 16550A 手册确认状态合法但无 RX 数据
3. 检查 MCR 发现 bit 4 = 1
4. 写入 `outb(0, 0x3FC)` 清除后 DR 正常翻转

```c
void gdb_stub_init(void) {
    outb(0, 0x3FC);  // 清除 MCR.LOOP
    // ...
}
```

**教训**：SeaBIOS/QEMU 可能遗留自环状态，串口初始化时必须显式清除 MCR。调试时应先输出 LSR 全貌定位，不只盯 DR 位。

### gdb_poll 不应消费 RBR

**现象**：触发 INT3 后 `$T05` 能发出，但之后 stub 卡死，不再响应。

**根因**：`gdb_poll` 在触发 INT3 前执行了 `serial_in()`，将触发字节从 RBR 读走。INT3 处理函数中 `gdb_recv()` 再调用 `serial_in()` 时 RBR 已空，永久阻塞。

```c
// 错误: 先消费了触发字节
void gdb_poll(void) {
    if (inb(0x3FD) & 1) {
        char c = serial_in();  // 字节被读走
        __asm__ volatile("int $3");
        // gdb_recv() 再也读不到任何字节
    }
}
```

**解决**：`gdb_poll` 只检查 LSR.DR，不访问 RBR。触发字节由 `gdb_recv()` 在 `while ((c = serial_in()) != '$')` 中自行读取并丢弃。

### 串口读写稳定性验证

**问题**：确认 `outb`/`inb` 确实能读写 UART，且无 FIFO 丢数。

**方法**：利用 loopback 做闭环测试：
1. MCR = 0x10 启用自环
2. 写 4 字节到 THR，对每字节等待 LSR.DR，读 RBR 对比
3. MCR = 0x00 关闭自环
4. 输出 `SRW:P/F` 标记

验证通过后，进一步通过 TCP 全双工测试确认 TX 和 RX 可同时工作（GDB 协议双向通信）。

## 调试串口标记

| 串口输出 | 含义 | 缺失原因 |
|----------|------|----------|
| `PMOK` | entry.asm PM 切换成功 | GDT/CR0/far jump 错误 |
| `entry` | setup_main 已运行 | extern 或 `-e entry` 问题 |
| `vga init done` | vga.init() 返回 | PCI/VBE 挂起或 VGA 寄存器问题 |
| `Graphics init OK` | 控制台缓冲正常 | 字体渲染崩溃或缓冲溢出 |

`bm_puts()` 在 bm_init 前后都能用，适合早期调试埋点。

## 测试覆盖

| 测试文件 | 验证点 | 手段 |
|----------|--------|------|
| `tests/serial.sh` | 写通路 (PMOK, entry, ...) | 抓串口输出 `grep` 关键字 |
| `tests/serial-rw.sh` | 读写闭环 (loopback) | `grep SRW:P` |
| `tests/gdb-over-serial-protocol.sh` | 串口全双工 + GDB 协议 | Python socket `?`/`g`/`m`/`M`/`P`/`c` 包交互 |
