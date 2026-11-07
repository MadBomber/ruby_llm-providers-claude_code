# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'ruby_llm/providers/claude_code'
require 'minitest/autorun'
require 'json'

# Stands in for Runner: replays canned stdout lines and records each call.
class FakeRunner
  Status = Struct.new(:exitstatus) do
    def success?
      exitstatus.zero?
    end
  end

  attr_reader :calls

  def initialize(*outputs, exitstatus: 0, stderr: '')
    @outputs = outputs
    @exitstatus = exitstatus
    @stderr = stderr
    @calls = []
  end

  def run(argv, stdin: '', cwd: nil, timeout: nil, env: {})
    @calls << { argv: argv, stdin: stdin, cwd: cwd, timeout: timeout, env: env }
    lines = @outputs.shift || []
    lines.each { |line| yield line if block_given? }
    RubyLLM::Providers::ClaudeCode::Runner::Result.new(stdout: lines.join, stderr: @stderr,
                                                       status: Status.new(@exitstatus))
  end
end

# JSON lines shaped like `claude -p` output.
module ClaudeOutput
  module_function

  def result(text, session_id: 'sess-1', cost: 0.0042, is_error: false, extra: {})
    JSON.generate({
      'type' => 'result', 'subtype' => is_error ? 'error_during_execution' : 'success',
      'is_error' => is_error, 'result' => text, 'session_id' => session_id,
      'stop_reason' => 'end_turn', 'total_cost_usd' => cost,
      'usage' => { 'input_tokens' => 12, 'output_tokens' => 7, 'cache_read_input_tokens' => 100,
                   'cache_creation_input_tokens' => 50, 'output_tokens_details' => { 'thinking_tokens' => 3 } }
    }.merge(extra)) + "\n"
  end

  def stream_event(event, parent: nil)
    JSON.generate({ 'type' => 'stream_event', 'event' => event, 'parent_tool_use_id' => parent,
                    'session_id' => 'sess-1' }) + "\n"
  end

  def text_block_start(index = 0)
    stream_event({ 'type' => 'content_block_start', 'index' => index, 'content_block' => { 'type' => 'text' } })
  end

  def text_delta(text, index: 0, parent: nil)
    stream_event({ 'type' => 'content_block_delta', 'index' => index,
                   'delta' => { 'type' => 'text_delta', 'text' => text } }, parent: parent)
  end

  def streamed(*pieces, session_id: 'sess-1')
    [text_block_start] + pieces.map { |piece| text_delta(piece) } + [result(pieces.join, session_id: session_id)]
  end
end

def user_message(text, **)
  RubyLLM::Message.new(role: :user, content: text, **)
end

def assistant_message(text)
  RubyLLM::Message.new(role: :assistant, content: text)
end

def system_message(text)
  RubyLLM::Message.new(role: :system, content: text)
end
