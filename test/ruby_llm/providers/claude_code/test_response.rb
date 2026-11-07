# frozen_string_literal: true

require 'test_helper'

class TestClaudeCodeResponse < Minitest::Test
  Response = RubyLLM::Providers::ClaudeCode::Response

  def response(schema: nil)
    Response.new(model: 'sonnet', schema: schema)
  end

  def test_result_becomes_message
    r = response
    r.ingest(ClaudeOutput.result('pong', session_id: 's1', cost: 0.5))
    message = r.message
    assert_equal 'pong', message.content
    assert_equal :assistant, message.role
    assert_equal 's1', r.session_id
    assert_equal 12, message.tokens.input
    assert_equal 7, message.tokens.output
    assert_equal 100, message.tokens.cache_read
    assert_equal 50, message.tokens.cache_write
    assert_equal 3, message.tokens.thinking
    assert_in_delta 0.5, message.tokens.reported_cost
    assert_predicate message, :stopped?
    assert_equal 'result', message.raw['type']
  end

  def test_streaming_yields_text_deltas_only
    r = response
    chunks = []
    lines = [ClaudeOutput.text_block_start,
             ClaudeOutput.text_delta('po'),
             ClaudeOutput.text_delta('ng'),
             ClaudeOutput.text_delta('nested', parent: 'toolu_1'),
             ClaudeOutput.stream_event({ 'type' => 'content_block_start', 'index' => 1,
                                         'content_block' => { 'type' => 'tool_use' } }),
             ClaudeOutput.stream_event({ 'type' => 'content_block_delta', 'index' => 1,
                                         'delta' => { 'type' => 'input_json_delta', 'partial_json' => '{' } }),
             JSON.generate({ 'type' => 'assistant', 'message' => { 'model' => 'claude-haiku-5-5' } }) + "\n",
             "not json\n", "\n",
             ClaudeOutput.result('pong')]
    lines.each { |line| r.ingest(line) { |chunk| chunks << chunk } }
    assert_equal %w[po ng], chunks.map(&:content)
    assert(chunks.all?(RubyLLM::Chunk))
    assert_equal 'claude-haiku-5-5', r.model_id
    assert_equal 'pong', r.message.content
  end

  def test_structured_output
    r = response(schema: { schema: {} })
    r.ingest(ClaudeOutput.result('ignored', extra: { 'structured_output' => { 'answer' => 42 } }))
    assert_equal '{"answer":42}', r.message.content
  end

  def test_error_result_raises
    r = response
    r.ingest(ClaudeOutput.result('Not logged in', is_error: true))
    error = assert_raises(RubyLLM::Providers::ClaudeCode::Error) { r.message }
    assert_includes error.message, 'Not logged in'
  end

  def test_missing_result_raises_with_diagnostics
    run = RubyLLM::Providers::ClaudeCode::Runner::Result.new(stdout: '', stderr: 'boom', status: FakeRunner::Status.new(2))
    error = assert_raises(RubyLLM::Providers::ClaudeCode::Error) { response.message(run) }
    assert_includes error.message, '(2)'
    assert_includes error.message, 'boom'
  end

  def test_max_tokens_finish_reason
    r = response
    r.ingest(ClaudeOutput.result('cut', extra: { 'stop_reason' => 'max_tokens' }))
    assert_predicate r.message, :max_tokens?
  end
end
