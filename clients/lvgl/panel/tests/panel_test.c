/* The panel's cases, each reported in the form the record writer reads: `pass  <id>`, or `FAIL  <id> — <why>`. */
#define _GNU_SOURCE
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "display.h"
#include "picture.h"
#include "ui.h"

static char why[512];

/* A case fails with a reason, and returns it. */
static const char *fail(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vsnprintf(why, sizeof why, format, args);
    va_end(args);
    return why;
}

#define NEED(cond, ...)                                                                                          \
    do {                                                                                                         \
        if (!(cond)) {                                                                                           \
            return fail(__VA_ARGS__);                                                                            \
        }                                                                                                        \
    } while (0)

/* ---- records ---- */

static Yoke__Interface__V1__Record *unit_record(const char *id, const char *state, const char *command,
                                                const char *query) {
    Yoke__Interface__V1__Record *r = malloc(sizeof *r);
    yoke__interface__v1__record__init(r);
    Yoke__Interface__V1__UnitRecord *u = malloc(sizeof *u);
    yoke__interface__v1__unit_record__init(u);
    u->declared = malloc(sizeof *u->declared);
    yoke__interface__v1__unit_record__declared__init(u->declared);
    u->declared->identity = strdup(id);
    u->declared->kind = strdup("plugin");
    u->observed = malloc(sizeof *u->observed);
    yoke__interface__v1__unit_record__observed__init(u->observed);
    u->observed->state = strdup(state);
    u->addressed = malloc(sizeof *u->addressed);
    yoke__interface__v1__unit_record__addressed__init(u->addressed);
    if (command != NULL) {
        u->addressed->commands = malloc(sizeof(char *));
        u->addressed->commands[0] = strdup(command);
        u->addressed->n_commands = 1;
    }
    if (query != NULL) {
        u->addressed->queries = malloc(sizeof(char *));
        u->addressed->queries[0] = strdup(query);
        u->addressed->n_queries = 1;
    }
    r->subject_case = YOKE__INTERFACE__V1__RECORD__SUBJECT_UNIT;
    r->unit = u;
    return r;
}

static Yoke__Interface__V1__Record *channel_record(const char *name) {
    Yoke__Interface__V1__Record *r = malloc(sizeof *r);
    yoke__interface__v1__record__init(r);
    Yoke__Interface__V1__ChannelRecord *c = malloc(sizeof *c);
    yoke__interface__v1__channel_record__init(c);
    c->declared = malloc(sizeof *c->declared);
    yoke__interface__v1__channel_record__declared__init(c->declared);
    c->declared->name = strdup(name);
    c->declared->projection = strdup("local");
    c->observed = malloc(sizeof *c->observed);
    yoke__interface__v1__channel_record__observed__init(c->observed);
    c->observed->attached = 1;
    r->subject_case = YOKE__INTERFACE__V1__RECORD__SUBJECT_CHANNEL;
    r->channel = c;
    return r;
}

static Yoke__Interface__V1__Record *instance_record(void) {
    Yoke__Interface__V1__Record *r = malloc(sizeof *r);
    yoke__interface__v1__record__init(r);
    Yoke__Interface__V1__InstanceRecord *i = malloc(sizeof *i);
    yoke__interface__v1__instance_record__init(i);
    i->ready = 1;
    r->subject_case = YOKE__INTERFACE__V1__RECORD__SUBJECT_INSTANCE;
    r->instance = i;
    return r;
}

static Yoke__Interface__V1__Snapshot opening;
static Yoke__Interface__V1__Record *opening_records[4];

/* An opening at the sequence 4 holding the instance, the channel `panel` and the units `acquire` and
 * `provision-store`. */
static const Yoke__Interface__V1__Snapshot *the_opening(void) {
    yoke__interface__v1__snapshot__init(&opening);
    opening.at = 4;
    opening_records[0] = instance_record();
    opening_records[1] = channel_record("panel");
    opening_records[2] = unit_record("acquire", "Running", "calibrate", "head-status");
    opening_records[3] = unit_record("provision-store", "Completed", NULL, NULL);
    opening.records = opening_records;
    opening.n_records = 4;
    return &opening;
}

static char *subjects(const panel_picture *p) {
    char *out = strdup("");
    for (size_t i = 0; i < panel_picture_count(p); i++) {
        char *one = panel_subject(panel_picture_record(p, i));
        char *joined = NULL;
        if (asprintf(&joined, "%s%s%s", out, i ? " " : "", one) < 0) {
            joined = NULL;
        }
        free(one);
        free(out);
        out = joined;
    }
    return out;
}

/* ---- the cases ---- */

// std: yoke-reference:the-lvgl-panel.01
static const char *the_picture_is_the_opening_held_by_subject(void) {
    panel_picture *p = panel_picture_make(the_opening());
    char *held = subjects(p);
    const char *result = NULL;
    if (panel_picture_at(p) != 4 || panel_picture_count(p) != 4 ||
        strcmp(held, "instance channel/panel unit/acquire unit/provision-store") != 0) {
        result = fail("the picture is at %llu and holds [%s]", (unsigned long long)panel_picture_at(p), held);
    }
    free(held);
    panel_picture_free(p);
    return result;
}

typedef struct reading {
    int calls;
    int answer; /* 0 a record, 1 gone, -1 cannot be read */
} reading;

static int read_again(void *context, const char *kind, const char *identity, Yoke__Interface__V1__Record **now) {
    reading *r = context;
    r->calls++;
    (void)kind;
    if (r->answer == 0) {
        *now = unit_record(identity, "Failed", "calibrate", NULL);
    }
    return r->answer;
}

static Yoke__Interface__V1__Event event_of(uint64_t seq, const char *kind, const char *identity) {
    static Yoke__Interface__V1__Subject subject;
    yoke__interface__v1__subject__init(&subject);
    subject.kind = (char *)kind;
    subject.identity = (char *)identity;
    Yoke__Interface__V1__Event e;
    yoke__interface__v1__event__init(&e);
    e.seq = seq;
    e.type = (char *)"unit.state.changed";
    e.subject = &subject;
    return e;
}

// std: yoke-reference:the-lvgl-panel.02
static const char *an_event_reads_its_subject_again_an_overflow_replaces_and_only_the_applied_is_confirmed(void) {
    panel_picture *p = panel_picture_make(the_opening());
    reading now = {.answer = 0};
    Yoke__Interface__V1__Event e5 = event_of(5, "unit", "acquire");
    if (panel_picture_apply(p, &e5, read_again, &now) != 0 || now.calls != 1 || panel_picture_at(p) != 5) {
        panel_picture_free(p);
        return fail("an event was not applied: %d reads, at %llu", now.calls, (unsigned long long)panel_picture_at(p));
    }
    char *line = panel_unit_line(panel_picture_record(p, 2)->unit);
    int read_now = line != NULL && strstr(line, "unit acquire Failed") != NULL;
    free(line);
    if (!read_now) {
        panel_picture_free(p);
        return fail("the unit was not read again");
    }
    reading gone = {.answer = 1};
    Yoke__Interface__V1__Event e6 = event_of(6, "unit", "provision-store");
    if (panel_picture_apply(p, &e6, read_again, &gone) != 0 || panel_picture_count(p) != 3 || panel_picture_at(p) != 6) {
        panel_picture_free(p);
        return fail("a subject that is gone was not taken out");
    }
    reading broken = {.answer = -1};
    Yoke__Interface__V1__Event e7 = event_of(7, "unit", "acquire");
    int refused = panel_picture_apply(p, &e7, read_again, &broken);
    if (refused != -1 || panel_picture_at(p) != 6 || panel_picture_count(p) != 3) {
        panel_picture_free(p);
        return fail("an event whose subject could not be read was applied (%d, at %llu)", refused,
                    (unsigned long long)panel_picture_at(p));
    }
    Yoke__Interface__V1__Snapshot fresh;
    yoke__interface__v1__snapshot__init(&fresh);
    fresh.at = 9;
    Yoke__Interface__V1__Record *only[1] = {instance_record()};
    fresh.records = only;
    fresh.n_records = 1;
    panel_picture_replace(p, &fresh);
    int replaced = panel_picture_at(p) == 9 && panel_picture_count(p) == 1;
    panel_picture_free(p);
    NEED(replaced, "an overflow did not replace the picture");
    return NULL;
}

typedef struct clicks {
    char unit[64], type[64];
    int commands, asks;
} clicks;

static char *said_command(void *context, const char *unit, const char *type) {
    clicks *c = context;
    c->commands++;
    snprintf(c->unit, sizeof c->unit, "%s", unit);
    snprintf(c->type, sizeof c->type, "%s", type);
    return strdup("OUTCOME_DONE calibrated");
}

static char *said_ask(void *context, const char *unit, const char *type) {
    clicks *c = context;
    c->asks++;
    snprintf(c->unit, sizeof c->unit, "%s", unit);
    snprintf(c->type, sizeof c->type, "%s", type);
    return strdup("nominal");
}

static panel_ui *the_screen(clicks *c, panel_picture **picture) {
    lv_display_t *display = panel_display_open("offscreen", 480, 320);
    if (display == NULL) {
        return NULL;
    }
    panel_acts acts = {.context = c, .command = said_command, .ask = said_ask};
    panel_ui *ui = panel_ui_make(lv_screen_active(), &acts);
    *picture = panel_picture_make(the_opening());
    panel_ui_show(ui, *picture);
    return ui;
}

// std: yoke-reference:the-lvgl-panel.03
static const char *the_screen_is_composed_from_the_picture(void) {
    clicks c = {0};
    panel_picture *picture;
    panel_ui *ui = the_screen(&c, &picture);
    NEED(ui != NULL, "the display cannot be opened");
    NEED(strcmp(panel_ui_channel_text(ui), "channel panel local attached") == 0, "the channel line is %s",
         panel_ui_channel_text(ui));
    NEED(panel_ui_units(ui) == 2, "the screen shows %zu units", panel_ui_units(ui));
    NEED(strcmp(panel_ui_unit_text(ui, 0), "unit acquire Running commands=[calibrate] queries=[head-status]") == 0,
         "the first unit reads %s", panel_ui_unit_text(ui, 0));
    NEED(strcmp(panel_ui_unit_text(ui, 1), "unit provision-store Completed commands=[] queries=[]") == 0,
         "the second unit reads %s", panel_ui_unit_text(ui, 1));
    NEED(panel_ui_button(ui, "acquire", "calibrate") != NULL && panel_ui_button(ui, "acquire", "head-status") != NULL,
         "a command or a question has no button");
    NEED(panel_ui_button(ui, "provision-store", "calibrate") == NULL, "a unit has a button for what it was not given");
    panel_ui_free(ui);
    panel_picture_free(picture);
    return NULL;
}

// std: yoke-reference:the-lvgl-panel.04
static const char *a_button_does_what_the_panel_is_told_and_the_screen_says_what_came_of_it(void) {
    clicks c = {0};
    panel_picture *picture;
    panel_ui *ui = the_screen(&c, &picture);
    NEED(ui != NULL, "the display cannot be opened");
    lv_obj_send_event(panel_ui_button(ui, "acquire", "calibrate"), LV_EVENT_CLICKED, NULL);
    NEED(c.commands == 1 && c.asks == 0 && strcmp(c.unit, "acquire") == 0 && strcmp(c.type, "calibrate") == 0,
         "the command button did %d commands and %d questions, of %s:%s", c.commands, c.asks, c.unit, c.type);
    NEED(strcmp(panel_ui_status_text(ui), "OUTCOME_DONE calibrated") == 0, "the screen says %s", panel_ui_status_text(ui));
    lv_obj_send_event(panel_ui_button(ui, "acquire", "head-status"), LV_EVENT_CLICKED, NULL);
    NEED(c.asks == 1 && strcmp(c.type, "head-status") == 0, "the question button did not ask");
    NEED(strcmp(panel_ui_status_text(ui), "nominal") == 0, "the screen says %s", panel_ui_status_text(ui));
    panel_ui_free(ui);
    panel_picture_free(picture);
    return NULL;
}

// std: yoke-reference:the-lvgl-panel.05
static const char *the_screen_is_drawn_to_the_display(void) {
    clicks c = {0};
    panel_picture *picture;
    panel_ui *ui = the_screen(&c, &picture);
    NEED(ui != NULL, "the display cannot be opened");
    unsigned long before = panel_display_flushed();
    lv_refr_now(NULL);
    NEED(panel_display_flushed() > before, "the display was not drawn to");
    panel_ui_free(ui);
    panel_picture_free(picture);
    NEED(panel_display_open("nowhere", 480, 320) == NULL, "a display that is not one was opened");
    return NULL;
}

int main(void) {
    static const struct {
        const char *id;
        const char *(*run)(void);
    } cases[] = {
        {"yoke-reference:the-lvgl-panel.01", the_picture_is_the_opening_held_by_subject},
        {"yoke-reference:the-lvgl-panel.02",
         an_event_reads_its_subject_again_an_overflow_replaces_and_only_the_applied_is_confirmed},
        {"yoke-reference:the-lvgl-panel.03", the_screen_is_composed_from_the_picture},
        {"yoke-reference:the-lvgl-panel.04", a_button_does_what_the_panel_is_told_and_the_screen_says_what_came_of_it},
        {"yoke-reference:the-lvgl-panel.05", the_screen_is_drawn_to_the_display},
    };
    int status = 0;
    for (size_t i = 0; i < sizeof cases / sizeof *cases; i++) {
        const char *failed = cases[i].run();
        if (failed == NULL) {
            printf("pass  %s\n", cases[i].id);
        } else {
            printf("FAIL  %s — %s\n", cases[i].id, failed);
            status = 1;
        }
    }
    return status;
}
