#ifndef VBE_H
#define VBE_H

/* VBE Controller Info (returned by AX=0x4F00) */
struct vbe_info_block {
    char     signature[4];      /* "VESA" */
    unsigned short version;     /* e.g. 0x0300 for VBE 3.0 */
    unsigned long  oem_str;     /* seg:off ptr */
    unsigned long  capabilities;
    unsigned long  video_mode;  /* seg:off ptr to mode list */
    unsigned short total_mem;   /* in 64KB blocks */
    unsigned short oem_ver;
    unsigned long  oem_data;
    char     reserved[222];
    char     oem[256];
} __attribute__((packed));

/* VBE Mode Info Block (returned by AX=0x4F01) */
struct vbe_mode_info {
    /* Mandatory (VBE 1.0+) */
    unsigned short mode_attr;       /* 0x00 */
    unsigned char  win_a_attr;      /* 0x02 */
    unsigned char  win_b_attr;      /* 0x03 */
    unsigned short win_gran;        /* 0x04 */
    unsigned short win_size;        /* 0x06 */
    unsigned short win_a_seg;       /* 0x08 */
    unsigned short win_b_seg;       /* 0x0A */
    unsigned long  win_func;        /* 0x0C */
    unsigned short pitch;           /* 0x10 - bytes per scan line */

    /* Resolution / color */
    unsigned short width;           /* 0x12 */
    unsigned short height;          /* 0x14 */
    unsigned char  w_char;          /* 0x16 */
    unsigned char  h_char;          /* 0x17 */
    unsigned char  planes;          /* 0x18 */
    unsigned char  bpp;             /* 0x19 */
    unsigned char  banks;           /* 0x1A */
    unsigned char  mem_model;       /* 0x1B */
    unsigned char  bank_size;       /* 0x1C - KB */
    unsigned char  image_pages;     /* 0x1D */
    unsigned char  reserved1;       /* 0x1E */

    /* Direct color fields */
    unsigned char  red_mask;        /* 0x1F */
    unsigned char  red_pos;         /* 0x20 */
    unsigned char  green_mask;      /* 0x21 */
    unsigned char  green_pos;       /* 0x22 */
    unsigned char  blue_mask;       /* 0x23 */
    unsigned char  blue_pos;        /* 0x24 */
    unsigned char  rsvd_mask;       /* 0x25 */
    unsigned char  rsvd_pos;        /* 0x26 */
    unsigned char  dc_info;         /* 0x27 - direct color mode info */

    /* Physical framebuffer (VBE 2.0+) */
    unsigned long  fb_addr;         /* 0x28 - linear framebuffer address */

    /* VBE 3.0+ */
    unsigned long  offscreen;       /* 0x2C */
    unsigned short offscreen_size;  /* 0x30 */

    unsigned char  reserved2[206];  /* 0x32-0xFF */
} __attribute__((packed));

#endif
