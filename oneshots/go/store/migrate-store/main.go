// Command migrate-store is the example's unit that carries the archive's store from the layout 2.1.0
// wrote to the one 2.2.0 reads, and exits. It runs only where the stamp says an older version last ran.
//
//	migrate-store <store>
package main

import (
	"fmt"
	"os"

	"github.com/yoke-project/yoke-reference/oneshots/go/store/layout"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "migrate-store: migrate-store <store>, the directory its unit binds")
		os.Exit(2)
	}
	if err := layout.Migrate(os.Args[1]); err != nil {
		fmt.Fprintln(os.Stderr, "migrate-store:", err)
		os.Exit(1)
	}
	fmt.Println("migrate-store: the store at", os.Args[1], "is in", layout.V2)
}
