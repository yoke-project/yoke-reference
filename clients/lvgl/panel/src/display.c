#include "display.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static unsigned long flushed;

static uint32_t milliseconds(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint32_t)(t.tv_sec * 1000 + t.tv_nsec / 1000000);
}

/* A display of memory draws nowhere: it counts the flushes, and says it is done. */
static void flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels) {
    (void)area;
    (void)pixels;
    flushed++;
    lv_display_flush_ready(display);
}

unsigned long panel_display_flushed(void) { return flushed; }

lv_display_t *panel_display_open(const char *spec, int width, int height) {
    if (!lv_is_initialized()) {
        lv_init();
        lv_tick_set_cb(milliseconds);
    }
    if (strncmp(spec, "fbdev:", 6) == 0) {
        lv_display_t *display = lv_linux_fbdev_create();
        if (display == NULL) {
            return NULL;
        }
        lv_linux_fbdev_set_file(display, spec + 6);
        return display;
    }
    if (strcmp(spec, "offscreen") != 0) {
        return NULL;
    }
    lv_display_t *display = lv_display_create(width, height);
    size_t size = (size_t)width * (size_t)height / 10 * 4;
    lv_display_set_buffers(display, malloc(size), NULL, (uint32_t)size, LV_DISPLAY_RENDER_MODE_PARTIAL);
    lv_display_set_flush_cb(display, flush);
    return display;
}
