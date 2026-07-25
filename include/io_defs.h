#ifndef IO_DEFS_H
#define IO_DEFS_H

/* bit manipulation macro */
#define BIT(n)          (1U << (n))

/* standard IO semantics — function return value bitmask conventions
   used by uart_iost() and any poll-style IO function */
#define READ_READY      BIT(0)    /* data available for read (RBR has data) */
#define WRITE_READY     BIT(1)    /* transmitter holding register empty, ready for write */

/* operation interface — test readiness bits in a status mask */
#define _IS_BIT_ALL(s, mask)        ((s) & (mask))
#define _IS_READ_READY(s)        _IS_BIT_ALL(s, READ_READY)
#define _IS_WRITE_READY(s)       _IS_BIT_ALL(s, WRITE_READY)
#define _IS_ANY_READY(s)         _IS_BIT_ALL(s, (READ_READY) | (WRITE_READY))

#endif

