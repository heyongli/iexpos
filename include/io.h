#ifndef IO_DEFS_H
#define IO_DEFS_H

/* bit manipulation macro */
#define BIT(n)          (1U << (n))

/* standard IO semantics — function return value bitmask conventions
   used by uart_iost() and any poll-style IO function */
#define _READ_READY      BIT(0)    /* data available for read (RBR has data) */
#define _WRITE_READY     BIT(1)    /* transmitter holding register empty, ready for write */

#define _IO_OK       0    /* operation completed successfully */
#define _IO_ERR    BIT(31)   /* caller must handle result (sign bit) */
/* if result < 0, caller must handle it */
#define _NOT_READY    BIT(30)   /* resource not ready */
#define _ABORT       BIT(29)   /* operation aborted by IO abort signal */


/* operation interface — test readiness bits in a status mask */
#define _IS_BIT_ALL(s, mask)        ((s) & (mask))
#define _IS_READ_READY(s)        _IS_BIT_ALL(s, _READ_READY)
#define _IS_WRITE_READY(s)       _IS_BIT_ALL(s, _WRITE_READY)
#define _IS_ANY_READY(s)         _IS_BIT_ALL(s, (_READ_READY) | (_WRITE_READY))




/* io abort: defined per-arch in os_regs.h (e.g., EFLAGS reserved bit) */



#endif