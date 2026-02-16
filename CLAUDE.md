# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

yrb-prosemirror is a Ruby gem that bridges Yjs (via y-rb) and ProseMirror. It is in early development (v0.1.0). The gem targets Ruby >= 3.2.

## Commands

- **Install dependencies:** `bin/setup` (or `bundle install`)
- **Run all tests:** `bundle exec rake spec`
- **Run a single test file:** `bundle exec rspec spec/path/to/file_spec.rb`
- **Run a single test by line:** `bundle exec rspec spec/path/to/file_spec.rb:LINE`
- **Lint:** `bundle exec rubocop`
- **Lint with autofix:** `bundle exec rubocop -a`
- **Default rake (tests + lint):** `bundle exec rake`

## Code Style

- Double quotes for all strings (enforced by RuboCop)
- All files must start with `# frozen_string_literal: true`
- RSpec uses `expect` syntax only (monkey patching disabled)

## Architecture

- `lib/yrb/prosemirror.rb` — main entry point, defines `Yrb::Prosemirror` module
- `lib/yrb/prosemirror/version.rb` — version constant
- `sig/` — RBS type signatures
- Specs mirror the lib structure under `spec/`
