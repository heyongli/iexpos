# iexpos — 项目文档与工作流指引

> 本文件是项目索引，**不需要一次性加载全部内容**。
> 
> 工作原则：
> 1. 文件需要先用一句话说明其角色，再 Read 具体内容；不预先加载全部 context
> 2. 修改模块时，根据下方索引找到对应文件再 Read，不同时加载无关文件
> 3. 只读当前任务需要的文件，用完即止

## 文件索引

> **外部引用文档为参考文档，仅在需要时加载为 context，不预先读取。**

- boot/boot.asm 引导加载内核
- boot/entry.asm GDT+CR0, 跳 setup_main

- kernel/setup.c 入口, bm_init, 打印, 运行demo
- kernel/console.c/h 环缓冲, 后端分发
- include/baremetal.h 统一平台 API
- include/font_8x16.h 字体

- bmX86/vga.c/h VGA驱动
- bmX86/rtc.c/h RTC驱动
- include/vbe.h VBE结构体

- ui/ui.c/h 进度条

- demos/demos.h demo入口
- demos/orbit.c 旋转动画

- tests/serial.sh 串口测试
- tests/visual.sh 画面测试
- tests/gdb-qemu.sh QEMU单步跟踪

- docs/gdb-qemu.md QEMU GDB文档
- docs/gdb.md GDB stub实现
- docs/serial.md 串口设计
- docs/io-ports.md I/O端口速查
| 文件 | 作用 |
|------|------|
| `gdb-qemu.md` | GDB (via QEMU) 调试文档: 改动/原理/用法/测试 |
| `gdb.md` | GDB stub 自实现: 协议/IDT/串口/断点表/工作量估算 |

## 构建与测试

```bash
make clean all           # 构建 (产物在 build/)
./test.sh                # 运行全部测试
tests/serial.sh          # 单独串口测试
tests/visual.sh          # 单独画面测试
```

## 关键约定

- **不要自动 commit**，只有明确要求时才 commit
- C: `-m32 -ffreestanding -fno-PIC -nostdlib -fno-asynchronous-unwind-tables`
- ASM kernel: NASM `-f elf32`; boot: NASM `-f bin [org 0x7c00]`
- 链接: `ld -m elf_i386 -Ttext 0x7E00 -e entry --oformat binary -n`
- 无标准库, 栈: `mov esp, 0x7C00`
- kernel.bin 起始 4 字节即 entry.asm (链接在第一位)
- 内核加载地址: 0x7E00, BSS 靠 `-n` 避免落到 0xA0000

GDB (QEMU) 调试详情见 `docs/gdb-qemu.md`。
调试串口标记见 `docs/serial.md`。

I/O 端口速查见 `docs/io-ports.md`。
