package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestMainHandler(t *testing.T) {
	// Set a default port for testing if APP_PORT is not set
	os.Setenv("APP_PORT", "8083") // Use a different port for testing to avoid conflict

	// Create a request to pass to our handler. We don't have any query parameters for now, so nil is fine.
	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err)
	}

	// We create a ResponseRecorder (which satisfies http.ResponseWriter) to record the response.
	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(helloHandler) // Use the actual handler from main.go

	// Our handlers satisfy http.Handler, so we can call their ServeHTTP method
	// directly and pass in our Request and ResponseRecorder.
	handler.ServeHTTP(rr, req)

	// Check the status code is what we expect.
	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v",
			status, http.StatusOK)
	}

	// Check the response body is what we expect (or contains expected parts).
	// The handler returns headers as JSON. Let's check for Content-Type.
	expectedContentType := "application/json"
	if contentType := rr.Header().Get("Content-Type"); contentType != expectedContentType {
		t.Errorf("handler returned unexpected content type: got %v want %v",
			contentType, expectedContentType)
	}

	// Check if body contains some expected header, like "User-Agent" (usually present)
	// This is a simple check, more robust would be to unmarshal JSON and check keys.
	if testing.Verbose() { // Print body only in verbose mode
		t.Log("Response body:", rr.Body.String())
	}
	if rr.Body.String() == "" {
		t.Errorf("handler returned empty body")
	}
	// A very basic check that it's JSON-like
	if !(rr.Body.String()[0] == '{' && rr.Body.String()[len(rr.Body.String())-1] == '}') && !(rr.Body.String()[0] == '[' && rr.Body.String()[len(rr.Body.String())-1] == ']') {
		t.Errorf("response body does not look like JSON: %s", rr.Body.String())
	}


}

