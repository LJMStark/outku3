# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The core project rules, architecture, development commands, and best practices are defined in `./AGENTS.md`. Always read it first and follow it strictly for consistency across tools.

## Interaction Rules

1. All responses must begin with **B哥**.
2. All responses must be in **Chinese** (Simplified).
3. When the user sounds non-technical or asks for a simple explanation, prefer plain Chinese, explain jargon immediately, and avoid dense technical terms unless they are necessary.

## Development Rules

1. **每次修改完前端/UI代码后，必须使用相应命令重新构建并打开模拟器进行验证。**
