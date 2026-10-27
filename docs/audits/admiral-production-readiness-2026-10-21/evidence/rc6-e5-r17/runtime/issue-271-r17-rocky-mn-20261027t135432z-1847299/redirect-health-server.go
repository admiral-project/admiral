// Tiny static HTTP service used to verify that Fleet does not follow a
// workload-controlled redirect during health checks.
package main

import (
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	target := os.Getenv("REDIRECT_TARGET")
	if target == "" {
		log.Fatal("REDIRECT_TARGET is required")
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Location", target)
		w.WriteHeader(http.StatusFound)
	})
	server := &http.Server{
		Addr:              ":8080",
		Handler:           mux,
		ReadHeaderTimeout: 2 * time.Second,
	}
	log.Fatal(server.ListenAndServe())
}
