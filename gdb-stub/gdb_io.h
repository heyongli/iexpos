#ifndef GDB_IO_H
#define GDB_IO_H

/* Serial byte I/O for GDB stub.
   Platform-agnostic interface — no hardware headers needed by callers. */
void gdb_io_init(void);
void gdb_io_write(unsigned char c);
int  gdb_io_read(unsigned char *c);
int  gdb_io_try_read(unsigned char *c);
int  gdb_io_data_ready(void);
int  gdb_io_abort_pending(void);
void gdb_io_loopback_test(void);

#endif
