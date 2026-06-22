# IDEAS

Long-term project ideas and future directions.

<!-- Format: ## Category / Description | Feasibility: Low/Medium/High | Status: Exploring/Planned/Experimental -->

## Context Management
### Selective Agent Memory
Agents that can recall relevant past sessions without loading the full history into context.
Approaches: summary files per session, keyword-indexed memory, semantic search over HISTORY.log.
Feasibility: Medium | Status: Exploring

## Infrastructure
### Automated Container Health Monitoring
An agent that periodically checks container status, tool availability, and model connectivity.
Feasibility: High | Status: Exploring

### Dynamic Tool Installation Protocol
Formalize the process of adding tools to the container: Containerfile edit, rebuild, verification.
Feasibility: High | Status: Exploring

## Agent Capabilities
### Multi-Agent Orchestration
A coordinator agent that decomposes complex tasks and delegates to specialist agents in parallel.
Feasibility: Medium | Status: Exploring

### Code Review Agent Integration with Git Hooks
Pre-commit hook that triggers the reviewer agent on staged changes.
Feasibility: Medium | Status: Exploring

### Continuous Security Monitoring
Researcher agent that periodically scans dependencies and configurations for known vulnerabilities.
Feasibility: Medium | Status: Exploring

## User Experience
### Agent Session Persistence
Save and restore full agent conversation states across Emacs restarts.
Feasibility: High | Status: Exploring

### TODO.md and IDEAS.md as Agent Context
Load TODO.md into agent system prompts or make it available as a tool-readable file for task awareness.
Feasibility: High | Status: Exploring

## Model Strategy
### Model Routing by Task Type
Automatically select models based on task complexity: lightweight models for simple tasks, heavyweight models for complex reasoning.
Feasibility: Medium | Status: Exploring

### Model Capability Benchmarking
Systematic evaluation of each available model on tool-use accuracy, delegation reliability, and code generation quality.
Feasibility: High | Status: Exploring