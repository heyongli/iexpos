# iexpos — 项目文档与工作流指引

> 本文件是项目索引，**不需要一次性加载全部内容**。
> 需要修改某个模块时，根据下方文件说明找到对应文件再 Read。

## 执行流

BIOS → `boot/boot.asm` (INT 13h, 加载 30 扇区到 0x7E00)
     → `boot/entry.asm` (16→32-bit, LGDT/CR0, 跳 setup_main)
     → `kernel/setup.c` (C init + 运行 demo)

## 文件索引

### `boot/` — 引导
| 文件 | 作用 |
|------|------|
| `boot.asm` | 512B MBR, DAP 加载 kernel, 跳 0x7E00 |
| `entry.asm` | GDT + CR0.PE + far jump, 串口 "PMOK", call setup_main |

### `kernel/` — 核心子系统
| 文件 | 作用 |
|------|------|
| `setup.c` | 入口: bm_init → 打印信息 → 运行 demo |
| `console.c/h` | 4KB 环缓冲 + 时间戳 + 后端分发 (serial/screen) |
| `include/baremetal.h` | 统一平台 API (bm_puts, bm_ui_\*, bm_swap...) |
| `include/font_8x16.h` | IBM VGA 8×16 位图字体 (0x20–0x7E) |

### `bmX86/` — x86 平台驱动
| 文件 | 作用 |
|------|------|
| `vga.c/h` | PCI/VBE/VGA13 检测 + framebuffer + swap buffer + font render + screen backend |
| `rtc.c/h` | CMOS RTC via 0x70/0x71, BCD→bin, HH:MM:SS |
| `include/vbe.h` | VBE info block 结构体定义 |

### `ui/` — UI 控件
| 文件 | 作用 |
|------|------|
| `ui.c/h` | 进度条: progress_init/set/text, 自动调用 bm_swap |

### `demos/` — 演示
| 文件 | 作用 |
|------|------|
| `demos.h` | demo 入口声明 |
| `orbit.c` | 4 方块绕屏幕中心旋转 + 进度条动画 (sin/cos LUT) |

### `tests/` — 测试
| 文件 | 作用 |
|------|------|
| `serial.sh` | 串口输出含 PMOK/entry/Graphics init OK/Graphics test complete |
| `visual.sh` | QEMU screendump, 校验 framebuffer 非全黑 |

## 构建与测试

```bash
make clean all           # 构建
./test.sh                # 运行全部测试
tests/serial.sh          # 单独串口测试
tests/visual.sh          # 单独画面测试
```

## 关键约定

- C: `-m32 -ffreestanding -fno-PIC -nostdlib -fno-asynchronous-unwind-tables`
- ASM kernel: NASM `-f elf32`; boot: NASM `-f bin [org 0x7c00]`
- 链接: `ld -m elf_i386 -Ttext 0x7E00 -e entry --oformat binary -n`
- 无标准库, 栈: `mov esp, 0x7C00`
- kernel.bin 起始 4 字节即 entry.asm (链接在第一位)
- 内核加载地址: 0x7E00, BSS 靠 `-n` 避免落到 0xA0000

## 调试串口标记

| 串口输出 | 含义 | 缺失原因 |
|----------|------|----------|
| `PMOK` | entry.asm PM 切换成功 | GDT/CR0/far jump 错误 |
| `entry` | setup_main 已运行 | extern 或 `-e entry` 问题 |
| `vga init done` | vga.init() 返回 | PCI/VBE 挂起或 VGA 寄存器问题 |
| `Graphics init OK` | 控制台缓冲正常 | 字体渲染崩溃或缓冲溢出 |

`bm_puts()` 在 bm_init 前后都能用, 适合早期调试埋点。

## I/O 端口速查

| 端口 | 用途 |
|------|------|
| 0x1CE/0x1CF | Bochs VBE index/data |
| 0xCF8/0xCFC | PCI config address/data |
| 0x3F8 | COM1 串口 |
| 0x70/0x71 | CMOS RTC address/data |
