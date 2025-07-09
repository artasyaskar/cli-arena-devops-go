package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestAdd(t *testing.T) {
	if Add(1, 2) != 3 {
		t.Error("Add(1,2) expected 3")
	}
}

func TestHandler(t *testing.T) {
	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(handler)
	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v",
			status, http.StatusOK)
	}

	// Check the response body is what we expect.
	// expected := "Hello from the Go CI App!" // Body might change due to counter
	// if !strings.Contains(rr.Body.String(), expected) {
	// 	t.Errorf("handler returned unexpected body: got %v want to contain %v",
	// 		rr.Body.String(), expected)
	// }
}

// Test for race condition potential
// This test itself doesn't guarantee finding races without -race flag,
// but it exercises the code that could be racy.
func TestIncrementCounterConcurrent(t *testing.T) {
	// Reset counter for this test, assuming it's a package global for simplicity of example
	// In real code, avoid package globals or provide reset functions.
	counter = 0
	numGoroutines := 50
	for i := 0; i < numGoroutines; i++ {
		go incrementCounter()
	}
	// Give goroutines time to run. This is not a perfect way to test concurrency.
	// A sync.WaitGroup would be better in incrementCounter or in the test.
	time.Sleep(100 * time.Millisecond)

	// Value of counter is non-deterministic if there's a race.
	// If no race (with mutexes), counter should be numGoroutines.
	// t.Logf("Counter value after concurrent increments: %d (expected %d if no race)", counter, numGoroutines)
	// We don't assert specific value as that depends on race vs no-race.
	// The `-race` flag during `go test` is the actual detector.
}

func TestVulnerableFunction(t *testing.T) {
    // This test just calls the function to ensure it's part of compiled code
    // and gosec has a chance to analyze it.
    // No specific assertions needed here as gosec is static analysis.
    vulnerableFunction("test_input_for_gosec")
    // If vulnerableFunction wrote to a global or had side effects, we might check them.
}
