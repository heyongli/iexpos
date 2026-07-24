# GDB (via QEMU) — iexpos

## 改动内容

| 改动 | 文件 | 作用 |
|------|------|------|
| `-g` 加入 CFLAGS | Makefile:4 | 所有 .c 编译带 DWARF 调试符号 |
| `build/kernel.elf` 链接目标 | Makefile:44-45 | 不压成 binary, 保留 ELF 节区 + 符号表 |
| `make gdb-qemu` 目标 | Makefile:60-64 | QEMU 加 `-s -S` 启动 GDB server + 冻结 CPU |
| `gdb-qemu.gdb` 脚本 | tests/gdb-qemu.gdb:1-4 | 自动加载 ELF + 连接 + 断点 setup_main + 放行 |
| 文档 | docs/gdb-qemu.md | 用法 / 符号地址 / gdb-qemu.gdb 说明 |

## 支持的功能

- 源码级断点: `break setup_main`, `break bm_init`, `break demo_orbit`
- 单步执行: `step` (进入函数), `next` (跳过函数), `finish` (跳出)
- 查看变量: `print var`, `print *fb`, `print cols[0]`
- 查看寄存器: `info registers`, `print $eax`
- 查看内存: `x/16wx 0xB8000`, `x/s 0x7E00`
- 反汇编: `disas`, `layout asm` (TUI 模式)
- 函数列表: `info functions`
- 源代码浏览: `list`, `list setup.c:50`

不支持: 用户态 syscall 调试、多核同步调试（未涉及）。

## 用法

终端 1 — 启动 QEMU + GDB server:
```bash
make gdb-qemu
# QEMU 停在第一条指令, 等待 GDB 连接 (端口 1234)
```

终端 2 — 启动 GDB:
```bash
gdb -x tests/gdb-qemu.gdb  # 自动加载 ELF + 连接 + 停 setup_main
```

或手动连接:
```bash
gdb build/kernel.elf
(gdb) target remote localhost:1234
(gdb) break setup_main
(gdb) continue
```

进入交互调试后:
```
Breakpoint 1, setup_main () at kernel/setup.c:6
(gdb) list
(gdb) next
(gdb) print bm_ui_width()
(gdb) continue
```

## gdb-qemu.gdb 逐行说明

| 命令 | 作用 |
|------|------|
| `file build/kernel.elf` | 加载符号 (含 DWARF 源码级调试) |
| `set architecture i386:x86-64` | 64-bit QEMU 需匹配架构 |
| `target remote :1234` | 连接 QEMU GDB server |
| `hbreak setup_main` | 硬件断点 (兼容 KVM) |
| `continue` | 放行到断点 |

## 关键符号地址

| 符号 | 地址 | 说明 |
|------|------|------|
| `entry` | `0x7E00` | entry.asm 第一条指令 |
| `setup_main` | kernel/setup.c | C 入口 (建议首断点) |
| `bm_init` | bmX86/vga.c | PCI/VBE/VGA 初始化 |
| `demo_orbit` | demos/orbit.c | orbit 动画入口 |

## 测试

```bash
tests/gdb-qemu.sh   # 自动构建 + QEMU + GDB 单步跟踪 (需安装 gdb)
```

测试步骤:
1. 启动 QEMU (`-s -S`), 等待 GDB 连接
2. GDB 加载 `kernel.elf` → 连接 `:1234` → `hbreak setup_main` (硬件断点)
3. 放行到断点, 打印 backtrace
4. 单步一次 (`step`)
5. 放行到结束, 校验串口含 `Graphics test complete`
6. 如果系统无 `gdb` 命令则自动跳过

## 原理

内核无需任何 GDB stub、调试 monitor 或特殊 payload。调试能力完全来自 QEMU:

| 组件 | 负责 |
|------|------|
| QEMU `-s` | 内置 GDB server stub, 暴露 CPU 寄存器 + 内存, 处理断点 |
| QEMU `-S` | 启动时冻结 CPU, 等 GDB `continue` 才运行 |
| `kernel.elf` (DWARF) | 将源码行号 → 映射到 QEMU 内存地址 (0x7E00+) |
| GDB | 读取 ELF 符号, 通过 `:1234` 与 QEMU 通信, 实现源码级调试 |

所以内核就是一个普通 flat binary，不用加任何调试代码。

## 不依赖 QEMU — 自实现 GDB stub

如果要在**真机**上调试（无 QEMU GDB server），需要在内核中嵌入一个 GDB stub，
通过**串口**与 GDB 通信，协议为 GDB Remote Serial Protocol。

### 需要实现的最小功能集

GDB 通过串口发送 `$packet#checksum` 格式的请求，stub 回复 `$reply#checksum`。

| 命令 | 方向 | 作用 |
|------|------|------|
| `?` | 查询 | 返回目标当前状态 (`S05` = SIGTRAP) |
| `c` | 继续 | 恢复执行 (需要能响应后续断点) |
| `s` | 单步 | 设置 EFLAGS.TF, 恢复执行 |
| `g` | 读寄存器 | 返回所有 CPU 寄存器 (eax, ecx, ..., eip, eflags, seg regs) |
| `G` | 写寄存器 | 恢复保存的寄存器 值 |
| `m addr,len` | 读内存 | 返回 `addr` 起始 `len` 字节的 hex 编码 |
| `M addr,len:...` | 写内存 | 写入 hex 数据到内存 |
| `Z0,addr,kind` | 设软件断点 | 保存原字节, 写 `0xCC`(INT3) 到 `addr` |
| `z0,addr,kind` | 删软件断点 | 恢复原字节 |
| `k` | 杀死 | 复位/停机 |

### 需要的内核基础设施

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

### 最小串口协议交互示例

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
    
### 估算工作量

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

## 注意事项

- 如果不需要 KVM (单步更准确), 可将 `make gdb-qemu` 中的 `-enable-kvm` 去掉
- `sg kvm` 可能在某些环境不可用, 去掉即可: `qemu-system-x86_64 -m 2G -nographic -smp 2 -vga std -hda build/vm-raw.img -s -S`
