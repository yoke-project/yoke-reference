/*
 * The panel, as the Core launches it: it attaches to the channel it is handed, composes its screen from the
 * opening, and keeps it current from a subscription of its own. `--socket <path>` attaches to a channel by
 * hand instead, and `--display <spec>` (or PANEL_DISPLAY) says where it draws: `offscreen`, the default, or
 * `fbdev:<path>`.
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "display.h"
#include "picture.h"
#include "ui.h"

static atomic_bool stopping;

static void on_signal(int sig) {
    (void)sig;
    atomic_store(&stopping, true);
}

/* What arrived on the subscription, waiting for the thread that draws. */
typedef struct delivery {
    Yoke__Interface__V1__Subscribed *item;
    struct delivery *next;
} delivery;

typedef struct panel {
    yoke_attachment *a;
    yoke_subscription *sub;
    pthread_mutex_t mu;
    delivery *head, *tail;
    atomic_bool ended;
} panel;

static void *follow(void *arg) {
    panel *p = arg;
    while (!atomic_load(&stopping)) {
        Yoke__Interface__V1__Subscribed *d = NULL;
        yoke_error err = {0};
        int got = yoke_subscription_next(p->sub, &d, 200, &err);
        yoke_error_clear(&err);
        if (got == YOKE_WAIT_TIMEOUT) {
            continue;
        }
        if (got != YOKE_WAIT_GOT) {
            atomic_store(&p->ended, true);
            return NULL;
        }
        delivery *n = calloc(1, sizeof *n);
        n->item = d;
        pthread_mutex_lock(&p->mu);
        if (p->tail != NULL) {
            p->tail->next = n;
        } else {
            p->head = n;
        }
        p->tail = n;
        pthread_mutex_unlock(&p->mu);
    }
    return NULL;
}

static delivery *take(panel *p) {
    pthread_mutex_lock(&p->mu);
    delivery *n = p->head;
    if (n != NULL) {
        p->head = n->next;
        if (p->head == NULL) {
            p->tail = NULL;
        }
    }
    pthread_mutex_unlock(&p->mu);
    return n;
}

/* A subject read again: its record now, which the picture keeps. */
static int read_again(void *context, const char *kind, const char *identity, Yoke__Interface__V1__Record **now) {
    panel *p = context;
    Yoke__Interface__V1__Response *answer = NULL;
    yoke_error err = {0};
    if (yoke_read(p->a, kind, identity, &answer, &err) != 0) {
        int gone = yoke_is_refusal(&err, "subject.unknown");
        yoke_error_clear(&err);
        return gone ? 1 : -1;
    }
    int result = 1;
    if (answer->read->n_records > 0) {
        size_t len = protobuf_c_message_get_packed_size(&answer->read->records[0]->base);
        unsigned char *bytes = malloc(len + 1);
        protobuf_c_message_pack(&answer->read->records[0]->base, bytes);
        *now = yoke__interface__v1__record__unpack(NULL, len, bytes);
        free(bytes);
        result = 0;
    }
    yoke_response_free(answer);
    return result;
}

static char *command(void *context, const char *unit, const char *type) {
    panel *p = context;
    Yoke__Interface__V1__Response *answer = NULL;
    yoke_error err = {0};
    char *said = NULL;
    if (yoke_command(p->a, unit, type, "", 0, &answer, &err) == 0) {
        const Yoke__Interface__V1__Acknowledged *ack = answer->command;
        const ProtobufCEnumValue *v = protobuf_c_enum_descriptor_get_value(
            &yoke__interface__v1__acknowledged__outcome__descriptor, (int)ack->outcome);
        if (asprintf(&said, "%s %s:%s %s", v ? v->name : "unknown", unit, type, ack->line) < 0) {
            said = NULL;
        }
        yoke_response_free(answer);
    } else if (asprintf(&said, "%s %s:%s", err.code ? err.code : "failed", unit, type) < 0) {
        said = NULL;
    }
    yoke_error_clear(&err);
    return said;
}

static char *ask(void *context, const char *unit, const char *type) {
    panel *p = context;
    Yoke__Interface__V1__Response *answer = NULL;
    yoke_error err = {0};
    char *said = NULL;
    if (yoke_ask(p->a, unit, type, "", 0, &answer, &err) == 0) {
        if (asprintf(&said, "%s:%s %.*s", unit, type, (int)answer->query->payload.len, answer->query->payload.data) < 0) {
            said = NULL;
        }
        yoke_response_free(answer);
    } else if (asprintf(&said, "%s %s:%s", err.code ? err.code : "failed", unit, type) < 0) {
        said = NULL;
    }
    yoke_error_clear(&err);
    return said;
}

/* The units the picture holds, one line each, under a heading the log can be read for. */
static void say_units(const char *heading, const panel_picture *picture) {
    for (size_t i = 0; i < panel_picture_count(picture); i++) {
        const Yoke__Interface__V1__Record *r = panel_picture_record(picture, i);
        if (r->subject_case == YOKE__INTERFACE__V1__RECORD__SUBJECT_UNIT) {
            char *line = panel_unit_line(r->unit);
            printf("%s: %s\n", heading, line ? line : "");
            free(line);
        }
    }
    fflush(stdout);
}

static const char *process_env(const char *name, void *context) {
    (void)context;
    return getenv(name);
}

int main(int argc, char **argv) {
    const char *socket = NULL, *display_spec = getenv("PANEL_DISPLAY");
    for (int i = 1; i + 1 < argc; i += 2) {
        if (strcmp(argv[i], "--socket") == 0) {
            socket = argv[i + 1];
        } else if (strcmp(argv[i], "--display") == 0) {
            display_spec = argv[i + 1];
        } else {
            fprintf(stderr, "panel: %s is not an option\n", argv[i]);
            return 2;
        }
    }
    setvbuf(stdout, NULL, _IOLBF, 0);
    char *address = NULL;
    yoke_error err = {0};
    if (socket != NULL) {
        address = strdup(socket);
    } else if (yoke_interface_managed(&address, process_env, NULL, &err) != 0) {
        fprintf(stderr, "panel: %s\n", err.message ? err.message : "no channel");
        return 2;
    }
    yoke_attach_options options = {.timeout_ms = 30000};
    panel p = {.mu = PTHREAD_MUTEX_INITIALIZER};
    p.a = yoke_attach(address, &options, &err);
    if (p.a == NULL) {
        fprintf(stderr, "panel: %s%s%s\n", err.code ? err.code : "", err.code ? ": " : "", err.message ? err.message : "failed");
        yoke_error_clear(&err);
        free(address);
        return 1;
    }
    printf("panel: attached to %s\n", address);
    free(address);

    lv_display_t *display = panel_display_open(display_spec ? display_spec : "offscreen", 480, 320);
    if (display == NULL) {
        fprintf(stderr, "panel: the display %s cannot be opened\n", display_spec ? display_spec : "offscreen");
        yoke_detach(p.a);
        return 1;
    }
    panel_picture *picture = panel_picture_make(yoke_picture(p.a));
    panel_acts acts = {.context = &p, .command = command, .ask = ask};
    panel_ui *ui = panel_ui_make(lv_screen_active(), &acts);
    panel_ui_show(ui, picture);
    say_units("composed", picture);

    struct sigaction sa = {.sa_handler = on_signal};
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);

    p.sub = yoke_subscribe(p.a, NULL, &err);
    pthread_t follower;
    bool following = p.sub != NULL;
    if (following) {
        pthread_create(&follower, NULL, follow, &p);
    } else {
        fprintf(stderr, "panel: the events could not be followed: %s\n", err.message ? err.message : "");
    }
    yoke_error_clear(&err);

    while (!atomic_load(&stopping) && !atomic_load(&p.ended)) {
        uint32_t wait = lv_timer_handler();
        for (delivery *n; (n = take(&p)) != NULL;) {
            Yoke__Interface__V1__Subscribed *d = n->item;
            uint64_t applied = 0;
            if (d->carries_case == YOKE__INTERFACE__V1__SUBSCRIBED__CARRIES_SNAPSHOT) {
                panel_picture_replace(picture, d->snapshot);
                applied = d->snapshot->at;
            } else if (d->carries_case == YOKE__INTERFACE__V1__SUBSCRIBED__CARRIES_OVERFLOW) {
                panel_picture_replace(picture, d->overflow);
                applied = d->overflow->at;
            } else if (d->carries_case == YOKE__INTERFACE__V1__SUBSCRIBED__CARRIES_EVENT &&
                       panel_picture_apply(picture, d->event, read_again, &p) == 0) {
                applied = d->event->seq;
            }
            if (applied != 0) {
                panel_ui_show(ui, picture);
                say_units("updated", picture);
                /* Only what has been applied is confirmed. */
                Yoke__Interface__V1__Response *confirmed = NULL;
                if (yoke_confirm(p.a, yoke_subscription_id(p.sub), applied, &confirmed, &err) != 0) {
                    yoke_error_clear(&err);
                }
                yoke_response_free(confirmed);
            }
            yoke_subscribed_free(d);
            free(n);
        }
        usleep((wait < 50 ? wait : 50) * 1000u + 1000u);
    }

    atomic_store(&stopping, true);
    if (following) {
        pthread_join(follower, NULL);
        yoke_subscription_close(p.sub);
    }
    panel_ui_free(ui);
    panel_picture_free(picture);
    yoke_detach(p.a);
    printf("panel: stopped\n");
    return 0;
}
