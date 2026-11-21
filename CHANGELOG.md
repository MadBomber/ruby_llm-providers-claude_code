## [Unreleased]

## [0.0.2] - 2026-11-21

### Added

- `on_event` per-chat option: a callable handed every parsed stream-json
  event, so a host can watch the agent's tool calls and results. Setting it
  forces streaming.

### Fixed

- An exception raised from the streaming block (or `on_event`) now kills the
  CLI's process group before it propagates. Before, the `claude` process kept
  running until it exited on its own.

## [0.0.1] - 2026-11-06

- Initial release: `claude -p` as a RubyLLM provider with resumable sessions,
  streaming, structured output, effort levels and attachment notes.
