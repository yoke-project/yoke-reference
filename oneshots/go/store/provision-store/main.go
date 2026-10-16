// Command provision-store is the example's unit that prepares the archive's store before anything writes
// to it, and exits.
//
//	provision-store <store>
package main

import (
	"fmt"
	"os"

	"github.com/yoke-project/yoke-reference/oneshots/go/store/layout"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "provision-store: provision-store <store>, the directory its unit binds")
		os.Exit(2)
	}
	if err := layout.Provision(os.Args[1]); err != nil {
		fmt.Fprintln(os.Stderr, "provision-store:", err)
		os.Exit(1)
	}
	fmt.Println("provision-store: the store at", os.Args[1], "is prepared")
}
