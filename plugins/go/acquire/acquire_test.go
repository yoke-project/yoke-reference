package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/yoke-project/yoke-reference/plugins/go/acquire/spectrometer"
	"github.com/yoke-project/yoke-sdk-go/plugin"
)

// session records what acquire does on it.
type session struct{ acts []any }

type (
	emitted struct {
		stream  string
		payload string
	}
	reported struct {
		occurrence string
		severity   plugin.Severity
		line       string
		detail     string
	}
	health struct {
		grade uint8
		line  string
	}
)

func (s *session) Emit(stream string, payload []byte) error {
	s.acts = append(s.acts, emitted{stream, string(payload)})
	return nil
}

func (s *session) Report(occurrence string, severity plugin.Severity, line string, detail []byte) error {
	s.acts = append(s.acts, reported{occurrence, severity, line, string(detail)})
	return nil
}

func (s *session) Health(grade uint8, line string) error {
	s.acts = append(s.acts, health{grade, line})
	return nil
}

func (s *session) only(kind any) []any {
	var out []any
	for _, a := range s.acts {
		if reflect.TypeOf(a) == reflect.TypeOf(kind) {
			out = append(out, a)
		}
	}
	return out
}

// bench is an instrument answered in memory, which falls silent while silent is set.
type bench struct {
	spectrometer.Instrument
	asked  []string
	silent bool
}

func (b *bench) Ask(command string) (string, error) {
	b.asked = append(b.asked, command)
	if b.silent {
		return "", errors.New("the instrument did not answer")
	}
	return b.Instrument.Answer(command), nil
}

// lamp reads the given drifts, one per reading, then 0.
func lamp(readings ...int) func(int) int {
	return func(n int) int {
		if n <= len(readings) {
			return readings[n-1]
		}
		return 0
	}
}

func granted(streams []string, occurrences []string) plugin.Admission {
	return plugin.Admission{Granted: plugin.Scope{Streams: streams, Occurrences: occurrences}}
}

func spectrumOf(label string, scan int) string {
	counts := make([]int, spectrometer.Bins)
	for bin := range counts {
		counts[bin] = spectrometer.Count(scan, bin)
	}
	b, _ := json.Marshal(spectrum{Label: label, Scan: scan, Counts: counts})
	return string(b)
}

func scan(t *testing.T, s *Station, times int) {
	t.Helper()
	for range times {
		if err := s.Scan(); err != nil {
			t.Fatal(err)
		}
	}
}

// std: yoke-reference:acquire.01
func TestTheManifestIsTheExamplesAndTheDeclarationGeneratesIt(t *testing.T) {
	committed, err := os.ReadFile("manifest.yaml")
	if err != nil {
		t.Fatal(err)
	}
	if generated := Declaration().Manifest(); !bytes.Equal(committed, generated) {
		t.Errorf("manifest.yaml is not what the declaration generates; run `go run . manifest > manifest.yaml`:\n%s", generated)
	}
	d := Declaration()
	want := plugin.Declaration{
		ID:          "com.yoke.station.acquire",
		Needs:       []string{"device:instrument"},
		Streams:     []plugin.Stream{{ID: "station.spectra"}, {ID: "station.diagnostics"}},
		Occurrences: []string{"calibration.drift"},
		Capabilities: []plugin.Capability{
			{Name: "stream.spectra.publish", Governs: plugin.Object{Stream: "station.spectra"}},
			{Name: "stream.diagnostics.publish", Governs: plugin.Object{Stream: "station.diagnostics"}},
			{Name: "occurrence.calibration.drift.report", Governs: plugin.Object{Occurrence: "calibration.drift"}},
		},
	}
	if !reflect.DeepEqual(d, want) {
		t.Errorf("the declaration is %+v", d)
	}
}

// std: yoke-reference:acquire.03
func TestASpectrumIsEmittedOnlyWhileItsStreamIsActivated(t *testing.T) {
	s, b := &session{}, &bench{}
	st := NewStation("bench a", "/dev/spectro-head-a", b, s, granted([]string{Spectra}, nil))
	scan(t, st, 1)
	st.Observe(plugin.Activated{Stream: Spectra, Transport: "ordered"})
	scan(t, st, 2)
	st.Observe(plugin.Stopped{Stream: Spectra})
	scan(t, st, 1)
	if n := strings.Count(strings.Join(b.asked, " "), "SCAN"); n != 4 {
		t.Errorf("the instrument was asked %d scans: %v", n, b.asked)
	}
	want := []any{emitted{Spectra, spectrumOf("bench a", 2)}, emitted{Spectra, spectrumOf("bench a", 3)}}
	if got := s.only(emitted{}); !reflect.DeepEqual(got, want) {
		t.Errorf("acquire emitted %v, want %v", got, want)
	}
}

// std: yoke-reference:acquire.04
func TestAWithheldStreamIsNeverWrittenToAndAcquiringGoesOn(t *testing.T) {
	s, b := &session{}, &bench{}
	st := NewStation("bench a", "/dev/spectro-head-a", b, s, granted([]string{Spectra}, nil))
	st.Observe(plugin.Activated{Stream: Spectra, Transport: "ordered"})
	scan(t, st, 3)
	var spectra int
	for _, e := range s.only(emitted{}) {
		if e.(emitted).stream != Spectra {
			t.Errorf("acquire emitted on %s", e.(emitted).stream)
		}
		spectra++
	}
	if spectra != 3 {
		t.Errorf("acquire emitted %d spectra", spectra)
	}
	if got, want := s.only(health{}), []any{health{0, "acquiring from /dev/spectro-head-a"}}; !reflect.DeepEqual(got, want) {
		t.Errorf("acquire reported %v", got)
	}
}

// std: yoke-reference:acquire.05
func TestADriftIsReportedOnceWithAcquiresOwnSeverity(t *testing.T) {
	s, b := &session{}, &bench{Instrument: spectrometer.Instrument{Lamp: lamp(0, 3, 4, 0, 3)}}
	st := NewStation("bench a", "/dev/spectro-head-a", b, s, granted(nil, []string{Drift}))
	// How many drifts have been reported once each reading is taken: at the second, and at the fifth.
	for reading, want := range []int{0, 1, 1, 1, 2} {
		scan(t, st, 1)
		if got := len(s.only(reported{})); got != want {
			t.Errorf("after reading %d, %d drifts were reported, want %d", reading+1, got, want)
		}
	}
	drift := reported{Drift, plugin.SeverityOf(50), "the reference lamp has drifted 3 parts in a thousand", `{"lamp_ppt":3}`}
	if got, want := s.only(reported{}), []any{drift, drift}; !reflect.DeepEqual(got, want) {
		t.Errorf("acquire reported %v, want %v", got, want)
	}
}

// std: yoke-reference:acquire.06
func TestADriftIsNotReportedWhenReportingItIsWithheld(t *testing.T) {
	s, b := &session{}, &bench{Instrument: spectrometer.Instrument{Lamp: lamp(3, 3)}}
	st := NewStation("bench a", "/dev/spectro-head-a", b, s, granted(nil, nil))
	scan(t, st, 2)
	if got := s.only(reported{}); len(got) != 0 {
		t.Errorf("acquire reported %v", got)
	}
	if n := strings.Count(strings.Join(b.asked, " "), "SCAN"); n != 2 {
		t.Errorf("the instrument was asked %d scans", n)
	}
}

// std: yoke-reference:acquire.07
func TestAnInstrumentThatFallsSilentIsSaidAndSoIsItsReturn(t *testing.T) {
	s, b := &session{}, &bench{}
	st := NewStation("bench a", "/dev/spectro-head-a", b, s, granted(nil, nil))
	scan(t, st, 1)
	b.silent = true
	scan(t, st, 2)
	b.silent = false
	scan(t, st, 1)
	acquiring := health{0, "acquiring from /dev/spectro-head-a"}
	want := []any{acquiring, health{60, "the instrument does not answer"}, acquiring}
	if got := s.only(health{}); !reflect.DeepEqual(got, want) {
		t.Errorf("acquire reported %v, want %v", got, want)
	}
}

// std: yoke-reference:acquire.08
func TestAcquireOpensTheDeviceByItsBoundNameRaw(t *testing.T) {
	master, path, slave, err := spectrometer.Pair()
	if err != nil {
		t.Fatal(err)
	}
	defer slave.Close()
	defer master.Close()
	link := filepath.Join(t.TempDir(), "spectro-head-a")
	if err := os.Symlink(path, link); err != nil {
		t.Fatal(err)
	}
	go (&spectrometer.Instrument{}).Serve(master)

	line, err := OpenLine(link)
	if err != nil {
		t.Fatal(err)
	}
	defer line.Close()
	s := &session{}
	st := NewStation("bench a", link, line, s, granted([]string{Spectra}, nil))
	st.Observe(plugin.Activated{Stream: Spectra, Transport: "ordered"})
	scan(t, st, 1)
	if got, want := s.only(emitted{}), []any{emitted{Spectra, spectrumOf("bench a", 1)}}; !reflect.DeepEqual(got, want) {
		t.Errorf("acquire emitted %v, want %v", got, want)
	}

	missing := filepath.Join(t.TempDir(), "spectro-head-z")
	if _, err := OpenLine(missing); err == nil || !strings.Contains(err.Error(), missing) {
		t.Errorf("opening %s failed with %v", missing, err)
	}
}
