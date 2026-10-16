package store_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// built builds the two programs once, as their units run them.
func built(t *testing.T) (provision, migrate string) {
	t.Helper()
	bin := t.TempDir()
	for _, p := range []string{"provision-store", "migrate-store"} {
		if out, err := exec.Command("go", "build", "-o", filepath.Join(bin, p), "./"+p).CombinedOutput(); err != nil {
			t.Fatalf("%s does not build: %v\n%s", p, err, out)
		}
	}
	return filepath.Join(bin, "provision-store"), filepath.Join(bin, "migrate-store")
}

// run runs a program on a store, and returns its exit status and what it said.
func run(program, store string) (int, string) {
	out, err := exec.Command(program, store).CombinedOutput()
	if exit, ok := err.(*exec.ExitError); ok {
		return exit.ExitCode(), string(out)
	}
	return 0, string(out)
}

// tree is every file under root, with its contents, by its path relative to root.
func tree(t *testing.T, root string) map[string]string {
	t.Helper()
	out := map[string]string{}
	filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			data, _ := os.ReadFile(path)
			rel, _ := filepath.Rel(root, path)
			out[rel] = string(data)
		}
		return nil
	})
	return out
}

func dataset(t *testing.T, path, contents string, written time.Time) {
	t.Helper()
	os.MkdirAll(filepath.Dir(path), 0o755)
	if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
		t.Fatal(err)
	}
	os.Chtimes(path, written, written)
}

var (
	fifteenth = time.Date(2026, 10, 15, 9, 0, 0, 0, time.UTC)
	sixteenth = time.Date(2026, 10, 16, 9, 0, 0, 0, time.UTC)
)

// std: yoke-reference:the-store-oneshots.01
func TestProvisionStorePreparesAStoreOnce(t *testing.T) {
	provision, _ := built(t)

	empty := t.TempDir()
	if code, out := run(provision, empty); code != 0 {
		t.Fatalf("on an empty directory it exited %d: %s", code, out)
	}
	if got := tree(t, empty); len(got) != 1 || got["layout"] != "v1\n" {
		t.Errorf("the prepared store holds %v", got)
	}
	if info, err := os.Stat(filepath.Join(empty, "datasets")); err != nil || !info.IsDir() {
		t.Errorf("the prepared store has no datasets directory: %v", err)
	}

	prepared := t.TempDir()
	os.WriteFile(filepath.Join(prepared, "layout"), []byte("v1\n"), 0o644)
	dataset(t, filepath.Join(prepared, "datasets", "1.json"), `{"scan":1}`, fifteenth)
	before := tree(t, prepared)
	if code, out := run(provision, prepared); code != 0 || len(tree(t, prepared)) != len(before) || tree(t, prepared)["datasets/1.json"] != `{"scan":1}` {
		t.Errorf("on a prepared store it exited %d (%s) and left %v", code, out, tree(t, prepared))
	}

	unknown := t.TempDir()
	os.WriteFile(filepath.Join(unknown, "layout"), []byte("v9\n"), 0o644)
	if code, out := run(provision, unknown); code != 1 || !strings.Contains(out, "v9") || len(tree(t, unknown)) != 1 {
		t.Errorf("on a v9 store it exited %d: %s", code, out)
	}
}

// std: yoke-reference:the-store-oneshots.02
func TestMigrateStoreCarriesAV1StoreToV2(t *testing.T) {
	_, migrate := built(t)
	store := t.TempDir()
	os.WriteFile(filepath.Join(store, "layout"), []byte("v1\n"), 0o644)
	dataset(t, filepath.Join(store, "datasets", "1.json"), `{"scan":1}`, fifteenth)
	dataset(t, filepath.Join(store, "datasets", "2.json"), `{"scan":2}`, sixteenth)
	if code, out := run(migrate, store); code != 0 {
		t.Fatalf("it exited %d: %s", code, out)
	}
	want := map[string]string{"layout": "v2\n", "datasets/2026-10-15/1.json": `{"scan":1}`, "datasets/2026-10-16/2.json": `{"scan":2}`}
	if got := tree(t, store); len(got) != len(want) || got["layout"] != want["layout"] ||
		got["datasets/2026-10-15/1.json"] != want["datasets/2026-10-15/1.json"] || got["datasets/2026-10-16/2.json"] != want["datasets/2026-10-16/2.json"] {
		t.Errorf("the store holds %v", got)
	}
	if info, err := os.Stat(filepath.Join(store, "datasets", "2026-10-15", "1.json")); err != nil || !info.ModTime().Equal(fifteenth) {
		t.Errorf("the moved dataset lost its time: %v %v", info, err)
	}
}

// std: yoke-reference:the-store-oneshots.03
func TestAnInterruptedMigrationIsFinishedAndAMigratedStoreLeftAlone(t *testing.T) {
	_, migrate := built(t)

	halfway := t.TempDir()
	os.WriteFile(filepath.Join(halfway, "layout"), []byte("v1\n"), 0o644)
	dataset(t, filepath.Join(halfway, "datasets", "2026-10-15", "1.json"), `{"scan":1}`, fifteenth)
	dataset(t, filepath.Join(halfway, "datasets", "2.json"), `{"scan":2}`, sixteenth)
	if code, out := run(migrate, halfway); code != 0 {
		t.Fatalf("on a store halfway it exited %d: %s", code, out)
	}
	if got := tree(t, halfway); len(got) != 3 || got["layout"] != "v2\n" || got["datasets/2026-10-15/1.json"] == "" || got["datasets/2026-10-16/2.json"] == "" {
		t.Errorf("the store halfway holds %v", got)
	}

	migrated := t.TempDir()
	os.WriteFile(filepath.Join(migrated, "layout"), []byte("v2\n"), 0o644)
	dataset(t, filepath.Join(migrated, "datasets", "2026-10-16", "1.json"), `{"scan":1}`, sixteenth)
	before := tree(t, migrated)
	if code, out := run(migrate, migrated); code != 0 || len(tree(t, migrated)) != len(before) {
		t.Errorf("on a migrated store it exited %d (%s) and left %v", code, out, tree(t, migrated))
	}

	never := t.TempDir()
	if code, out := run(migrate, never); code != 1 || !strings.Contains(out, "never prepared") {
		t.Errorf("on a store never prepared it exited %d: %s", code, out)
	}
}
