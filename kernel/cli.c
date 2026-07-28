#include "cli.h"
#include "baremetal.h"
#include "gdb_io.h"
#include "gdb_stub.h"
#include "ui.h"

#define CLI_BUF_SIZE 128
#define PROMPT "$ "

static char cli_buf[CLI_BUF_SIZE];
static int cli_pos = 0;
static int cli_active = 1;

static void puts(const char *s) {
    bm_puts_raw(s);
}

static void putc_char(char c) {
    char buf[2] = { c, 0 };
    bm_puts_raw(buf);
}

static void put_hex(unsigned int val) {
    char buf[11] = "0x00000000";
    for (int i = 9; i >= 2; i--) {
        int nibble = val & 0xF;
        buf[i] = nibble < 10 ? '0' + nibble : 'a' + nibble - 10;
        val >>= 4;
    }
    puts(buf);
}

static void put_dec(int val) {
    char buf[12], *p = buf + sizeof(buf);
    *--p = 0;
    if (val < 0) { *--p = '-'; val = -val; }
    if (!val) *--p = '0';
    while (val) { *--p = '0' + val % 10; val /= 10; }
    puts(p);
}

static void show_prompt(void) {
    puts(PROMPT);
}

static void cmd_help(void) {
    puts("Commands:\n");
    puts("  help     - show this help\n");
    puts("  info     - show system info\n");
    puts("  test     - run serial loopback test\n");
    puts("  echo <s> - echo back text\n");
    puts("  hex <n>  - show number as hex\n");
    puts("  gdb      - switch serial to GDB mode\n");
}

static void cmd_info(void) {
    puts("Resolution: ");
    put_dec(bm_ui_width());
    puts("x");
    put_dec(bm_ui_height());
    puts("x");
    put_dec(bm_ui_bpp());
    puts("\n");
}

static void cmd_test(void) {
    extern void gdb_io_loopback_test(void);
    gdb_io_loopback_test();
}

static void cmd_echo(const char *arg) {
    puts(arg);
    puts("\n");
}

static void cmd_hex(const char *arg) {
    int val = 0;
    while (*arg >= '0' && *arg <= '9') {
        val = val * 10 + (*arg - '0');
        arg++;
    }
    put_hex(val);
    puts("\n");
}

static void cmd_gdb(void) {
    puts("Switching to GDB mode.\n");
    cli_active = 0;
}

static void process_line(void) {
    cli_buf[cli_pos] = 0;

    const char *cmd = cli_buf;
    while (*cmd == ' ') cmd++;

    if (*cmd == 0) {
        /* empty line */
    } else if (cmd[0] == 'h' && cmd[1] == 'e' && cmd[2] == 'l' && cmd[3] == 'p' && cmd[4] == 0) {
        cmd_help();
    } else if (cmd[0] == 'i' && cmd[1] == 'n' && cmd[2] == 'f' && cmd[3] == 'o' && cmd[4] == 0) {
        cmd_info();
    } else if (cmd[0] == 't' && cmd[1] == 'e' && cmd[2] == 's' && cmd[3] == 't' && cmd[4] == 0) {
        cmd_test();
    } else if (cmd[0] == 'g' && cmd[1] == 'd' && cmd[2] == 'b' && cmd[3] == 0) {
        cmd_gdb();
    } else if (cmd[0] == 'e' && cmd[1] == 'c' && cmd[2] == 'h' && cmd[3] == 'o' && cmd[4] == ' ') {
        cmd_echo(cmd + 5);
    } else if (cmd[0] == 'h' && cmd[1] == 'e' && cmd[2] == 'x' && cmd[3] == ' ') {
        cmd_hex(cmd + 4);
    } else {
        puts("Unknown: ");
        puts(cmd);
        puts("\nType 'help'.\n");
    }

    cli_pos = 0;
    show_prompt();
}

void cli_init(void) {
    cli_pos = 0;
    cli_active = 1;
    puts(PROMPT);
}

int cli_is_active(void) {
    return cli_active;
}

void cli_poll(void) {
    unsigned char c;
    if (!cli_active) return;
    if (!gdb_io_data_ready()) return;
    if (gdb_io_try_read(&c) < 0) return;

    if (c == '\n' || c == '\r') {
        putc_char('\n');
        if (cli_pos > 0) {
            process_line();
        } else {
            show_prompt();
        }
    } else if (c == '\b' || c == 127) {
        if (cli_pos > 0) {
            cli_pos--;
            puts("\b \b");
        }
    } else if (c == '\t') {
        /* ignore tabs */
    } else if (c == 0x03) {
        /* Ctrl-C: cancel current line */
        puts("^C\n");
        cli_pos = 0;
        show_prompt();
    } else if (cli_pos < CLI_BUF_SIZE - 1) {
        cli_buf[cli_pos++] = c;
        putc_char(c);
    }
}
