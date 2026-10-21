#include "picture.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct panel_picture {
    uint64_t at;
    Yoke__Interface__V1__Record **records;
    size_t count;
};

static Yoke__Interface__V1__Record *copy_record(const Yoke__Interface__V1__Record *r) {
    size_t len = protobuf_c_message_get_packed_size(&r->base);
    unsigned char *bytes = malloc(len + 1);
    protobuf_c_message_pack(&r->base, bytes);
    Yoke__Interface__V1__Record *copy = yoke__interface__v1__record__unpack(NULL, len, bytes);
    free(bytes);
    return copy;
}

static void clear(panel_picture *p) {
    for (size_t i = 0; i < p->count; i++) {
        yoke__interface__v1__record__free_unpacked(p->records[i], NULL);
    }
    free(p->records);
    p->records = NULL;
    p->count = 0;
}

static void fill(panel_picture *p, const Yoke__Interface__V1__Snapshot *snapshot) {
    p->at = snapshot->at;
    p->count = snapshot->n_records;
    p->records = calloc(p->count ? p->count : 1, sizeof *p->records);
    for (size_t i = 0; i < p->count; i++) {
        p->records[i] = copy_record(snapshot->records[i]);
    }
}

panel_picture *panel_picture_make(const Yoke__Interface__V1__Snapshot *snapshot) {
    panel_picture *p = calloc(1, sizeof *p);
    fill(p, snapshot);
    return p;
}

void panel_picture_free(panel_picture *p) {
    if (p != NULL) {
        clear(p);
        free(p);
    }
}

uint64_t panel_picture_at(const panel_picture *p) { return p->at; }

size_t panel_picture_count(const panel_picture *p) { return p->count; }

const Yoke__Interface__V1__Record *panel_picture_record(const panel_picture *p, size_t i) {
    return i < p->count ? p->records[i] : NULL;
}

char *panel_subject(const Yoke__Interface__V1__Record *r) {
    const char *kind = "", *identity = "";
    switch (r->subject_case) {
    case YOKE__INTERFACE__V1__RECORD__SUBJECT_INSTANCE:
        kind = "instance";
        break;
    case YOKE__INTERFACE__V1__RECORD__SUBJECT_UNIT:
        kind = "unit";
        identity = r->unit->declared ? r->unit->declared->identity : "";
        break;
    case YOKE__INTERFACE__V1__RECORD__SUBJECT_CHANNEL:
        kind = "channel";
        identity = r->channel->declared ? r->channel->declared->name : "";
        break;
    default:
        break;
    }
    char *out = NULL;
    if (identity[0] != '\0') {
        if (asprintf(&out, "%s/%s", kind, identity) < 0) {
            out = NULL;
        }
    } else {
        out = strdup(kind);
    }
    return out;
}

void panel_picture_replace(panel_picture *p, const Yoke__Interface__V1__Snapshot *snapshot) {
    clear(p);
    fill(p, snapshot);
}

/* The index of a subject in the picture, or -1. */
static long find(const panel_picture *p, const char *subject) {
    for (size_t i = 0; i < p->count; i++) {
        char *at = panel_subject(p->records[i]);
        int same = at != NULL && strcmp(at, subject) == 0;
        free(at);
        if (same) {
            return (long)i;
        }
    }
    return -1;
}

int panel_picture_apply(panel_picture *p, const Yoke__Interface__V1__Event *event, panel_reader read, void *context) {
    const char *kind = event->subject ? event->subject->kind : "";
    const char *identity = event->subject ? event->subject->identity : "";
    if (kind[0] == '\0') {
        p->at = event->seq; /* an event about no subject changes nothing to read again */
        return 0;
    }
    Yoke__Interface__V1__Record *now = NULL;
    int got = read(context, kind, identity, &now);
    if (got < 0) {
        return -1;
    }
    char *subject = NULL;
    if (asprintf(&subject, "%s%s%s", kind, identity[0] ? "/" : "", identity) < 0) {
        return -1;
    }
    long at = find(p, subject);
    free(subject);
    if (got == 1) {
        if (at >= 0) {
            yoke__interface__v1__record__free_unpacked(p->records[at], NULL);
            memmove(&p->records[at], &p->records[at + 1], (p->count - (size_t)at - 1) * sizeof *p->records);
            p->count--;
        }
    } else if (at >= 0) {
        yoke__interface__v1__record__free_unpacked(p->records[at], NULL);
        p->records[at] = now;
    } else {
        p->records = realloc(p->records, (p->count + 1) * sizeof *p->records);
        p->records[p->count++] = now;
    }
    p->at = event->seq;
    return 0;
}

static char *joined(char **list, size_t n) {
    size_t len = 1;
    for (size_t i = 0; i < n; i++) {
        len += strlen(list[i]) + 1;
    }
    char *out = malloc(len);
    out[0] = '\0';
    for (size_t i = 0; i < n; i++) {
        if (i > 0) {
            strcat(out, ",");
        }
        strcat(out, list[i]);
    }
    return out;
}

char *panel_unit_line(const Yoke__Interface__V1__UnitRecord *u) {
    char *commands = u->addressed ? joined(u->addressed->commands, u->addressed->n_commands) : strdup("");
    char *queries = u->addressed ? joined(u->addressed->queries, u->addressed->n_queries) : strdup("");
    char *line = NULL;
    if (asprintf(&line, "unit %s %s commands=[%s] queries=[%s]", u->declared ? u->declared->identity : "",
                 u->observed ? u->observed->state : "", commands, queries) < 0) {
        line = NULL;
    }
    free(commands);
    free(queries);
    return line;
}
