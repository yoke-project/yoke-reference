// Command clock is a reference Plugin: a clock that tells the time when asked and marks it when told.
//
// It is written against the published Go plugin library like anyone's, and its module requires nothing
// that somebody outside the project could not obtain. Copy it as the start of a Plugin of your own.
package main

import (
	"time"

	"github.com/yoke-project/yoke-sdk-go/plugin"
)

// Declaration is what the clock says about itself: one question, one command, one occurrence, and the
// capability that governs each.
func Declaration() plugin.Declaration {
	return plugin.Declaration{
		ID:          "com.yoke.reference.clock",
		Commands:    []string{"clock.mark"},
		Queries:     []string{"clock.now"},
		Occurrences: []string{"clock.marked"},
		Capabilities: []plugin.Capability{
			{Name: "command.mark.accept", Governs: plugin.Object{Command: "clock.mark"}},
			{Name: "query.now.answer", Governs: plugin.Object{Query: "clock.now"}},
			{Name: "event.marked.report", Governs: plugin.Object{Occurrence: "clock.marked"}},
		},
	}
}

// A mark is routine: the clock states its severity itself, since the library chooses none for it.
var markSeverity = plugin.SeverityOf(10)

// Acts are what the clock does on its Session. A started unit of the library does all three.
type Acts interface {
	Ack(c plugin.Command, outcome plugin.Outcome, line string) error
	Answer(q plugin.Question, payload []byte) error
	Report(occurrence string, severity plugin.Severity, line string, detail []byte) error
}

// Handle does what one event of the Session asks, reading the time from now.
func Handle(u Acts, event any, now func() time.Time) error {
	instant := now().UTC().Format(time.RFC3339)
	switch e := event.(type) {
	case plugin.Question:
		if e.Type == "clock.now" {
			return u.Answer(e, []byte(instant))
		}
	case plugin.Command:
		if e.Type == "clock.mark" {
			line := "marked at " + instant
			if err := u.Ack(e, plugin.Done, line); err != nil {
				return err
			}
			return u.Report("clock.marked", markSeverity, line, nil)
		}
	}
	// Nothing else is declared, so nothing else is granted, and the Core sends nothing else.
	return nil
}
