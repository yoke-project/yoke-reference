#include "ui.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct action {
    panel_ui *ui;
    char *unit, *type;
    int asks;
    lv_obj_t *button;
} action;

struct panel_ui {
    panel_acts acts;
    lv_obj_t *root, *channel, *status, *units;
    action *actions;
    size_t n_actions;
    lv_obj_t **unit_labels;
    size_t n_units;
};

static void clicked(lv_event_t *e) {
    action *a = lv_event_get_user_data(e);
    char *said = a->asks ? a->ui->acts.ask(a->ui->acts.context, a->unit, a->type)
                         : a->ui->acts.command(a->ui->acts.context, a->unit, a->type);
    lv_label_set_text(a->ui->status, said ? said : "");
    free(said);
}

panel_ui *panel_ui_make(lv_obj_t *parent, const panel_acts *acts) {
    panel_ui *ui = calloc(1, sizeof *ui);
    ui->acts = *acts;
    ui->root = lv_obj_create(parent);
    lv_obj_set_size(ui->root, LV_PCT(100), LV_PCT(100));
    lv_obj_set_flex_flow(ui->root, LV_FLEX_FLOW_COLUMN);
    ui->channel = lv_label_create(ui->root);
    lv_label_set_text(ui->channel, "");
    ui->units = lv_obj_create(ui->root);
    lv_obj_set_size(ui->units, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(ui->units, LV_FLEX_FLOW_COLUMN);
    ui->status = lv_label_create(ui->root);
    lv_label_set_text(ui->status, "");
    return ui;
}

static void forget_actions(panel_ui *ui) {
    for (size_t i = 0; i < ui->n_actions; i++) {
        free(ui->actions[i].unit);
        free(ui->actions[i].type);
    }
    free(ui->actions);
    ui->actions = NULL;
    ui->n_actions = 0;
    free(ui->unit_labels);
    ui->unit_labels = NULL;
    ui->n_units = 0;
}

void panel_ui_free(panel_ui *ui) {
    if (ui == NULL) {
        return;
    }
    forget_actions(ui);
    lv_obj_delete(ui->root);
    free(ui);
}

static void add_button(panel_ui *ui, lv_obj_t *row, const char *unit, const char *type, int asks,
                       action *slots, size_t *at) {
    action *a = &slots[(*at)++];
    a->ui = ui;
    a->unit = strdup(unit);
    a->type = strdup(type);
    a->asks = asks;
    a->button = lv_button_create(row);
    lv_obj_t *label = lv_label_create(a->button);
    char *text = NULL;
    if (asprintf(&text, "%s %s", asks ? "ask" : "do", type) >= 0) {
        lv_label_set_text(label, text);
        free(text);
    }
    lv_obj_add_event_cb(a->button, clicked, LV_EVENT_CLICKED, a);
}

void panel_ui_show(panel_ui *ui, const panel_picture *picture) {
    lv_obj_clean(ui->units);
    forget_actions(ui);
    lv_label_set_text(ui->channel, "");
    size_t units = 0, buttons = 0;
    for (size_t i = 0; i < panel_picture_count(picture); i++) {
        const Yoke__Interface__V1__Record *r = panel_picture_record(picture, i);
        if (r->subject_case == YOKE__INTERFACE__V1__RECORD__SUBJECT_UNIT) {
            units++;
            if (r->unit->addressed != NULL) {
                buttons += r->unit->addressed->n_commands + r->unit->addressed->n_queries;
            }
        }
    }
    ui->actions = calloc(buttons ? buttons : 1, sizeof *ui->actions);
    ui->unit_labels = calloc(units ? units : 1, sizeof *ui->unit_labels);
    for (size_t i = 0; i < panel_picture_count(picture); i++) {
        const Yoke__Interface__V1__Record *r = panel_picture_record(picture, i);
        if (r->subject_case == YOKE__INTERFACE__V1__RECORD__SUBJECT_CHANNEL && r->channel->declared != NULL) {
            char *line = NULL;
            const Yoke__Interface__V1__ChannelRecord *c = r->channel;
            if (asprintf(&line, "channel %s %s %s", c->declared->name, c->declared->projection,
                         c->observed != NULL && c->observed->attached ? "attached" : "detached") >= 0) {
                lv_label_set_text(ui->channel, line);
                free(line);
            }
        } else if (r->subject_case == YOKE__INTERFACE__V1__RECORD__SUBJECT_UNIT) {
            lv_obj_t *row = lv_obj_create(ui->units);
            lv_obj_set_size(row, LV_PCT(100), LV_SIZE_CONTENT);
            lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW_WRAP);
            lv_obj_t *label = lv_label_create(row);
            char *line = panel_unit_line(r->unit);
            lv_label_set_text(label, line ? line : "");
            free(line);
            ui->unit_labels[ui->n_units++] = label;
            const char *unit = r->unit->declared ? r->unit->declared->identity : "";
            if (r->unit->addressed != NULL) {
                for (size_t k = 0; k < r->unit->addressed->n_commands; k++) {
                    add_button(ui, row, unit, r->unit->addressed->commands[k], 0, ui->actions, &ui->n_actions);
                }
                for (size_t k = 0; k < r->unit->addressed->n_queries; k++) {
                    add_button(ui, row, unit, r->unit->addressed->queries[k], 1, ui->actions, &ui->n_actions);
                }
            }
        }
    }
}

size_t panel_ui_units(const panel_ui *ui) { return ui->n_units; }

const char *panel_ui_unit_text(const panel_ui *ui, size_t i) {
    return i < ui->n_units ? lv_label_get_text(ui->unit_labels[i]) : NULL;
}

lv_obj_t *panel_ui_button(const panel_ui *ui, const char *unit, const char *type) {
    for (size_t i = 0; i < ui->n_actions; i++) {
        if (strcmp(ui->actions[i].unit, unit) == 0 && strcmp(ui->actions[i].type, type) == 0) {
            return ui->actions[i].button;
        }
    }
    return NULL;
}

const char *panel_ui_channel_text(const panel_ui *ui) { return lv_label_get_text(ui->channel); }

const char *panel_ui_status_text(const panel_ui *ui) { return lv_label_get_text(ui->status); }
