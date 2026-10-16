// Package layout is what the example's two oneshots do to the archive's store: prepare it, and carry it
// from one layout to the next. The layout is written in the store's own `layout` file, which the archive
// reads, so the three programs agree on it without knowing each other.
package layout

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// The layouts a store can be in: v1 keeps every dataset in `datasets/`, v2 one directory per day.
const (
	V1 = "v1"
	V2 = "v2"
)

// ErrUnprepared is a store nobody prepared: it holds no layout.
var ErrUnprepared = errors.New("the store was never prepared: it holds no layout")

// Of is the layout the store at root says it has.
func Of(root string) (string, error) {
	data, err := os.ReadFile(filepath.Join(root, "layout"))
	if errors.Is(err, fs.ErrNotExist) {
		return "", ErrUnprepared
	}
	if err != nil {
		return "", err
	}
	l := strings.TrimSpace(string(data))
	if l != V1 && l != V2 {
		return l, fmt.Errorf("the store is in the layout %q, which is neither %s nor %s", l, V1, V2)
	}
	return l, nil
}

// write writes the layout file whole, through a file renamed over the old one, so that a reader sees one
// layout or the other.
func write(root, layout string) error {
	tmp := filepath.Join(root, ".layout.writing")
	if err := os.WriteFile(tmp, []byte(layout+"\n"), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, filepath.Join(root, "layout"))
}

// Provision prepares the store at root in the layout v1, with its datasets directory. A store already
// prepared is left as it is; one in a layout this program does not know is refused, untouched.
func Provision(root string) error {
	if _, err := Of(root); !errors.Is(err, ErrUnprepared) {
		return err
	}
	if err := os.MkdirAll(filepath.Join(root, "datasets"), 0o755); err != nil {
		return err
	}
	return write(root, V1)
}

// Migrate carries the store at root from v1 to v2: every dataset at the top of `datasets/` moves under
// the day it was written, keeping its name and its time, and the layout is written last. A migration
// interrupted is finished by running it again; a store already in v2 is left alone.
func Migrate(root string) error {
	l, err := Of(root)
	if err != nil {
		return err
	}
	if l == V2 {
		return nil
	}
	dir := filepath.Join(root, "datasets")
	entries, err := os.ReadDir(dir)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		info, err := e.Info()
		if err != nil {
			return err
		}
		day := filepath.Join(dir, info.ModTime().UTC().Format(time.DateOnly))
		if err := os.MkdirAll(day, 0o755); err != nil {
			return err
		}
		if err := os.Rename(filepath.Join(dir, e.Name()), filepath.Join(day, e.Name())); err != nil {
			return err
		}
	}
	return write(root, V2)
}
