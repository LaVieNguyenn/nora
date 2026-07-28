package main

import (
	"testing"
	"time"
)

// A cache whose TTL is at or below the cadence of its only caller can never
// return a cached value: by the time the next call arrives the entry is already
// stale. Four of them shipped that way, so every full collect re-ran
// system_profiler for Bluetooth and power, re-walked ~/.Trash, and re-forked
// powermetrics.
//
// This pins the class rather than the four instances: any new expensive probe
// added to the full collect has to declare a TTL that outlives it.
func TestExpensiveCacheTTLsOutliveTheCollectInterval(t *testing.T) {
	cases := []struct {
		name string
		ttl  time.Duration
		// How stale the value may reasonably get. A reading that changes over
		// days does not need a TTL measured in seconds.
		wantAtLeast time.Duration
	}{
		{"bluetooth (system_profiler SPBluetoothDataType)", bluetoothCacheTTL, time.Minute},
		{"power (system_profiler SPPowerDataType)", powerCacheTTL, time.Minute},
		{"trash size (recursive walk of ~/.Trash)", trashSizeCacheTTL, time.Minute},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.ttl <= slowRefreshInterval {
				t.Errorf("TTL %v does not exceed the full-collect interval %v, so the cache never hits",
					tc.ttl, slowRefreshInterval)
			}
			if tc.ttl < tc.wantAtLeast {
				t.Errorf("TTL %v is below the intended floor %v", tc.ttl, tc.wantAtLeast)
			}
		})
	}
}

// powermetrics refuses to run without root. `mo status` runs as the user, so
// the probe can only ever fail, and forking it to relearn that on every full
// collect cost a process spawn plus the timeout budget.
func TestGPUUsageSkipsPowermetricsWithoutRoot(t *testing.T) {
	// The test process is unprivileged, so this exercises the early return.
	if got := getMacGPUUsage(); got != -1 {
		t.Errorf("expected -1 (unavailable) when not root, got %v", got)
	}
}
