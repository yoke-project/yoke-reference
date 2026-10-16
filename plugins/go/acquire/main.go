package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/yoke-project/yoke-sdk-go/plugin"
)

func main() {
	// `acquire manifest` prints the Manifest the declaration generates, which is installed beside the binary.
	if len(os.Args) == 2 && os.Args[1] == "manifest" {
		os.Stdout.Write(Declaration().Manifest())
		return
	}
	device := flag.String("device", "", "the serial device the unit binds as instrument")
	label := flag.String("label", "", "the instrument's label, carried with every spectrum")
	period := flag.Duration("period", time.Second, "how often a spectrum is taken")
	flag.Parse()
	if *device == "" {
		fmt.Fprintln(os.Stderr, "acquire: --device names the instrument, which the unit binds")
		os.Exit(2)
	}
	// The device is opened before registering: an instrument that cannot be reached is a launch that
	// failed, not a Session with nothing to do.
	line, err := OpenLine(*device)
	if err != nil {
		fmt.Fprintln(os.Stderr, "acquire:", err)
		os.Exit(1)
	}
	defer line.Close()
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()
	u, err := plugin.Start(ctx, Declaration())
	if err != nil {
		fmt.Fprintln(os.Stderr, "acquire:", err)
		os.Exit(1)
	}
	station := NewStation(*label, *device, line, u, u.Admission())
	scan := func() {
		if err := station.Scan(); err != nil {
			fmt.Fprintln(os.Stderr, "acquire:", err)
		}
	}
	// The library beats only once acquire has said how it is, and the first scan says it.
	scan()
	ticker := time.NewTicker(*period)
	defer ticker.Stop()
	for {
		select {
		case event, open := <-u.Events():
			if !open {
				return
			}
			station.Observe(event)
		case <-ticker.C:
			scan()
		case <-ctx.Done():
			// Asked to stop: close the Session in order, and leave once it has ended.
			u.Close()
			<-u.Done()
			return
		}
	}
}
