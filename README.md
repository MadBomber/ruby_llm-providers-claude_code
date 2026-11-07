# ruby_llm-providers-claude_code

A [RubyLLM](https://rubyllm.com) provider that uses the **Claude Code agent**
as the model. Each completion runs `claude -p` in batch mode, writes the
prompt to its stdin and reads the JSON result from stdout.

This is deliberately *not* an isolated stand-in for the Anthropic API. The
agent keeps everything that makes it an agent: its own tools (Read, Edit,
Bash, ...), its settings, hooks and MCP servers, and it works in the current
directory. Multi-turn chats resume the same CLI session, so the agent keeps
its context, tool results and plan between turns.

```ruby
require 'ruby_llm/providers/claude_code'

chat = RubyLLM.chat(model: 'sonnet', provider: :claude_code)
chat.ask('What does the Rakefile in this directory do?')
chat.ask('Add a `lint` task to it') { |chunk| print chunk.content }
```

With [aia](https://github.com/madbomber/aia) the provider is picked from the
model prefix, so any prompt, pipeline or multi-model run can be driven by the
agent:

```bash
aia --model claude_code/opus refactor_prompt
aia --model claude_code/sonnet=implementer,codex/default=reviewer --consensus review
```

## Requirements

- Ruby 3.2 or newer
- RubyLLM 2.1 or newer
- The Claude Code CLI on your PATH (`claude --version`), logged in. Requests
  use whatever login Claude Code has; no API key is read by this gem.

## Installation

```ruby
gem 'ruby_llm-providers-claude_code', require: 'ruby_llm/providers/claude_code'
```

The provider registers itself as `:claude_code` when required. No
configuration is required.

## Models

The part after the slash goes straight to `claude --model`: an alias
(`opus`, `sonnet`, `haiku`) or a full id such as `claude-opus-5-5`. The id
`default` (or an empty id) sends no `--model` flag and lets the CLI choose.
`list_models` returns this static set; any other id is passed through.

## Sessions

RubyLLM hands the provider the whole transcript on every turn. The provider
fingerprints what it has sent before, and when the transcript minus the newest
message matches what the CLI session already saw, it sends only the new
message with `--resume <session id>`. Any other shape, such as a rewound or
edited history, a cleared chat or a changed system prompt, starts a fresh
session with the full conversation replayed as a tagged transcript.

```ruby
chat.with_provider_options(claude_code: { resume: false })      # fresh session every turn
chat.with_provider_options(claude_code: { session_id: 'uuid' }) # continue a known session
provider = chat.instance_variable_get(:@provider)
provider.session.id                                              # the CLI session in use
```

## Configuration

Global options are `RubyLLM.config.claude_code_*`; the same keys can be set
per chat with `with_provider_options(claude_code: { ... })`.

| Option | Default | Meaning |
|---|---|---|
| `command` | `claude` | CLI executable |
| `cwd` | current directory | Directory the agent works in |
| `timeout` | `600` | Seconds before the process group is killed; `nil` or `0` disables |
| `permission_mode` | CLI default | `--permission-mode` (`acceptEdits`, `plan`, `bypassPermissions`, ...) |
| `args` | none | Extra CLI arguments, array or shell string (`--add-dir`, `--max-turns`, `--mcp-config`, ...) |
| `system_prompt_mode` | `append` | `append` adds RubyLLM instructions to Claude Code's prompt; `replace` uses them instead |
| `env` | none | Extra environment variables for the process |
| `resume` | `true` | Reuse the CLI session across turns |
| `session_id` | none | Per-request only: force `--resume` with this id |

```ruby
RubyLLM.configure do |c|
  c.claude_code_permission_mode = 'acceptEdits'
  c.claude_code_timeout = 900
  c.claude_code_args = ['--add-dir', '/path/to/other/repo']
end
```

## What is supported

| Feature | How |
|---|---|
| Text, system prompts, multi-turn | Native; see Sessions |
| Streaming | `--output-format stream-json`; only the top-level agent's text is streamed, not subagent output |
| Structured output (`with_schema`) | `--json-schema`; the result is the JSON string |
| `with_thinking(effort:)` | `--effort` (low, medium, high, xhigh, max) |
| Token counts and cost | From the CLI result, including cache reads and writes and `total_cost_usd` |
| Attachments | Noted in the prompt as `[Attached file 'name': path]`; the agent opens local files itself |
| RubyLLM tools (`with_tools`) | **Not supported**: raises `UnsupportedFeatureError`. The agent uses its own tools and MCP servers. The provider class answers `accepts_tools?` with `false` so hosts such as aia can skip attaching tools |
| temperature, max tokens | Ignored (logged at debug level) |

The streamed text is everything the agent says along the way; the returned
message content is its final result.

## Safety

In batch mode the agent can edit files and run commands in `cwd` under its
usual permission rules. Set `permission_mode` (or pass `--allowedTools` via
`args`) deliberately rather than relying on defaults you have not looked at.

## Development

```bash
bundle install
bundle exec rake test     # offline: the CLI is replaced by a fake runner
bundle exec rubocop
bin/console
```
