package spectrometer

import (
	"bufio"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// std: yoke-reference:acquire.02
func TestTheInstrumentAnswersAcrossAPseudoTerminal(t *testing.T) {
	master, path, slave, err := Pair()
	if err != nil {
		t.Fatal(err)
	}
	defer slave.Close()
	defer master.Close()
	link := filepath.Join(t.TempDir(), "spectro-head-a")
	if err := os.Symlink(path, link); err != nil {
		t.Fatal(err)
	}
	go (&Instrument{Lamp: DriftingFrom(3, 3)}).Serve(master)

	f, err := os.OpenFile(link, os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err := MakeRaw(f); err != nil {
		t.Fatal(err)
	}
	r := bufio.NewReader(f)
	ask := func(line string) string {
		t.Helper()
		if _, err := io.WriteString(f, line+"\n"); err != nil {
			t.Fatal(err)
		}
		f.SetReadDeadline(time.Now().Add(2 * time.Second))
		answer, err := r.ReadString('\n')
		if err != nil {
			t.Fatalf("%s was not answered: %v", line, err)
		}
		return strings.TrimSuffix(answer, "\n")
	}

	want := []string{"SPECTRUM", "1"}
	for bin := range Bins {
		want = append(want, strconv.Itoa(Count(1, bin)))
	}
	if got := ask("SCAN"); got != strings.Join(want, " ") {
		t.Errorf("SCAN was answered %q", got)
	}
	for _, want := range []string{"LAMP 0", "LAMP 0", "LAMP 3"} {
		if got := ask("LAMP"); got != want {
			t.Errorf("LAMP was answered %q, want %q", got, want)
		}
	}
	// An echo would arrive before the answer, and be read as it.
	if got := ask("HELLO"); got != "ERR HELLO" {
		t.Errorf("HELLO was answered %q", got)
	}
}
