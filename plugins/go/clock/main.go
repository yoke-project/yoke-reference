package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/yoke-project/yoke-sdk-go/plugin"
)

func main() {
	// `clock manifest` prints the Manifest the declaration generates, which is installed beside the binary.
	if len(os.Args) == 2 && os.Args[1] == "manifest" {
		os.Stdout.Write(Declaration().Manifest())
		return
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()
	u, err := plugin.Start(ctx, Declaration())
	if err != nil {
		fmt.Fprintln(os.Stderr, "clock:", err)
		os.Exit(1)
	}
	for {
		select {
		case event, open := <-u.Events():
			if !open {
				return
			}
			if err := Handle(u, event, time.Now); err != nil {
				fmt.Fprintln(os.Stderr, "clock:", err)
			}
		case <-ctx.Done():
			// Asked to stop: close the Session in order, and leave once it has ended.
			u.Close()
			<-u.Done()
			return
		}
	}
}
