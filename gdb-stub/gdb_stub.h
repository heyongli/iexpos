#ifndef GDB_STUB_H
#define GDB_STUB_H

void gdb_stub_init(void);
void gdb_poll(void);
void serial_rw_test(void);

/* Called from asm trampoline — remove/re-insert all breakpoints
   around each gdb_handler invocation to prevent reentrancy. */
void bp_remove_all(void);
void bp_insert_all(void);

#endif
