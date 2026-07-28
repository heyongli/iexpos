#ifndef RTC_H
#define RTC_H

typedef void (*output_fn)(const char *);

int  rtc_read_time(unsigned char *h, unsigned char *m, unsigned char *s);
void rtc_format_ts(char buf[9]);
void write_timestamp(output_fn out);

#endif
