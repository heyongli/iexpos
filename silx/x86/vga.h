#ifndef VGA_DRV_H
#define VGA_DRV_H

struct fb_info {
    unsigned short width;
    unsigned short height;
    unsigned char  bpp;
    unsigned char  reserved[3];
    unsigned int   addr;
};

#endif
