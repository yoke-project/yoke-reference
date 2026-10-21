/*
 * What the panel holds of what the channel sees: the opening picture, kept by subject, and what keeps it
 * current. An event reads its subject again; an overflow replaces the picture; and only what has been
 * applied is confirmed.
 */
#ifndef PANEL_PICTURE_H
#define PANEL_PICTURE_H

#include <stddef.h>
#include <stdint.h>

#include "yoke/interface.h"

typedef struct panel_picture panel_picture;

/* A picture made from an opening's snapshot; the records are copied. */
panel_picture *panel_picture_make(const Yoke__Interface__V1__Snapshot *snapshot);
void panel_picture_free(panel_picture *p);

/* The sequence the picture is current as of, and its records in the order they came. */
uint64_t panel_picture_at(const panel_picture *p);
size_t panel_picture_count(const panel_picture *p);
const Yoke__Interface__V1__Record *panel_picture_record(const panel_picture *p, size_t i);

/* A record's subject as `kind/identity`, in a buffer the caller frees. */
char *panel_subject(const Yoke__Interface__V1__Record *r);

/* The picture replaced by a snapshot: what an overflow brings. */
void panel_picture_replace(panel_picture *p, const Yoke__Interface__V1__Snapshot *snapshot);

/*
 * Reads a subject again: 0 with the record it is now, 1 when it is not there any more (the Core refused
 * `subject.unknown`), -1 when it cannot be read.
 */
typedef int (*panel_reader)(void *context, const char *kind, const char *identity, Yoke__Interface__V1__Record **now);

/*
 * An event applied: the subject it names read again and put in its place, or taken out when it is gone;
 * the picture is then current as of the event. 0 when it was applied, -1 when its subject could not be read,
 * in which case the picture is as it was and nothing is to be confirmed.
 */
int panel_picture_apply(panel_picture *p, const Yoke__Interface__V1__Event *event, panel_reader read, void *context);

/* One line for a unit, as the picture composes it: `unit clock Running commands=[…] queries=[…]`. */
char *panel_unit_line(const Yoke__Interface__V1__UnitRecord *u);

#endif
