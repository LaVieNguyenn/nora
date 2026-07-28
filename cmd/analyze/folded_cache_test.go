package main

import "testing"

// Folded directories — node_modules, .git, Caches, DerivedData — are the
// largest and slowest subtrees on a developer machine, and they were the only
// ones that bypassed the cache layer entirely: every scan re-forked `du` over
// each of them. Measured on ~/Library, a rescan went from 6.0s to 0.1s once
// they were cached like every other subtree.
func TestFoldedDirSizeReusesCacheAndHonoursBypass(t *testing.T) {
	dir := t.TempDir()

	measured := 0
	measure := func() int64 {
		measured++
		// Above subdirCacheMinSize so the result is worth persisting; a folded
		// directory below that threshold is cheap enough to re-measure.
		return subdirCacheMinSize * 2
	}

	// Cold: nothing cached, so the measurement has to run.
	if got := foldedDirSize(dir, scanCacheReuse, measure); got != subdirCacheMinSize*2 {
		t.Fatalf("cold size = %d, want %d", got, subdirCacheMinSize*2)
	}
	if measured != 1 {
		t.Fatalf("cold measured %d times, want 1", measured)
	}

	// Warm: the same directory must come back from cache without measuring.
	if got := foldedDirSize(dir, scanCacheReuse, measure); got != subdirCacheMinSize*2 {
		t.Fatalf("warm size = %d, want %d", got, subdirCacheMinSize*2)
	}
	if measured != 1 {
		t.Fatalf("warm measured %d times, want 1 — the cache was not used", measured)
	}

	// A manual refresh must reach the filesystem again. Without this the user
	// has no way to correct a stale number, which is the whole reason the
	// bypass policy exists.
	if got := foldedDirSize(dir, scanCacheBypass, measure); got != subdirCacheMinSize*2 {
		t.Fatalf("bypass size = %d, want %d", got, subdirCacheMinSize*2)
	}
	if measured != 2 {
		t.Fatalf("bypass measured %d times, want 2 — bypass reused the cache", measured)
	}
}

// A folded directory too small to be worth caching should not leave a file
// behind: the store would fill with entries that save nothing.
func TestFoldedDirSizeSkipsCacheForSmallDirectories(t *testing.T) {
	dir := t.TempDir()

	measured := 0
	measure := func() int64 {
		measured++
		return 1024
	}

	_ = foldedDirSize(dir, scanCacheReuse, measure)
	_ = foldedDirSize(dir, scanCacheReuse, measure)

	if measured != 2 {
		t.Fatalf("measured %d times, want 2 — a sub-threshold directory was cached", measured)
	}
}
