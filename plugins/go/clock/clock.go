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
	return plugin.Declaration{}
}

// Acts are what the clock does on its Session. A started unit of the library does all three.
type Acts interface {
	Ack(c plugin.Command, outcome plugin.Outcome, line string) error
	Answer(q plugin.Question, payload []byte) error
	Report(occurrence string, severity plugin.Severity, line string, detail []byte) error
}

// Handle does what one event of the Session asks, reading the time from now.
func Handle(u Acts, event any, now func() time.Time) error {
	return nil
}
