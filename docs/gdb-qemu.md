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

## 注意事项

- 如果不需要 KVM (单步更准确), 可将 `make gdb-qemu` 中的 `-enable-kvm` 去掉
- `sg kvm` 可能在某些环境不可用, 去掉即可: `qemu-system-x86_64 -m 2G -nographic -smp 2 -vga std -hda build/vm-raw.img -s -S`

GDB stub 自实现方案见 [`gdb.md`](gdb.md)。
