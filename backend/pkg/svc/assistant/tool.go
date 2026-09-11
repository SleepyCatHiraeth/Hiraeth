package assistant

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"
)

// The tool layer. Stage 3, and built on what Stages 1 and 2 established rather
// than on the design that predates them.
//
// The design rule is the one the memory system already proved here: the model
// proposes, this package disposes. `modules/services/Ai.qml` is the
// counterexample and the reason the turret exists -- it advertises one tool,
// `run_shell_command`, and runs the model's output as ["bash","-c",args], which
// is one model-produced string holding full user authority.
//
// So four things are structural here, not conventions:
//
//   - A tool is a Go declaration with a fixed argv builder. There is no field
//     anywhere in this file that holds a command string, which is what makes
//     "never a shell" checkable rather than promised.
//   - Parameters are typed and validated before they become argv, and a value
//     can never become a flag.
//   - Every invocation passes one choke point, `invoke`, which is where policy
//     is enforced and the audit line is written. Nothing executes around it.
//   - Execution is bounded: the caller's context, an explicit timeout, its own
//     process group so it dies with the turn, and a cap on what comes back.
//
// Nothing here is exposed to the model. Advertising tools to the LLM is a
// separate change that should not happen until a human has read this file.

// ToolParam is one declared parameter.
type ToolParam struct {
	Name     string `json:"name"`
	Kind     string `json:"kind"` // "string" | "int" | "bool"
	Required bool   `json:"required"`
	Describe string `json:"describe"`
}

// Tool is a capability the assistant may be asked to use.
//
// `Build` returns the argv to run. It returns a slice, never a string, so there
// is no point at which a shell could be introduced without changing this type.
type Tool struct {
	Name             string
	Describe         string
	Params           []ToolParam
	RequiresApproval bool
	Timeout          time.Duration

	// Exactly one of these. Run is a native Go implementation and spawns
	// nothing, which is strictly safer and is what a tool should use when it
	// can; Build returns an argv for the cases that genuinely need a program.
	// Neither is a command string, which is what makes "never a shell"
	// a property of the type rather than a promise in a comment.
	Run   func(ctx context.Context, args map[string]any) (string, error)
	Build func(args map[string]any) ([]string, error)
}

var (
	toolsMu sync.RWMutex
	tools   = map[string]Tool{}
)

func registerTool(t Tool) {
	toolsMu.Lock()
	defer toolsMu.Unlock()
	tools[t.Name] = t
}

// maxToolOutput caps what a tool may return to the model. A tool that prints a
// gigabyte must not become a gigabyte of prompt.
const maxToolOutput = 8 << 10

// validateArgs checks a proposal against the declaration.
//
// A value can never become a flag: every argument is a separate argv element,
// and a string that looks like an option is still just a string in that slot.
// The check here is about types and required fields; the flag property comes
// from Build never concatenating.
func validateArgs(t Tool, args map[string]any) error {
	declared := map[string]ToolParam{}
	for _, p := range t.Params {
		declared[p.Name] = p
	}
	for name := range args {
		if _, ok := declared[name]; !ok {
			return fmt.Errorf("tool %q has no parameter %q", t.Name, name)
		}
	}
	for _, p := range t.Params {
		v, present := args[p.Name]
		if !present {
			if p.Required {
				return fmt.Errorf("tool %q requires %q", t.Name, p.Name)
			}
			continue
		}
		switch p.Kind {
		case "string":
			s, ok := v.(string)
			if !ok {
				return fmt.Errorf("%q must be a string", p.Name)
			}
			// Control characters in an argument are never meaningful here and
			// are how a value smuggles structure into whatever reads it.
			for _, r := range s {
				if r < 0x20 && r != '\t' {
					return fmt.Errorf("%q contains a control character", p.Name)
				}
			}
		case "int":
			if _, ok := v.(float64); !ok { // JSON numbers
				return fmt.Errorf("%q must be a number", p.Name)
			}
		case "bool":
			if _, ok := v.(bool); !ok {
				return fmt.Errorf("%q must be true or false", p.Name)
			}
		default:
			return fmt.Errorf("tool %q declares unknown kind %q", t.Name, p.Kind)
		}
	}
	return nil
}

// invoke is the single path from "a call was proposed" to "something ran".
//
// `approved` is the user's decision. It is a parameter rather than a flag read
// from config, so that granting approval is always an act someone performed for
// this specific call.
func (s *Service) invoke(ctx context.Context, name string, args map[string]any, approved bool) (string, error) {
	toolsMu.RLock()
	t, ok := tools[name]
	toolsMu.RUnlock()
	if !ok {
		s.auditTool(name, "refused", "unknown tool")
		return "", fmt.Errorf("no such tool: %q", name)
	}
	if err := validateArgs(t, args); err != nil {
		s.auditTool(name, "refused", "invalid arguments")
		return "", err
	}
	if t.RequiresApproval {
		// Refused outright, and the boolean is ignored.
		//
		// `approved` arrives in the same unauthenticated JSON request that asks
		// to run the tool. The socket is 0600 so the caller is this user, but
		// nothing proves a human decided anything, or that a trusted UI sent
		// it -- any process running as the user could set it. Calling that an
		// approval boundary would be a lie told in a security-critical place.
		//
		// So until there is a real consent path -- a short-lived token minted
		// by the review card, bound to this one call -- a tool that needs
		// approval cannot run at all. No tool currently sets this, so nothing
		// is lost today except the pretence.
		_ = approved
		s.auditTool(name, "refused", "approval path not built")
		return "", fmt.Errorf("tool %q requires approval, and no approval path exists yet", name)
	}

	if t.Run != nil {
		// Native: nothing is spawned, so there is no argv, no process group and
		// no output cap to apply beyond the truncation below.
		runCtx, cancel := context.WithTimeout(ctx, timeoutOf(t))
		defer cancel()
		result, err := t.Run(runCtx, args)
		if err != nil {
			s.auditTool(name, "failed", "error")
			return "", fmt.Errorf("tool %q failed: %w", name, err)
		}
		if len(result) > maxToolOutput {
			result = result[:maxToolOutput] + "\n[output truncated]"
		}
		s.auditTool(name, "ran", "")
		return result, nil
	}
	if t.Build == nil {
		s.auditTool(name, "refused", "tool has no implementation")
		return "", fmt.Errorf("tool %q has no implementation", name)
	}

	argv, err := t.Build(args)
	if err != nil {
		s.auditTool(name, "refused", "could not build command")
		return "", err
	}
	if len(argv) == 0 {
		s.auditTool(name, "refused", "empty command")
		return "", fmt.Errorf("tool %q produced no command", name)
	}

	timeout := timeoutOf(t)
	runCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	cmd := exec.CommandContext(runCtx, argv[0], argv[1:]...)
	// Its own process group, so a cancelled turn takes the tool with it rather
	// than leaving it behind holding something.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	stderr := newCapped(2048)
	cmd.Stderr = stderr

	started := time.Now()
	out, err := cmd.Output()
	if runCtx.Err() == context.DeadlineExceeded {
		s.auditTool(name, "failed", "timed out")
		return "", fmt.Errorf("tool %q took longer than %s", name, timeout)
	}
	if err != nil {
		// The exit status only. A tool's stderr is output: it can carry its
		// arguments, a file it was reading, a recipient address, or model text,
		// and this journal is meant to hold none of those. The captured buffer
		// exists for a developer at a terminal, not for the log.
		s.auditTool(name, "failed", "exit error")
		logWorker("tool:"+name, time.Since(started), err, "")
		return "", fmt.Errorf("tool %q failed: %w", name, err)
	}

	result := strings.TrimSpace(string(out))
	if len(result) > maxToolOutput {
		result = result[:maxToolOutput] + "\n[output truncated]"
	}
	s.auditTool(name, "ran", "")
	logWorker("tool:"+name, time.Since(started), nil, "")
	return result, nil
}

// auditTool records that a call happened and what was decided.
//
// The tool name, the decision and a short reason -- never the arguments, never
// the output, never the model's reasoning, never what the user said. The memory
// audit follows the same rule for the same reason: a record of an action should
// not become a copy of its content.
func timeoutOf(t Tool) time.Duration {
	if t.Timeout > 0 {
		return t.Timeout
	}
	return 10 * time.Second
}

var toolNamePattern = regexp.MustCompile(`^[a-z][a-z0-9_]{0,63}$`)

func (s *Service) auditTool(name, decision, reason string) {
	// A name that is not a declared identifier is caller-controlled text, and
	// logging it verbatim let an IPC caller write whatever it liked into the
	// journal -- a secret, or a newline and a forged second line.
	if !toolNamePattern.MatchString(name) {
		name = "<invalid name>"
	}
	if reason != "" {
		logEvent("tool %s: %s (%s)", name, decision, reason)
		return
	}
	logEvent("tool %s: %s", name, decision)
}

// toolsList reports what exists, so a UI can show it without guessing.
func (s *Service) toolsList(json.RawMessage) (any, error) {
	toolsMu.RLock()
	defer toolsMu.RUnlock()
	out := make([]map[string]any, 0, len(tools))
	for _, t := range tools {
		out = append(out, map[string]any{
			"name": t.Name, "describe": t.Describe,
			"params": t.Params, "requires_approval": t.RequiresApproval,
		})
	}
	return map[string]any{"tools": out}, nil
}

func (s *Service) toolsInvoke(params json.RawMessage) (any, error) {
	// The master switch governs anything the assistant DOES, not just what it
	// says. Leaving action endpoints live while the UI shows "off" is exactly
	// the surprise that switch exists to prevent.
	s.mu.Lock()
	enabled := s.cfg.Enabled
	s.mu.Unlock()
	if !enabled {
		return nil, fmt.Errorf("the turret assistant is off; turn it on in Settings")
	}

	var p struct {
		Name     string         `json:"name"`
		Args     map[string]any `json:"args"`
		Approved bool           `json:"approved"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, err
	}
	ctx, done := s.backgroundContext(30 * time.Second)
	defer done()

	result, err := s.invoke(ctx, p.Name, p.Args, p.Approved)
	if err != nil {
		return nil, err
	}
	return map[string]any{"result": result}, nil
}
