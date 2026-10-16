package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"syscall"
	"time"

	"github.com/yoke-project/yoke-reference/plugins/go/acquire/spectrometer"
)

// What each command is answered with, and how long the instrument has to answer it.
var answers = map[string]string{"SCAN": "SPECTRUM", "LAMP": "LAMP"}

const answerWithin = 500 * time.Millisecond

// Line is the serial line to the instrument, opened raw by the name the unit was bound to.
type Line struct {
	f *os.File
	r *bufio.Reader
}

// OpenLine opens the device at path for reading and writing, raw. The path is consumed as given — a
// stable name, as a udev rule makes one — and never constructed.
func OpenLine(path string) (*Line, error) {
	f, err := os.OpenFile(path, os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return nil, fmt.Errorf("the instrument at %s cannot be opened: %w", path, err)
	}
	if err := spectrometer.MakeRaw(f); err != nil {
		f.Close()
		return nil, err
	}
	return &Line{f: f, r: bufio.NewReader(f)}, nil
}

// Ask writes one command and reads lines until the one that answers it. A line answering something else
// is a late answer to a command already given up on, and is passed over.
func (l *Line) Ask(command string) (string, error) {
	if _, err := io.WriteString(l.f, command+"\n"); err != nil {
		return "", err
	}
	if err := l.f.SetReadDeadline(time.Now().Add(answerWithin)); err != nil {
		return "", err
	}
	for {
		line, err := l.r.ReadString('\n')
		if err != nil {
			if errors.Is(err, os.ErrDeadlineExceeded) {
				return "", fmt.Errorf("the instrument did not answer %s within %s", command, answerWithin)
			}
			return "", err
		}
		line = strings.TrimSpace(line)
		if word, _, _ := strings.Cut(line, " "); word == answers[command] {
			return line, nil
		}
	}
}

// Close closes the line.
func (l *Line) Close() error { return l.f.Close() }
