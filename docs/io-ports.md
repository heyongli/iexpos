# I/O 端口速查 — iexpos

| 端口 | 用途 |
|------|------|
| 0x1CE/0x1CF | Bochs VBE index/data |
| 0xCF8/0xCFC | PCI config address/data |
| 0x40 | PIT 通道 0（计数器数据） |
| 0x43 | PIT 控制字（0x36 = 通道 0、LSB+MSB、模式 3、二进制） |
| 0x3F8 | COM1 串口 |
| 0x70/0x71 | CMOS RTC address/data |

## PIT 注意

- 上电后 PIT 通道 0 未编程（计数 65536，QEMU 中计数器不启动，`pit_read()` 恒为常量）。
- `pit_init()`（`silx/x86/io.c`）用控制字 0x36 + 计数 0x0000 装载，计数器以 1.193182 MHz 全速自由翻转 65535→0，`elapsed_pit()` / `mdelay()` 才有效。
- 装载计数 1 不可用：计数器只在 0/1 间跳动，`elapsed_pit()` 无法累积到 `PIT_FRAME_TICKS`。
