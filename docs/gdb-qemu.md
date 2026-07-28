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
| `bm_init` | silx/x86/vga.c | PCI/VBE/VGA 初始化 |
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
- `sg kvm` 可能在某些环境不可用, 去掉即可: `qemu-system-x86_64 -m 2G -nographic -smp 2 -vga std -drive file=build/vm-raw.img,format=raw -s -S`

GDB stub 自实现方案见 [`gdb-serial.md`](gdb-serial.md)。

## 调试示例

### 启动步骤

**终端 1** — 启动 QEMU + GDB server:
```bash
# 方法 A: 使用 make 目标
make gdb-qemu

# 方法 B: 手动启动
qemu-system-x86_64 \
  -enable-kvm -m 2G -nographic -smp 2 -vga std \
  -drive file=build/vm-raw.img,format=raw \
  -net none \
  -s -S    # -s: 启动 GDB server (端口 1234), -S: 冻结 CPU
```

**终端 2** — 连接 GDB:
```bash
# 方法 A: 自动脚本
gdb -x tests/gdb-qemu.gdb

# 方法 B: 手动连接
gdb build/kernel.elf
(gdb) set architecture i386:x86-64
(gdb) target remote localhost:1234
```

### 常用调试命令

```bash
# 设置断点
(gdb) break setup_main          # C 函数断点
(gdb) break bm_init             # 另一个函数
(gdb) break *0x7E00             # 地址断点
(gdb) hbreak setup_main         # 硬件断点 (KVM 更可靠)

# 控制执行
(gdb) continue                  # 继续运行
(gdb) step                      # 单步进入
(gdb) next                      # 单步跳过
(gdb) finish                    # 跳出当前函数

# 查看状态
(gdb) info registers            # 查看寄存器
(gdb) print variable            # 打印变量
(gdb) print *fb                 # 打印结构体
(gdb) x/16wx 0xB8000           # 查看内存
(gdb) backtrace                 # 调用栈

# 源码操作
(gdb) list                      # 显示源码
(gdb) list setup.c:50           # 跳到指定行
(gdb) info functions            # 列出函数
```

### 实际调试示例

**场景 1: 调试 VGA 初始化**
```bash
(gdb) break bm_init
(gdb) continue
# 命中断点
(gdb) next                      # 单步执行
(gdb) print fb.width            # 检查 framebuffer 宽度
(gdb) print fb.height           # 检查 framebuffer 高度
(gdb) continue
```

**场景 2: 调试 GDB stub**
```bash
(gdb) break gdb_handler
(gdb) continue
# 收到 GDB 请求时中断
(gdb) print *r                  # 查看寄存器结构
(gdb) print hex_buf             # 查看 GDB 命令
(gdb) continue
```

**场景 3: 检查内存映射**
```bash
(gdb) x/32wx 0x7E00            # 查看内核起始处
(gdb) x/s 0x7E00               # 查看字符串
(gdb) info registers cr0        # 查看控制寄存器
```

### 调试技巧

**使用 QEMU monitor:**
```bash
# 启动时添加 monitor
qemu-system-x86_64 ... -monitor tcp:127.0.0.1:4444,server,nowait

# 连接 monitor
nc 127.0.0.1 4444

# 常用命令
info registers        # 查看寄存器
info cpus             # 查看 CPU 状态
screendump file.ppm  # 截屏
xp /16wx 0x7E00      # 查看内存
```

**断点调试 GDB stub:**
如果 GDB stub 本身有问题，可以用 QEMU 的 `-s` 调试 stub:
```bash
# 终端 1: 启动 QEMU (串口到文件)
qemu-system-x86_64 ... -serial file:/tmp/serial.log -s -S

# 终端 2: GDB 调试
gdb build/kernel.elf
(gdb) target remote :1234
(gdb) break gdb_handler
(gdb) continue
```

### 常见问题

**GDB 无法连接?**
```bash
# 检查 QEMU 是否在运行
ps aux | grep qemu

# 检查端口是否打开
ss -ltn | grep 1234
```

**GDB 显示 "Remote communication error"?**
```bash
# 重启 QEMU
killall qemu-system-x86_64
make gdb-qemu
```
