package ipc

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

type testRequest struct {
	id     int
	method string
}

func startPipeServer(t *testing.T, server *Server) (net.Conn, <-chan struct{}) {
	t.Helper()
	serverConn, clientConn := net.Pipe()
	done := make(chan struct{})
	go func() {
		server.handleConn(serverConn)
		close(done)
	}()
	t.Cleanup(func() { clientConn.Close() })
	return clientConn, done
}

func sendRequest(t *testing.T, conn net.Conn, id int, method string) {
	t.Helper()
	sendRequests(t, conn, testRequest{id, method})
}

func sendRequests(t *testing.T, conn net.Conn, requests ...testRequest) {
	t.Helper()
	var batch []byte
	for _, request := range requests {
		data, err := json.Marshal(map[string]any{"id": request.id, "method": request.method, "params": map[string]any{}})
		if err != nil {
			t.Fatal(err)
		}
		batch = append(batch, data...)
		batch = append(batch, '\n')
	}
	if _, err := conn.Write(batch); err != nil {
		t.Fatal(err)
	}
}

func readResponse(t *testing.T, conn net.Conn, reader *bufio.Reader) Response {
	t.Helper()
	if err := conn.SetReadDeadline(time.Now().Add(2 * time.Second)); err != nil {
		t.Fatal(err)
	}
	line, err := reader.ReadBytes('\n')
	if err != nil {
		t.Fatal(err)
	}
	var response Response
	if err := json.Unmarshal(line, &response); err != nil {
		t.Fatalf("invalid response %q: %v", line, err)
	}
	return response
}

func responseID(t *testing.T, response Response) int {
	t.Helper()
	var id int
	if err := json.Unmarshal(response.ID, &id); err != nil {
		t.Fatal(err)
	}
	return id
}

func waitForSignal(t *testing.T, signal <-chan struct{}, what string) {
	t.Helper()
	select {
	case <-signal:
	case <-time.After(2 * time.Second):
		t.Fatalf("timed out waiting for %s", what)
	}
}

func TestSlowRequestDoesNotBlockUnrelatedService(t *testing.T) {
	server := NewServer("")
	slowStarted := make(chan struct{})
	releaseSlow := make(chan struct{})
	server.Register(&Service{Name: "slow", Methods: map[string]HandlerFunc{
		"run": func(json.RawMessage) (any, error) {
			close(slowStarted)
			<-releaseSlow
			return "slow", nil
		},
	}})
	server.Register(&Service{Name: "fast", Methods: map[string]HandlerFunc{
		"run": func(json.RawMessage) (any, error) { return "fast", nil },
	}})

	conn, _ := startPipeServer(t, server)
	reader := bufio.NewReader(conn)
	sendRequests(t, conn,
		testRequest{1, "slow.run"},
		testRequest{2, "fast.run"},
	)
	waitForSignal(t, slowStarted, "slow handler")

	response := readResponse(t, conn, reader)
	if id := responseID(t, response); id != 2 {
		close(releaseSlow)
		t.Fatalf("fast response id = %d, want 2", id)
	}
	close(releaseSlow)
	if id := responseID(t, readResponse(t, conn, reader)); id != 1 {
		t.Fatalf("slow response id = %d, want 1", id)
	}
}

func TestConcurrentResponsesAreCompleteJSONLines(t *testing.T) {
	server := NewServer("")
	const requests = 200
	for i := 0; i < maxConcurrentRequests; i++ {
		name := fmt.Sprintf("service%d", i)
		payload := strings.Repeat(string(rune('a'+i)), 32*1024)
		server.Register(&Service{Name: name, Methods: map[string]HandlerFunc{
			"run": func(json.RawMessage) (any, error) {
				time.Sleep(time.Millisecond)
				return payload, nil
			},
		}})
	}

	conn, _ := startPipeServer(t, server)
	reader := bufio.NewReader(conn)
	for id := 1; id <= requests; id++ {
		sendRequest(t, conn, id, fmt.Sprintf("service%d.run", id%maxConcurrentRequests))
	}

	seen := make(map[int]bool, requests)
	for range requests {
		response := readResponse(t, conn, reader)
		id := responseID(t, response)
		if seen[id] {
			t.Fatalf("duplicate response id %d", id)
		}
		seen[id] = true
		var payload string
		if err := json.Unmarshal(response.Result, &payload); err != nil {
			t.Fatalf("response %d has invalid result: %v", id, err)
		}
		if len(payload) != 32*1024 {
			t.Fatalf("response %d payload length = %d", id, len(payload))
		}
	}
}

func TestResponsesMatchIDsOutOfOrder(t *testing.T) {
	server := NewServer("")
	slowStarted := make(chan struct{})
	releaseSlow := make(chan struct{})
	server.Register(&Service{Name: "first", Methods: map[string]HandlerFunc{
		"run": func(json.RawMessage) (any, error) {
			close(slowStarted)
			<-releaseSlow
			return map[string]string{"request": "first"}, nil
		},
	}})
	server.Register(&Service{Name: "second", Methods: map[string]HandlerFunc{
		"run": func(json.RawMessage) (any, error) {
			return map[string]string{"request": "second"}, nil
		},
	}})

	conn, _ := startPipeServer(t, server)
	reader := bufio.NewReader(conn)
	sendRequests(t, conn,
		testRequest{41, "first.run"},
		testRequest{42, "second.run"},
	)
	waitForSignal(t, slowStarted, "first handler")
	response := readResponse(t, conn, reader)
	if id := responseID(t, response); id != 42 {
		close(releaseSlow)
		t.Fatalf("first completed response id = %d, want 42", id)
	}
	var result map[string]string
	if err := json.Unmarshal(response.Result, &result); err != nil {
		t.Fatal(err)
	}
	if result["request"] != "second" {
		t.Fatalf("response 42 result = %q", result["request"])
	}
	close(releaseSlow)
	response = readResponse(t, conn, reader)
	if id := responseID(t, response); id != 41 {
		t.Fatalf("second completed response id = %d, want 41", id)
	}
	if err := json.Unmarshal(response.Result, &result); err != nil {
		t.Fatal(err)
	}
	if result["request"] != "first" {
		t.Fatalf("response 41 result = %q", result["request"])
	}
}

func TestConcurrencyCapQueuesRequests(t *testing.T) {
	server := NewServer("")
	const requests = maxConcurrentRequests + 4
	started := make(chan struct{}, requests)
	release := make(chan struct{})
	var active atomic.Int32
	var maximum atomic.Int32
	for i := 0; i < requests; i++ {
		name := fmt.Sprintf("service%d", i)
		server.Register(&Service{Name: name, Methods: map[string]HandlerFunc{
			"run": func(json.RawMessage) (any, error) {
				current := active.Add(1)
				for {
					previous := maximum.Load()
					if current <= previous || maximum.CompareAndSwap(previous, current) {
						break
					}
				}
				started <- struct{}{}
				<-release
				active.Add(-1)
				return "ok", nil
			},
		}})
	}

	conn, _ := startPipeServer(t, server)
	reader := bufio.NewReader(conn)
	batch := make([]testRequest, requests)
	for id := 0; id < requests; id++ {
		batch[id].id = id + 1
		batch[id].method = fmt.Sprintf("service%d.run", id)
	}
	sendRequests(t, conn, batch...)
	for i := 0; i < maxConcurrentRequests; i++ {
		select {
		case <-started:
		case <-time.After(2 * time.Second):
			t.Fatalf("only %d handlers started", i)
		}
	}
	select {
	case <-started:
		t.Fatal("request started above concurrency cap")
	case <-time.After(100 * time.Millisecond):
	}
	close(release)
	for range requests {
		readResponse(t, conn, reader)
	}
	if got := maximum.Load(); got != maxConcurrentRequests {
		t.Fatalf("maximum concurrency = %d, want %d", got, maxConcurrentRequests)
	}
}

func TestSameServiceRequestsPreserveOrder(t *testing.T) {
	server := NewServer("")
	setStarted := make(chan struct{})
	releaseSet := make(chan struct{})
	var value atomic.Int32
	server.Register(&Service{Name: "state", Methods: map[string]HandlerFunc{
		"set": func(json.RawMessage) (any, error) {
			close(setStarted)
			<-releaseSet
			value.Store(7)
			return "ok", nil
		},
		"get": func(json.RawMessage) (any, error) { return value.Load(), nil },
	}})

	conn, _ := startPipeServer(t, server)
	reader := bufio.NewReader(conn)
	sendRequests(t, conn,
		testRequest{1, "state.set"},
		testRequest{2, "state.get"},
	)
	waitForSignal(t, setStarted, "set handler")
	close(releaseSet)
	if id := responseID(t, readResponse(t, conn, reader)); id != 1 {
		t.Fatalf("set response id = %d, want 1", id)
	}
	response := readResponse(t, conn, reader)
	if id := responseID(t, response); id != 2 {
		t.Fatalf("get response id = %d, want 2", id)
	}
	var got int
	if err := json.Unmarshal(response.Result, &got); err != nil {
		t.Fatal(err)
	}
	if got != 7 {
		t.Fatalf("get result = %d, want 7", got)
	}
}

func TestSubscriptionDeliversEventAndStopsOnClose(t *testing.T) {
	server := NewServer("")
	subscriberDone := make(chan struct{})
	server.Register(&Service{
		Name:    "events",
		Methods: map[string]HandlerFunc{},
		Subscribe: func(sub *Subscriber) {
			sub.Send("events.changed", map[string]int{"value": 7})
			<-sub.StopCh()
			close(subscriberDone)
		},
	})

	conn, serverDone := startPipeServer(t, server)
	reader := bufio.NewReader(conn)
	sendRequest(t, conn, 1, "subscribe")
	response := readResponse(t, conn, reader)
	if responseID(t, response) != 1 {
		t.Fatalf("subscription response has wrong id: %s", response.ID)
	}
	var event ServiceEvent
	if err := json.Unmarshal(response.Result, &event); err != nil {
		t.Fatal(err)
	}
	if event.Service != "events.changed" {
		t.Fatalf("event service = %q", event.Service)
	}
	conn.Close()
	waitForSignal(t, subscriberDone, "subscriber shutdown")
	waitForSignal(t, serverDone, "subscription connection shutdown")
}

func TestConnectionCloseWaitsForInflightHandlers(t *testing.T) {
	server := NewServer("")
	started := make(chan struct{})
	release := make(chan struct{})
	server.Register(&Service{Name: "work", Methods: map[string]HandlerFunc{
		"run": func(json.RawMessage) (any, error) {
			close(started)
			<-release
			return "ok", nil
		},
	}})

	conn, serverDone := startPipeServer(t, server)
	sendRequest(t, conn, 1, "work.run")
	waitForSignal(t, started, "handler start")
	conn.Close()
	select {
	case <-serverDone:
		t.Fatal("connection returned before in-flight handler")
	case <-time.After(50 * time.Millisecond):
	}
	close(release)
	waitForSignal(t, serverDone, "connection shutdown")
}
