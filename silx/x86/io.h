#ifndef SILX_IO_H
#define SILX_IO_H

/* include common IO definitions (BIT, _IO_OK, etc.).
   Use the relative path so this file does not re-include itself when
   callers in this dir resolve `"io.h"` to silx/x86/io.h (current-dir
   lookup wins over -I meta). */
#include "../../meta/io.h"

void mdelay(unsigned int ms);

#endif
