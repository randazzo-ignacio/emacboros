# TODO -- Infrastructure & Multi-Tier Architecture

## Overview

Four-tier infrastructure for the agent framework, each tier with a distinct role. Built for the author's hardware first, abstracted for sharing later.

## Tier Definitions

| Tier | Host | Hardware | Role |
|------|------|----------|------|
| 1 | Local (Emacs host) | Variable, weakest | Orchestrator. Runs Emacs, agent framework, tool layer. No inference. Future sharing target: laptop-only users point at remote Ollama. |
| 2 | 0b.ar | 64GB RAM, 16 CPU cores | Execution sandbox. SSH-accessible remote code execution. Docker, compilers, test suites. Root on a real VPS, isolated from daily driver. |
| 3 | 192.168.2.69 | 96GB RAM, 12 cores, RTX 3080 10GB VRAM | Primary inference. Ollama with mid-to-large models. Workhorse for most agents. |
| 4 | Ollama Cloud | 500B+ models, high speed | Frontier inference, budgeted. Flat rate, weekly token limit. Deep reasoning agents only. Falls back to tier 3 when budget exhausted. |

## Phase 1: Remote Execution Tool (`execute_code_remote`)

### Goal
New gptel tool that SSHes to 0b.ar and runs shell commands remotely. Keeps `execute_code_local` for filesystem operations in the Emacs container. Remote tool handles compute: Docker, compilation, test suites, long-running processes.

### Design
- Tool function: `my-gptel-tool-execute-remote (command &optional timeout)`
- SSH to `root@0b.ar` (configurable via `defcustom`)
- Execute command, stream output back to agent
- Timeout support (default 120s, configurable)
- Output truncation if exceeds max size (configurable, default 64KB)
- Configurable SSH user, host, port, key path via `defcustom`
- Optional command whitelist (disabled by default = full root)
- Graceful degradation: if SSH connection fails, return error message to agent (do NOT fall back to local execution silently -- agent should know the remote is down)

### Prerequisites
- [ ] Generate SSH keypair in Emacs container: `ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""`
- [ ] Authorize public key on 0b.ar: add `~/.ssh/id_ed25519.pub` to `root@0b.ar:~/.ssh/authorized_keys`
- [ ] Verify: `ssh -o ConnectTimeout=5 root@0b.ar "echo ok"`
- [ ] Install Docker on 0b.ar (if not already)
- [ ] Consider: dedicated user with limited sudo instead of root (future hardening)

### File
- `/root/.emacs.d/init.d/remote_exec_tool.el`
- Load from `init.el`

### Tool registration
```
gptel-make-tool
  :name "execute_code_remote"
  :description "Execute bash/shell commands on a remote VPS (0b.ar) via SSH. The remote server has Docker, compilers, and full compute resources. Use for compute-heavy tasks, test suites, container orchestration, and anything that should not run in the local Emacs container."
  :args [
    :name "command" :type "string" :description "The bash command to execute on the remote server."
    :name "timeout" :type "integer" :description "Maximum seconds to wait. Default 120." :optional
  ]
```

### Security considerations
- Agent has root SSH access to a VPS. It can do anything.
- Mitigations (future): SSH key with forced command, dedicated user, command whitelist, rate limiting.
- Current stance: full root on test server. Acceptable risk for the author's use case.
- For sharing: tool detects whether remote is configured. If not, degrades to `execute_code_local` with a note that remote execution is unavailable.

---

## Phase 2: Multi-Backend Configuration & Routing Table

### Goal
Rewrite `gptel_setup.el` to define multiple Ollama backends. Add a routing table mapping agent names to `(backend . model)` pairs. Delegate tool reads this table and sets `gptel-backend` and `gptel-model` buffer-locally per delegate.

### Design

#### Backends
- **Ollama-3080**: `192.168.2.69:11434` (existing, tier 3)
  - Models: granite4.1:8b-q8_0, gpt-oss:20b, gpt-oss:120b, mistral-medium-3.5:128b, nemotron-3-super:120b
  - Params: temperature 0.7, top_p 0.95, num_ctx 1048576, num_predict 65536

- **Ollama-Cloud**: Ollama's cloud endpoint (tier 4)
  - Models: nemotron-3-ultra:cloud, glm-5.2:cloud, (500B+ models TBD)
  - Params: same as above
  - Needs: API key / endpoint URL from Ollama cloud
  - [ ] Get Ollama Cloud API details (endpoint URL, auth method)

#### Routing table
```elisp
(defvar my-gptel-agent-routing
  '(("mccarthy"    . (:backend ollama-cloud  :model "glm-5.2:cloud"))
    ("coder"      . (:backend ollama-3080   :model "granite4.1:8b-q8_0"))
    ("reviewer"   . (:backend ollama-3080   :model "gpt-oss:20b"))
    ("researcher" . (:backend ollama-cloud  :model "glm-5.2:cloud"))
    ("finch"      . (:backend ollama-3080   :model "mistral-medium-3.5:128b"))
    ("machine"    . (:backend ollama-3080   :model "granite4.1:8b-q8_0"))
    ("ouroboros"  . (:backend ollama-3080   :model "nemotron-3-super:120b"))
    ("default"    . (:backend ollama-3080   :model "glm-5.2:cloud")))
  "Alist mapping agent names to backend/model pairs.")
```

#### Delegate tool changes
- In `my-gptel--spawn-delegate`, after setting `gptel-system-prompt`, look up agent name in routing table.
- Set `gptel-backend` and `gptel-model` buffer-locally based on routing entry.
- Fall back to `default` entry if agent not in table.
- Fall back to current global backend if no `default` entry.

### Files
- `/root/.emacs.d/init.d/gptel_setup.el` -- rewrite with both backends
- `/root/.emacs.d/init.d/delegate_tool.el` -- add routing lookup in spawn function

---

## Phase 3: Token Budget Management for Ollama Cloud

### Goal
Simple weekly counter for Ollama Cloud usage. When budget exhausted, cloud-assigned agents automatically fall back to tier 3 (3080 server). Reset weekly. Persist across Emacs restarts.

### Design
- `defcustom my-gptel-cloud-weekly-budget` -- token limit (default: estimate from Ollama Cloud plan)
- `defvar my-gptel-cloud-tokens-used` -- current week's usage
- State stored in `/root/.emacs.d/.cloud_budget` as a plist: `(:week-start "2026-06-23" :tokens-used 0)`
- On each cloud request: increment counter, check against budget, write state file
- If over budget: routing table returns tier 3 backend instead of cloud
- Weekly reset: compare current date to `:week-start`; if >7 days, reset counter
- [ ] Determine actual weekly token budget from Ollama Cloud plan
- [ ] Decide: count by tokens (need to parse response headers) or by requests (simpler, less accurate)

### File
- `/root/.emacs.d/init.d/token_budget.el`
- Load from `init.el`
- Integrate with routing table lookup in delegate tool

---

## Phase 4: Async Parallel Delegation

### Goal
Modify delegate tool to support fire-and-collect pattern. Spawn multiple agents simultaneously across different backends, then collect all results.

### Design

#### New tool: `delegate-async`
- `my-gptel-tool-delegate-async (agent task &optional context timeout)`
- Same as `delegate` but returns a task ID immediately instead of blocking
- Stores delegate-info in a global alist `my-gptel--async-tasks`
- Does NOT kill the buffer after completion -- keeps it for collection

#### New tool: `collect-results`
- `my-gptel-tool-collect-results (task-ids &optional timeout)`
- Takes a list of task IDs (space-separated or JSON array)
- Waits for all to complete (or timeout)
- Returns all responses as a combined string
- Kills buffers after collection

#### Modified `delegate` (existing)
- Keep as-is for backward compatibility (synchronous, single delegate)
- Or: make it a wrapper that calls delegate-async then collect-results with one ID

### Implementation notes
- `accept-process-output` already yields to event loop, so multiple async delegates can run concurrently in theory -- need to verify gptel doesn't serialize requests
- Each delegate buffer has its own `gptel-backend` and `gptel-model` (from Phase 2 routing), so they hit different backends in parallel
- Need to handle: partial completions, buffer death, timeout per-task

### Files
- `/root/.emacs.d/init.d/delegate_tool.el` -- add async variants
- Register both new tools in the same file

---

## Phase 5 (Later): Local Inference Fallback for Sharing

### Goal
Support running the framework with only a local Ollama instance (tier 1). For users without remote servers.

### Design
- Detect at startup: if no remote backends configured, define a local Ollama backend at `localhost:11434`
- Small model (3B-8B) suitable for weak hardware
- All agents route to local backend
- `execute_code_remote` detects no SSH config, degrades to `execute_code_local` with note
- Document minimum hardware requirements for local-only mode

### Deprioritized
- Build for the author's hardware first. Abstract later.

---

## Architecture Notes

### Why not run Ollama on tier 2 (0b.ar)?
- 64GB RAM, 16 cores, no GPU. CPU inference is slow for interesting models.
- Better used as execution sandbox: Docker, compilation, test suites, long-running processes.
- Could run a small model (3B) as fallback if needed, but not worth the complexity now.

### On the "dangerous but fun" remote execution idea
- Agent with root SSH to a VPS can do anything: spin up containers, run services, install packages.
- This is the natural extension of self-modification: the agent already modifies its own runtime (Emacs Lisp), giving it a real execution environment expands its world.
- Risk is manageable: 0b.ar is a test server, not production. SSH key restrictions and dedicated users can be added later.
- For sharing: tool detects configuration and degrades gracefully. Same code, different capability profile.

### On building for yourself first
- The framework should use all available hardware. Limiting potential because someone else's setup is simpler is the wrong optimization.
- Configuration via `defcustom` means the default can be simple (local Ollama only) while the author's config is powerful (four tiers).
- Sharing is a documentation problem, not an architecture problem. Solve it later.

### Model selection rationale
- `coder` on 8B: code generation for Emacs Lisp doesn't need a large model. 8B at q8 on GPU is fast and sufficient.
- `reviewer` on 20B: review needs more capacity to spot subtle issues.
- `researcher` on cloud 500B: synthesis and deep reasoning benefit from frontier models.
- `mccarthy` on cloud (budgeted): architectural decisions need quality. Falls back to 120B on tier 3 when cloud budget exhausted.
- Routing table is an alist -- tune by editing one variable. No restart needed if using `eval-expression`.