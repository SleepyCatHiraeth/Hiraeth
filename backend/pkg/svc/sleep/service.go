package sleep

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"sync"

	"github.com/godbus/dbus/v5"

	"ambxst/backend/pkg/ipc"
)

// Service monitors login1 PrepareForSleep and Session.Lock signals,
// pushing SUSPEND/WAKE/LOCK events and running configured commands.
// Replaces sleep_monitor.sh and loginlock.sh.
type Service struct {
	conn        *dbus.Conn
	mu          sync.Mutex
	beforeSleep string
	afterSleep  string
	lockCMD     string

	subsMu sync.Mutex
	subs   []*ipc.Subscriber
}

func NewService() (*Service, error) {
	conn, err := dbus.SystemBus()
	if err != nil {
		return nil, fmt.Errorf("system bus: %w", err)
	}
	// A working default, rather than nothing until the shell says otherwise.
	//
	// lockCMD was empty until IdleService pushed it, and IdleService is a lazily
	// loaded QML singleton -- so whether `loginctl lock-session` actually locked
	// the screen depended on whether something had happened to instantiate it.
	// The idle configuration on this machine runs that command after five
	// minutes, and logind marks the session locked either way. A session
	// advertised as locked with an unlocked screen is the worst of both, so the
	// daemon locks on its own and lets the shell override the command later.
	return &Service{conn: conn, lockCMD: "ambxst lock"}, nil
}

func (s *Service) Close() {
	if s.conn != nil {
		s.conn.Close()
	}
}

// watch listens for logind signals for the whole life of the daemon.
//
// This used to live inside subscribe(), so the D-Bus match was only ever added
// when a client subscribed -- and nothing in the shell subscribes to this
// service. The result was that `loginctl lock-session`, which the idle
// configuration runs after five minutes, set logind's LockedHint and emitted
// Session.Lock into a void: the lock command never ran, the screen never
// locked, and the session was advertised as locked while the desktop stayed
// open. Signals that drive security-relevant behaviour cannot be conditional on
// somebody happening to be listening for notifications.
func (s *Service) watch() {
	if s.conn == nil {
		return
	}
	ch := make(chan *dbus.Signal, 16)
	s.conn.Signal(ch)

	if err := s.conn.AddMatchSignal(
		dbus.WithMatchObjectPath("/org/freedesktop/login1"),
		dbus.WithMatchInterface("org.freedesktop.login1.Manager"),
		dbus.WithMatchMember("PrepareForSleep"),
	); err != nil {
		return
	}
	// Scoped to THIS session's object path. Session.Lock is emitted on a
	// session object, and a match with only interface and member filters
	// receives it for every session on the machine -- so a second user, or a
	// second session of the same user, running `loginctl lock-session` would
	// have locked the owner's active desktop.
	sessionPath := ourSessionPath(s.conn)
	for _, member := range []string{"Lock", "Unlock"} {
		opts := []dbus.MatchOption{
			dbus.WithMatchInterface("org.freedesktop.login1.Session"),
			dbus.WithMatchMember(member),
		}
		if sessionPath != "" {
			opts = append(opts, dbus.WithMatchObjectPath(sessionPath))
		}
		if err := s.conn.AddMatchSignal(opts...); err != nil {
			return
		}
	}

	go func() {
		for sig := range ch {
			if sig == nil {
				continue
			}
			switch sig.Name {
			case "org.freedesktop.login1.Manager.PrepareForSleep":
				for _, body := range sig.Body {
					v, ok := body.(bool)
					if !ok {
						continue
					}
					if v {
						s.broadcast("SUSPEND")
						runDetached(s.command(func(c *Service) string { return c.beforeSleep }))
					} else {
						s.broadcast("WAKE")
						runDetached(s.command(func(c *Service) string { return c.afterSleep }))
					}
				}
			case "org.freedesktop.login1.Session.Lock":
				// Checked again here: if the session path could not be
				// resolved the match above is machine-wide, and locking the
				// wrong desktop is worse than missing a lock.
				if sessionPath != "" && sig.Path != sessionPath {
					continue
				}
				s.broadcast("LOCK")
				runDetached(s.command(func(c *Service) string { return c.lockCMD }))
			case "org.freedesktop.login1.Session.Unlock":
				s.broadcast("UNLOCK")
			}
		}
	}()
}

func (s *Service) command(pick func(*Service) string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return pick(s)
}

func (s *Service) broadcast(event string) {
	s.subsMu.Lock()
	subs := append([]*ipc.Subscriber(nil), s.subs...)
	s.subsMu.Unlock()
	for _, sub := range subs {
		sub.Send("sleep", map[string]any{"event": event})
	}
}

// Register wires the service into the server.
func (s *Service) Register(srv *ipc.Server) {
	s.watch()
	srv.Register(&ipc.Service{
		Name: "sleep",
		Methods: map[string]ipc.HandlerFunc{
			"setCommands": func(params json.RawMessage) (any, error) {
				var p struct {
					Before string `json:"before"`
					After  string `json:"after"`
					Lock   string `json:"lock"`
				}
				if err := json.Unmarshal(params, &p); err != nil {
					return nil, err
				}
				s.mu.Lock()
				if p.Before != "" {
					s.beforeSleep = p.Before
				}
				if p.After != "" {
					s.afterSleep = p.After
				}
				if p.Lock != "" {
					s.lockCMD = p.Lock
				}
				s.mu.Unlock()
				return "ok", nil
			},
		},
		Subscribe: s.subscribe,
	})
}

func (s *Service) subscribe(sub *ipc.Subscriber) {
	s.subsMu.Lock()
	s.subs = append(s.subs, sub)
	s.subsMu.Unlock()

	<-sub.StopCh()

	s.subsMu.Lock()
	for i, existing := range s.subs {
		if existing == sub {
			s.subs = append(s.subs[:i], s.subs[i+1:]...)
			break
		}
	}
	s.subsMu.Unlock()
}

// ourSessionPath resolves this process's logind session, or "" if it cannot be
// determined.
func ourSessionPath(conn *dbus.Conn) dbus.ObjectPath {
	mgr := conn.Object("org.freedesktop.login1", dbus.ObjectPath("/org/freedesktop/login1"))
	var path dbus.ObjectPath
	if id := os.Getenv("XDG_SESSION_ID"); id != "" {
		if err := mgr.Call("org.freedesktop.login1.Manager.GetSession", 0, id).Store(&path); err == nil {
			return path
		}
	}
	if err := mgr.Call("org.freedesktop.login1.Manager.GetSessionByPID", 0,
		uint32(os.Getpid())).Store(&path); err != nil {
		return ""
	}
	return path
}

func runDetached(cmd string) {
	if cmd == "" {
		return
	}
	exec.Command("sh", "-c", cmd).Start()
}
