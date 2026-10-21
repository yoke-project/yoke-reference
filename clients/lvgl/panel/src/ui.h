/*
 * The panel's screen, composed from the picture: the channel's own state, and for each unit a line saying
 * what it is and what the channel may address on it, with a button for each command and each question. A
 * button does what the panel is told to do for it, and the screen says what came of it.
 */
#ifndef PANEL_UI_H
#define PANEL_UI_H

#include <lvgl.h>

#include "picture.h"

/* What a button does. Each returns a line saying what came of it, which the caller frees. */
typedef struct panel_acts {
    void *context;
    char *(*command)(void *context, const char *unit, const char *type);
    char *(*ask)(void *context, const char *unit, const char *type);
} panel_acts;

typedef struct panel_ui panel_ui;

/* A screen on `parent`, doing what `acts` says. */
panel_ui *panel_ui_make(lv_obj_t *parent, const panel_acts *acts);
void panel_ui_free(panel_ui *ui);

/* Composes the screen from the picture, replacing what it held. */
void panel_ui_show(panel_ui *ui, const panel_picture *picture);

/* How many units the screen shows, the text of the line of the i-th, and the button for a command or a
 * question of a unit (NULL when the screen has none). */
size_t panel_ui_units(const panel_ui *ui);
const char *panel_ui_unit_text(const panel_ui *ui, size_t i);
lv_obj_t *panel_ui_button(const panel_ui *ui, const char *unit, const char *type);

/* The channel's line, and what the last button said. */
const char *panel_ui_channel_text(const panel_ui *ui);
const char *panel_ui_status_text(const panel_ui *ui);

#endif
