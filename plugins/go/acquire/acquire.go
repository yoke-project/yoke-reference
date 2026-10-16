// Command acquire is a reference Plugin: the unit of a bench spectrometer's console that drives the
// instrument over a serial port, publishes what it measures, and says when its reference lamp drifts.
//
// It is written against the published Go plugin library like anyone's. Its Manifest needs a device and
// names no path: which device is the unit's, bound by whoever composes the deployment and handed to it
// as `--device`. Copy it as the start of a Plugin that drives hardware.
package main

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/yoke-project/yoke-sdk-go/plugin"
)

// The names acquire declares.
const (
	Spectra     = "station.spectra"
	Diagnostics = "station.diagnostics"
	Drift       = "calibration.drift"
)

// Declaration is what acquire says about itself: the device class it needs, the two streams it may
// publish, the occurrence it may report, and the capability that governs each. Spectra are
// measurements — a lost one is a hole in an archive, a reordered one a lie about when — so neither
// stream tolerates loss or reorder, and the Core gives each an ordered path.
func Declaration() plugin.Declaration {
	return plugin.Declaration{
		ID:          "com.yoke.station.acquire",
		Needs:       []string{"device:instrument"},
		Streams:     []plugin.Stream{{ID: Spectra}, {ID: Diagnostics}},
		Occurrences: []string{Drift},
		Capabilities: []plugin.Capability{
			{Name: "stream.spectra.publish", Governs: plugin.Object{Stream: Spectra}},
			{Name: "stream.diagnostics.publish", Governs: plugin.Object{Stream: Diagnostics}},
			{Name: "occurrence.calibration.drift.report", Governs: plugin.Object{Occurrence: Drift}},
		},
	}
}

// A drift of this many parts in a thousand, either way, is one worth reporting.
const driftThreshold = 3

// How serious a drift is, on this instrument: acquire's statement, since only acquire knows what three
// parts in a thousand mean here, and the Core carries it without reading it.
var driftSeverity = plugin.SeverityOf(50)

// The health grades acquire reports: none of them is a state, only how it is.
const (
	gradeAcquiring = 0
	gradeSilent    = 60
)

// Instrument is the serial line to the spectrometer: one command written, its answer read back.
type Instrument interface {
	Ask(command string) (string, error)
}

// Acts are what acquire does on its Session. A started unit of the library does all three.
type Acts interface {
	Emit(stream string, payload []byte) error
	Report(occurrence string, severity plugin.Severity, line string, detail []byte) error
	Health(grade uint8, line string) error
}

// Station is acquire's state between two scans: what it may do, what is flowing, and what it last said.
type Station struct {
	label, device string
	instrument    Instrument
	acts          Acts

	mayReport bool            // the drift occurrence was granted at admission
	active    map[string]bool // the streams the Core has activated and not stopped
	drifted   bool            // the lamp was out at the last reading, and that was reported or withheld
	said      int             // the last grade reported; -1 before the first
}

// NewStation is acquire on one instrument, under the scope its admission granted.
func NewStation(label, device string, instrument Instrument, acts Acts, admission plugin.Admission) *Station {
	s := &Station{label: label, device: device, instrument: instrument, acts: acts, active: map[string]bool{}, said: -1}
	for _, o := range admission.Granted.Occurrences {
		if o == Drift {
			s.mayReport = true
		}
	}
	return s
}

// Observe follows the Session's activations: a stream is written to only between its activation and
// its stop, because only the Core creates its transport.
func (s *Station) Observe(event any) {
	switch e := event.(type) {
	case plugin.Activated:
		s.active[e.Stream] = true
	case plugin.Stopped:
		delete(s.active, e.Stream)
	}
}

type spectrum struct {
	Label  string `json:"label"`
	Scan   int    `json:"scan"`
	Counts []int  `json:"counts"`
}

type diagnostics struct {
	Label   string `json:"label"`
	LampPPT int    `json:"lamp_ppt"`
}

// Scan takes one spectrum and one lamp reading, publishes each on its stream if the stream flows, and
// says how the instrument is. An instrument that does not answer is not an error of acquire's: it is
// said in the health report and the next scan tries again.
func (s *Station) Scan() error {
	answer, err := s.instrument.Ask("SCAN")
	if err != nil {
		return s.say(gradeSilent, "the instrument does not answer")
	}
	taken, err := parseSpectrum(answer)
	if err != nil {
		return err
	}
	taken.Label = s.label
	if err := s.emit(Spectra, taken); err != nil {
		return err
	}
	answer, err = s.instrument.Ask("LAMP")
	if err != nil {
		return s.say(gradeSilent, "the instrument does not answer")
	}
	ppt, err := parseLamp(answer)
	if err != nil {
		return err
	}
	if err := s.emit(Diagnostics, diagnostics{Label: s.label, LampPPT: ppt}); err != nil {
		return err
	}
	if err := s.say(gradeAcquiring, "acquiring from "+s.device); err != nil {
		return err
	}
	return s.lamp(ppt)
}

// lamp reports a drift once, when it starts; a drift withheld is not reported, since reporting it would
// exceed the scope the Core granted.
func (s *Station) lamp(ppt int) error {
	out := ppt >= driftThreshold || ppt <= -driftThreshold
	if !out {
		s.drifted = false
		return nil
	}
	if s.drifted {
		return nil
	}
	s.drifted = true
	if !s.mayReport {
		return nil
	}
	detail, _ := json.Marshal(map[string]int{"lamp_ppt": ppt})
	line := fmt.Sprintf("the reference lamp has drifted %d parts in a thousand", abs(ppt))
	return s.acts.Report(Drift, driftSeverity, line, detail)
}

func (s *Station) emit(stream string, v any) error {
	if !s.active[stream] {
		return nil
	}
	payload, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return s.acts.Emit(stream, payload)
}

// say reports how acquire is when that has changed, and only then: the library repeats the last report
// on every beat.
func (s *Station) say(grade int, line string) error {
	if grade == s.said {
		return nil
	}
	s.said = grade
	return s.acts.Health(uint8(grade), line)
}

func parseSpectrum(answer string) (spectrum, error) {
	fields := strings.Fields(answer)
	if len(fields) < 2 || fields[0] != "SPECTRUM" {
		return spectrum{}, fmt.Errorf("the instrument answered a scan with %q", answer)
	}
	scan, err := strconv.Atoi(fields[1])
	if err != nil {
		return spectrum{}, fmt.Errorf("the instrument answered a scan with %q", answer)
	}
	taken := spectrum{Scan: scan, Counts: make([]int, 0, len(fields)-2)}
	for _, f := range fields[2:] {
		n, err := strconv.Atoi(f)
		if err != nil {
			return spectrum{}, fmt.Errorf("the instrument answered a scan with %q", answer)
		}
		taken.Counts = append(taken.Counts, n)
	}
	return taken, nil
}

func parseLamp(answer string) (int, error) {
	fields := strings.Fields(answer)
	if len(fields) != 2 || fields[0] != "LAMP" {
		return 0, fmt.Errorf("the instrument answered a lamp reading with %q", answer)
	}
	ppt, err := strconv.Atoi(fields[1])
	if err != nil {
		return 0, fmt.Errorf("the instrument answered a lamp reading with %q", answer)
	}
	return ppt, nil
}

func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
