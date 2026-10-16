// Command instrument plays the spectrometer acquire drives, on the master end of a pseudo-terminal pair,
// and links the slave end at the path it is given: the stable name a unit binds, as a udev rule gives a
// real instrument one. It runs until it is stopped, and removes the link when it is.
//
//	instrument --link <path> [--drift-from <n>]
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/yoke-project/yoke-reference/plugins/go/acquire/spectrometer"
)

func main() {
	link := flag.String("link", "", "the path the slave end is linked at")
	driftFrom := flag.Int("drift-from", 0, "the lamp reading from which the lamp drifts 3 parts in a thousand; 0 never")
	flag.Parse()
	if *link == "" {
		fmt.Fprintln(os.Stderr, "instrument: --link names the path the instrument is reached at")
		os.Exit(2)
	}
	master, path, slave, err := spectrometer.Pair()
	if err != nil {
		fmt.Fprintln(os.Stderr, "instrument:", err)
		os.Exit(1)
	}
	defer slave.Close()
	if err := os.Symlink(path, *link); err != nil {
		fmt.Fprintln(os.Stderr, "instrument:", err)
		os.Exit(1)
	}
	defer os.Remove(*link)
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()
	go func() {
		<-ctx.Done()
		master.Close()
	}()
	fmt.Printf("instrument: %s at %s\n", *link, path)
	i := &spectrometer.Instrument{Lamp: spectrometer.DriftingFrom(*driftFrom, 3)}
	if err := i.Serve(master); err != nil && ctx.Err() == nil {
		fmt.Fprintln(os.Stderr, "instrument:", err)
		os.Exit(1)
	}
}
