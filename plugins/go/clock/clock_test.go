package main

import (
	"bytes"
	"os"
	"reflect"
	"testing"
	"time"

	"github.com/yoke-project/yoke-sdk-go/plugin"
)

// session records what the clock does on it.
type session struct{ acts []any }

type (
	acked struct {
		c       plugin.Command
		outcome plugin.Outcome
		line    string
	}
	answered struct {
		q       plugin.Question
		payload string
	}
	reported struct {
		occurrence string
		severity   plugin.Severity
		line       string
	}
)

func (s *session) Ack(c plugin.Command, outcome plugin.Outcome, line string) error {
	s.acts = append(s.acts, acked{c, outcome, line})
	return nil
}

func (s *session) Answer(q plugin.Question, payload []byte) error {
	s.acts = append(s.acts, answered{q, string(payload)})
	return nil
}

func (s *session) Report(occurrence string, severity plugin.Severity, line string, _ []byte) error {
	s.acts = append(s.acts, reported{occurrence, severity, line})
	return nil
}

func noon() time.Time { return time.Date(2026, 9, 26, 14, 0, 0, 0, time.FixedZone("CEST", 2*60*60)) }

// std: yoke-reference:the-clock.01
func TestTheManifestIsTheOneTheDeclarationGenerates(t *testing.T) {
	committed, err := os.ReadFile("manifest.yaml")
	if err != nil {
		t.Fatal(err)
	}
	if generated := Declaration().Manifest(); !bytes.Equal(committed, generated) {
		t.Errorf("manifest.yaml is not what the declaration generates; run `go run . manifest > manifest.yaml`:\n%s", generated)
	}
	d := Declaration()
	if d.ID != "com.yoke.reference.clock" || len(d.Queries) != 1 || d.Queries[0] != "clock.now" ||
		len(d.Commands) != 1 || d.Commands[0] != "clock.mark" || len(d.Occurrences) != 1 || d.Occurrences[0] != "clock.marked" {
		t.Errorf("the declaration is %+v", d)
	}
	governed := map[string]bool{}
	for _, c := range d.Capabilities {
		governed[c.Governs.Query+c.Governs.Command+c.Governs.Occurrence] = true
	}
	if len(d.Capabilities) != 3 || !governed["clock.now"] || !governed["clock.mark"] || !governed["clock.marked"] {
		t.Errorf("the capabilities are %+v", d.Capabilities)
	}
}

// std: yoke-reference:the-clock.02
func TestAQuestionForTheTimeIsAnswered(t *testing.T) {
	s := &session{}
	q := plugin.Question{ID: "q-1", Type: "clock.now"}
	if err := Handle(s, q, noon); err != nil {
		t.Fatal(err)
	}
	if want := []any{answered{q, "2026-09-26T12:00:00Z"}}; !reflect.DeepEqual(s.acts, want) {
		t.Errorf("the clock did %+v", s.acts)
	}
}

// std: yoke-reference:the-clock.03
func TestAMarkIsAcknowledgedAndReported(t *testing.T) {
	s := &session{}
	c := plugin.Command{ID: "c-1", Type: "clock.mark"}
	if err := Handle(s, c, noon); err != nil {
		t.Fatal(err)
	}
	line := "marked at 2026-09-26T12:00:00Z"
	want := []any{acked{c, plugin.Done, line}, reported{"clock.marked", plugin.SeverityOf(10), line}}
	if !reflect.DeepEqual(s.acts, want) {
		t.Errorf("the clock did %+v, want %+v", s.acts, want)
	}
}
