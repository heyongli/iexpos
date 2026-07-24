# VBE Structures — vbe.h

## Purpose

Provides **packed C structs** matching the VESA BIOS Extension (VBE) 3.0
specification for querying and setting video modes. These structs allow the
kernel to directly parse the mode‑info block written by the bootloader.

## Structures

### `struct vbe_info_block`

Returned by VBE function `AX=0x4F00` (get controller info). Size: 512 B.

| Offset | Type   | Field        | Description              |
|--------|--------|--------------|--------------------------|
| 0x00   | char[4]| `signature`  | `"VESA"`                 |
| 0x04   | u16    | `version`    | BCD version (e.g. 0x0300)|
| 0x06   | u32    | `oem_str`    | Far pointer to OEM name  |
| 0x0A   | u32    | `capabilities`| Feature flags           |
| 0x0E   | u32    | `video_mode` | Pointer to mode list     |
| 0x12   | u16    | `total_mem`  | Video memory in 64 KB    |
| 0x14   | u16    | `oem_ver`    | OEM software version     |
| 0x16   | u32    | `oem_data`   | Far pointer to OEM data  |
| 0x1A   | char[222]| `reserved` | Reserved                 |
| 0x100  | char[256]| `oem`      | OEM data / strings       |

### `struct vbe_mode_info` ★

Returned by VBE function `AX=0x4F01` (get mode info). Size: 256 B. This is
the struct used by the bootloader and VGA driver.

| Offset | Type | Field            | Description                        |
|--------|------|------------------|------------------------------------|
| 0x00   | u16  | `mode_attr`      | Mode attributes (0x0001=supported) |
| 0x02   | u8   | `win_a_attr`     | Window A attributes                |
| 0x03   | u8   | `win_b_attr`     | Window B attributes                |
| 0x04   | u16  | `win_gran`       | Window granularity (KB)            |
| 0x06   | u16  | `win_size`       | Window size (KB)                   |
| 0x08   | u16  | `win_a_seg`      | Window A start segment             |
| 0x0A   | u16  | `win_b_seg`      | Window B start segment             |
| 0x0C   | u32  | `win_func`       | Window positioning function ptr    |
| 0x10   | u16  | `pitch`          | Bytes per scan line                |
| **0x12**| u16  | **`width`**      | **X resolution in pixels**        |
| **0x14**| u16  | **`height`**     | **Y resolution in pixels**        |
| 0x16   | u8   | `w_char`         | Character cell width               |
| 0x17   | u8   | `h_char`         | Character cell height              |
| 0x18   | u8   | `planes`         | Number of planes                   |
| **0x19**| u8   | **`bpp`**        | **Bits per pixel**                |
| 0x1A   | u8   | `banks`          | Number of banks                    |
| 0x1B   | u8   | `mem_model`      | Memory model (0x06=direct colour)  |
| 0x1C   | u8   | `bank_size`      | Bank size (KB)                     |
| 0x1D   | u8   | `image_pages`    | Number of image pages              |
| 0x1F–0x26| —   | colour masks     | Bit positions for R/G/B/A          |
| **0x28**| u32  | **`fb_addr`**    | **Physical linear fb address**    |
| 0x2C   | u32  | `offscreen`      | Off-screen memory offset (VBE 3.0) |
| 0x30   | u16  | `offscreen_size` | Off-screen memory size             |

Fields in **bold** are used by the bootloader and VGA driver.

## Usage

### Bootloader (assembly)

```asm
mov ax, 0x4F01
mov cx, 0x4118          ; mode number
mov es, 0x1000
xor di, di              ; ES:DI = 0x10000 (buffer)
int 0x10                ; get mode info → ES:DI

mov ax, 0x4F02
mov bx, 0x4118
int 0x10                ; set mode

; copy relevant fields to 0x600
mov ax, [es:di+0x12]   ; width
mov [0x600], ax
mov ax, [es:di+0x14]   ; height
mov [0x602], ax
mov al, [es:di+0x19]   ; bpp
mov [0x604], al
mov eax, [es:di+0x28]  ; fb_addr
mov [0x608], eax
```

### C driver (vga.c)

```c
volatile struct vbe_mode_info *v = (void *)0x10000;
fb.width  = v->width;
fb.height = v->height;
fb.bpp    = v->bpp;
fb.addr   = v->fb_addr;
```

The raw block remains at `0x10000` after the bootloader completes, allowing
the C code to read additional fields (pitch, colour masks, etc.) if needed.

## `__attribute__((packed))`

Both structs use `__attribute__((packed))` to disable structure padding,
ensuring the memory layout matches the VBE specification exactly. Without
this, the compiler would add alignment padding between fields (e.g., 2 bytes
between the `u8` and `u16` fields), corrupting the offsets.
