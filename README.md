# ruby_llm-providers-claude_code

A [RubyLLM](https://rubyllm.com) provider that uses the **Claude Code CLI Agent Harness**
as a provider of models. Each completion runs the CLI tool `claude -p` in batch mode, writes the
prompt to its stdin and reads the JSON result from stdout.

This is deliberately *not* an isolated stand-in for the Anthropic API. The
agent keeps everything that makes it an agent: its own tools (Read, Edit,
Bash, ...), its settings, hooks and MCP servers, and it works in the current
directory. Multi-turn chats resume the same CLI session, so the agent keeps
its context, tool results and plan between turns.

## Requirements

- Ruby 3.2 or newer
- RubyLLM 2.1 or newer
- The Claude Code CLI on your PATH (`claude --version`), logged in. Requests
  use whatever login Claude Code has; no API key is read by this gem.

## Installation

```ruby
gem 'ruby_llm-providers-claude_code', require: 'ruby_llm/providers/claude_code'
```

The provider registers itself as `:claude_code` when required and works with
no configuration at all:

```ruby
require 'ruby_llm/providers/claude_code'

chat = RubyLLM.chat(model: 'sonnet', provider: :claude_code)
puts chat.ask('Read README.md and tell me what this gem does.').content
```

## Examples

The [examples](examples/) directory holds three small demo applications. Each
prints the prompt it sends and the reply it receives, and all of them point the
agent at this gem's own root directory and only ask it to read files.

| Demo | Shows |
|---|---|
| [`01_basic.rb`](examples/01_basic.rb) | One question, one answer, with the token counts for the turn |
| [`02_session.rb`](examples/02_session.rb) | A first question that starts a CLI session, then follow-ups that resume it; the session id is printed after each turn |
| [`03_chat_with_streaming.rb`](examples/03_chat_with_streaming.rb) | A reply streamed chunk by chunk, then an interactive chat loop on the same session |

Shared setup lives in [`common.rb`](examples/common.rb). Run a demo from the
gem root with Bundler, or directly from any directory:

```bash
bundle exec ruby examples/01_basic.rb
examples/02_session.rb
CLAUDE_CODE_MODEL=opus examples/03_chat_with_streaming.rb
```

## Configuration

Every option can be set in two places. `RubyLLM.configure` sets the global
default for every chat that uses this provider:

```ruby
RubyLLM.configure do |config|
  config.claude_code_command            = 'claude'
  config.claude_code_cwd                = '/path/to/project'
  config.claude_code_timeout            = 600
  config.claude_code_permission_mode    = 'acceptEdits'
  config.claude_code_args               = ['--add-dir', '/path/to/other/repo']
  config.claude_code_system_prompt_mode = 'append'
  config.claude_code_env                = { 'CLAUDE_CODE_MAX_OUTPUT_TOKENS' => '32000' }
  config.claude_code_resume             = true
end
```

`with_provider_options` sets the same keys, without the `claude_code_` prefix,
for one chat. A per-chat value wins over the global one, and the global value
wins over the built-in default:

```ruby
chat = RubyLLM.chat(model: 'sonnet', provider: :claude_code)
          .with_provider_options(claude_code: { cwd: '/path/to/project', permission_mode: 'plan' })
```

### Options

| Option | Default | Meaning |
|---|---|---|
| `command` | `claude` | CLI executable; a bare name is looked up on PATH, or give a full path |
| `cwd` | current directory | Directory the agent works in; relative paths in prompts, `--add-dir` and file edits all resolve here |
| `timeout` | `600` | Seconds before the whole process group is killed; `nil` or `0` disables the timeout |
| `permission_mode` | CLI default | Passed as `--permission-mode`: `default`, `acceptEdits`, `plan`, `bypassPermissions`, ... |
| `args` | none | Extra CLI arguments appended to every invocation, as an array or a shell-style string |
| `system_prompt_mode` | `append` | How `with_instructions` reaches the CLI: `append` adds to Claude Code's own system prompt, `replace` uses the instructions instead of it |
| `env` | none | Extra environment variables for the CLI process, as a hash; keys and values are stringified |
| `resume` | `true` | Reuse the CLI session across turns; `false` starts a fresh session for every completion |
| `session_id` | none | Per-chat only: continue this CLI session regardless of the transcript (see Sessions) |
| `on_event` | none | Per-chat only: a callable handed every parsed stream-json event (see Watching the agent) |

### Working directory

The agent reads and edits files relative to `cwd`, so set it to the project
you want worked on rather than relying on wherever your Ruby process happens
to run. To let the agent reach a second tree without changing `cwd`, pass
`--add-dir` through `args`.

### Permissions

In batch mode the agent applies its usual permission rules, and an action it
would normally ask about is simply not taken. `permission_mode` chooses the
policy: `plan` lets the agent read and think but change nothing,
`acceptEdits` lets it edit files without asking, and `bypassPermissions`
turns the checks off entirely. Finer control goes through `args`, for example
`--allowedTools Read,Grep` or `--disallowedTools Bash`.

### Extra CLI arguments

`args` takes either form and hands the result straight to the CLI after the
flags this gem sets itself:

```ruby
config.claude_code_args = ['--add-dir', '/other/repo', '--max-turns', '8']
config.claude_code_args = '--add-dir /other/repo --max-turns 8'   # split with shell rules
```

Common uses are `--add-dir`, `--max-turns`, `--mcp-config` and
`--allowedTools`. Do not pass `-p`, `--output-format`, `--model`, `--resume`
or `--permission-mode` here, since the gem sets those from the other options.

### System prompts

RubyLLM instructions (`chat.with_instructions`) are sent only when a session
starts. With `system_prompt_mode` at `append` they go through
`--append-system-prompt`, so the agent keeps its own system prompt and adds
yours. With `replace` they go through `--system-prompt` and stand in for it.

### Timeout

`timeout` covers the whole completion, including every tool call the agent
makes along the way. When it passes, the process group gets TERM, then KILL
after a two-second grace period, and the completion raises
`RubyLLM::Providers::ClaudeCode::TimeoutError`. Agentic work on a large
repository can legitimately take minutes, so raise it, or disable it with
`nil`, for long tasks.

### Watching the agent

The agent's own tool calls never reach RubyLLM's `on_tool_call` and
`on_tool_result` callbacks. To see them, pass `on_event`, a callable that
receives every parsed stream-json event as a Hash. `assistant` events carry
`tool_use` content blocks and `user` events carry `tool_result` blocks.
Events from subagents have a `parent_tool_use_id`.

```ruby
watcher = lambda do |event|
  next unless event['type'] == 'assistant'

  event.dig('message', 'content').each do |block|
    log_tool(block['name'], block['input']) if block['type'] == 'tool_use'
  end
end
chat.with_provider_options(claude_code: { on_event: watcher })
```

Setting `on_event` switches the CLI to stream-json even when `ask` has no
block. If the callable raises, or a streaming block passed to `ask` raises,
the CLI's process group is killed (TERM, then KILL after the grace period)
and the error propagates. A host can use this to stop a run mid-way.

## Models

The model id goes straight to `claude --model`: an alias (`opus`, `sonnet`,
`haiku`) or a full id such as `claude-opus-5-5`. The id `default` (or an empty
id) sends no `--model` flag and lets the CLI choose. `list_models` returns
this static set; any other id is passed through.

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
chat.provider.session.id                                        # the CLI session in use
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
| RubyLLM tools (`with_tools`) | **Not supported**: raises `UnsupportedFeatureError`. The agent uses its own tools and MCP servers. The provider class answers `accepts_tools?` with `false` so a host application can skip attaching tools |
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
asgard test_verbose       # offline: the CLI is replaced by a fake runner
asgard quality            # tests, rubocop, flog, flay, reek, ...
bin/console
```
