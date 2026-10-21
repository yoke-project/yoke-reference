/*
 * Where the panel draws: a display of memory a case can look at, or a Linux framebuffer on a device.
 */
#ifndef PANEL_DISPLAY_H
#define PANEL_DISPLAY_H

#include <lvgl.h>

/*
 * A display of width by height, drawn to where `spec` says: `offscreen` is memory, and `fbdev:<path>` the
 * framebuffer at the path. NULL when it cannot be opened.
 */
lv_display_t *panel_display_open(const char *spec, int width, int height);

/* How many times the display has been flushed: what an offscreen display shows of being drawn to. */
unsigned long panel_display_flushed(void);

#endif
