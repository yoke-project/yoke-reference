// Package spectrometer plays the instrument acquire drives: a bench spectrometer speaking a line protocol
// over a serial port, here the master end of a pseudo-terminal pair, so that acquire can be run and
// tested with no instrument attached. It is a test program, and nothing in acquire knows it exists.
//
// The protocol is one line asked and one line answered, each ending in a newline:
//
//	SCAN   →  SPECTRUM <scan> <count> × 16    the scans are numbered from 1
//	LAMP   →  LAMP <ppt>                      the reference lamp's drift, in parts in a thousand
//	other  →  ERR <the line asked>
package spectrometer

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

// Bins is how many counts a spectrum carries.
const Bins = 16

// Instrument is the spectrometer's state: how many scans it has taken and lamp readings it has given.
type Instrument struct {
	// Lamp is the drift the lamp reads at its nth reading, counted from 1. Nil reads 0 at every one.
	Lamp func(reading int) int

	scans, readings int
}

// DriftingFrom is a lamp that reads 0 until its nth reading and ppt from then on; from 0 never drifts.
func DriftingFrom(n, ppt int) func(int) int {
	return func(reading int) int {
		if n > 0 && reading >= n {
			return ppt
		}
		return 0
	}
}

// Answer is what the instrument answers one line with, without its newline.
func (i *Instrument) Answer(line string) string {
	switch strings.TrimSpace(line) {
	case "SCAN":
		i.scans++
		fields := []string{"SPECTRUM", strconv.Itoa(i.scans)}
		for bin := range Bins {
			fields = append(fields, strconv.Itoa(Count(i.scans, bin)))
		}
		return strings.Join(fields, " ")
	case "LAMP":
		i.readings++
		ppt := 0
		if i.Lamp != nil {
			ppt = i.Lamp(i.readings)
		}
		return "LAMP " + strconv.Itoa(ppt)
	}
	return "ERR " + strings.TrimSpace(line)
}

// Count is what the instrument counts in one bin of one scan: a peak in the middle, moving a little with
// each scan, so that two spectra are never the same.
func Count(scan, bin int) int {
	distance := bin - Bins/2
	return 1000 - 10*distance*distance + scan%7
}

// Serve answers every line read from rw until rw is closed. A pseudo-terminal's master end reads an
// error while no process holds the slave end open, which is waited out rather than ended on.
func (i *Instrument) Serve(rw io.ReadWriter) error {
	r := bufio.NewReader(rw)
	for {
		line, err := r.ReadString('\n')
		if errors.Is(err, syscall.EIO) {
			time.Sleep(50 * time.Millisecond)
			continue
		}
		if err != nil {
			if errors.Is(err, io.EOF) || errors.Is(err, os.ErrClosed) {
				return nil
			}
			return err
		}
		if strings.TrimSpace(line) == "" {
			continue
		}
		if _, err := io.WriteString(rw, i.Answer(line)+"\n"); err != nil {
			return err
		}
	}
}

// Pair opens a pseudo-terminal pair: the master end the instrument serves, the slave end's path, and the
// slave end itself, held open so that the master never reads the error of nobody listening. The slave
// is raw, as a serial port is, so nothing written to it is echoed back.
func Pair() (master *os.File, path string, slave *os.File, err error) {
	master, err = os.OpenFile("/dev/ptmx", os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return nil, "", nil, err
	}
	fail := func(e error) (*os.File, string, *os.File, error) {
		master.Close()
		return nil, "", nil, e
	}
	var n int
	var ctlErr error
	raw, err := master.SyscallConn()
	if err != nil {
		return fail(err)
	}
	if err := raw.Control(func(fd uintptr) {
		if ctlErr = unix.IoctlSetPointerInt(int(fd), unix.TIOCSPTLCK, 0); ctlErr == nil {
			n, ctlErr = unix.IoctlGetInt(int(fd), unix.TIOCGPTN)
		}
	}); err != nil {
		return fail(err)
	}
	if ctlErr != nil {
		return fail(fmt.Errorf("the pseudo-terminal cannot be unlocked: %w", ctlErr))
	}
	path = fmt.Sprintf("/dev/pts/%d", n)
	slave, err = os.OpenFile(path, os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return fail(err)
	}
	if err := MakeRaw(slave); err != nil {
		slave.Close()
		return fail(err)
	}
	return master, path, slave, nil
}

// MakeRaw puts a terminal in raw mode: bytes pass as they are, nothing is echoed, nothing is a signal.
func MakeRaw(f *os.File) error {
	raw, err := f.SyscallConn()
	if err != nil {
		return err
	}
	var ctlErr error
	if err := raw.Control(func(fd uintptr) {
		var t *unix.Termios
		if t, ctlErr = unix.IoctlGetTermios(int(fd), unix.TCGETS); ctlErr != nil {
			return
		}
		t.Iflag &^= unix.IGNBRK | unix.BRKINT | unix.PARMRK | unix.ISTRIP | unix.INLCR | unix.IGNCR | unix.ICRNL | unix.IXON
		t.Oflag &^= unix.OPOST
		t.Lflag &^= unix.ECHO | unix.ECHONL | unix.ICANON | unix.ISIG | unix.IEXTEN
		t.Cflag &^= unix.CSIZE | unix.PARENB
		t.Cflag |= unix.CS8
		t.Cc[unix.VMIN], t.Cc[unix.VTIME] = 1, 0
		ctlErr = unix.IoctlSetTermios(int(fd), unix.TCSETS, t)
	}); err != nil {
		return err
	}
	if ctlErr != nil {
		return fmt.Errorf("the terminal %s cannot be made raw: %w", f.Name(), ctlErr)
	}
	return nil
}
