#ifndef SILX_IO_H
#define SILX_IO_H

/* include common IO definitions (BIT, _IO_OK, etc.).
   Use the relative path so this file does not re-include itself when
   callers in this dir resolve `"io.h"` to silx/x86/io.h (current-dir
   lookup wins over -I meta). */
#include "../../meta/io.h"

/* PIT (8253/8254) runs at 1.193182 MHz = 1193182 Hz */
#define PIT_FREQ_HZ 1193182u

/* PIT ticks per millisecond (rounded) */
#define PIT_MS (PIT_FREQ_HZ / 1000u)

/* frame timing: 16 ms per frame (~62.5 fps, close to 60 Hz display) -> compile-time tick count */
#define PIT_FRAME_TICKS (16u * PIT_MS)

/* elapsed PIT ticks since 'start' (handles 16-bit wrap-around).
 * Usage: elapsed_pit(start) > 10 * PIT_MS  */
#define elapsed_pit(start) \
    ((unsigned short)((start) - pit_read()))

void pit_init(void);
void mdelay(unsigned int ms);
unsigned short pit_read(void);

#endif
