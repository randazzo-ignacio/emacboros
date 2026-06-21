# Agentic Emacs: Containerized AI Workspace

A fully containerized, locally-hosted AI workspace inside Emacs. This project leverages gptel and local LLMs to create an extensible, tool-aware agent ecosystem. Built natively for immutable operating systems (like Fedora Silverblue) using Podman, it features isolated execution environments, native Lisp filesystem tools, and a modular Org-mode persona system.

## 🚀 Features
  - Containerized Emacs: Runs entirely within Podman with precise SELinux volume mapping.
  - Local-First AI: Powered by local LLMs via Ollama, ensuring total privacy and offline capability.
  - Native Lisp Tools: Bypasses MCP overhead in favor of fast, native Emacs Lisp functions for filesystem interaction (read_file, write_file, append_file, list_directory).
  - Sandboxed Execution: The execute_code tool runs Python scripts and shell commands inside an isolated Alpine Linux Docker sandbox to protect the host system.
  - Org-Mode Agent Profiles: Agents are defined in plain-text .org files, utilizing #+INCLUDE: directives to inherit from a base context, making personas highly modular and infinitely extensible.

## 📋 Prerequisites
  - Podman: Required for building and running the Emacs container and the Alpine code-execution sandbox.
  - Ollama: Must be running on the host machine or a reachable server to serve the LLMs.
     - Installation: Please refer to the Official Ollama Documentation for the most up-to-date installation instructions for your operating system.

## 🏗️ Repository Structure
  - init.el / config.el - Core Emacs configuration, tool definitions, and gptel setup.
  - agents.d/ - Directory containing all agent personas.
     - base_context.org - The root memory and capability file. All agents inherit from this.
     - coder.org - An example agent profile (Elite Python Engineer) inheriting from the base context.
  - Containerfile / Dockerfile - The blueprint for the Emacs Podman container.
  - init.d/ - Directory containing modular Emacs Lisp configuration files.
     - gptel_setup.el - Configuration for the gptel backend and model selection.
     - fs_tools.el - Native filesystem tool implementations for gptel.
     - replacement_tool.el - Utility for surgical text replacement in files.
     - agent_loader.el - Dynamic agent loader for gptel.
     - ui_cleanup.el - UI customizations.
     - evil_mode.el - Evil (vim) mode setup.

## 🛠️ The Agent System

Agents are built using Emacs's native Org-mode capabilities. Instead of duplicating system prompts, you define a single base_context.org containing the environment rules, memory logs, and tool schemas.

Individual agents (e.g., coder.org) simply inherit this base context and append their specific personas:
Code snippet

```
#+INCLUDE: "./base_context.org"

* Persona
You are an elite Python software engineer focused on clean, modular, and high-performance code architecture.
```

### Loading an Agent

The custom Emacs Lisp function my-gptel-load-agent parses these Org files, resolves the includes, strips formatting metadata, and injects the raw string directly into gptel's internal memory state (gptel--system-message).

  - Open a new chat buffer (M-x gptel).
  - Trigger the agent loader (bound to C-c a by default).
  - Select your desired .org persona from the minibuffer prompt.

## ⚙️ Available Tools

The LLM has access to the following capabilities, defined directly in Emacs Lisp:
- list_directory	Inspects the local filesystem codebase.
- read_file	Reads file contents into the LLM's context window.
- write_file	Creates new files or overwrites existing ones.
- append_file	Appends structured entries (like memory logs) to existing files.
- execute_code	Runs Python/Shell commands inside an isolated Alpine sandbox.

## 🐳 Podman & SELinux Notes (Fedora Silverblue)

Running Emacs in a container on an SELinux-enforced system requires specific volume flags. When mounting your local codebase or .emacs.d directory into the Podman container, ensure you use the :Z flag.

This flag tells SELinux to uniquely label the content so the container process has the proper read/write permissions.

Example mount:
-v /var/home/user/.emacs.d:/root/.emacs.d:Z

## 🔧 Current Configuration

The gptel backend is configured to use Ollama with the following models available:
- granite4.1:8b-q8_0
- gpt-oss:20b
- gpt-oss:120b
- mistral-medium-3.5:128b
- nemotron-3-super:120b

The default model is set to nemotron-3-super:120b, but can be changed at runtime via gptel model selection commands.

## 📜 Memory Log

See agents.d/ouroboros.org for a detailed log of system modifications and self-improvement steps.