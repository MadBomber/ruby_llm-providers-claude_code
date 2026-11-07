# frozen_string_literal: true

require 'test_helper'

class TestClaudeCodeCommand < Minitest::Test
  Command = RubyLLM::Providers::ClaudeCode::Command
  Settings = RubyLLM::Providers::ClaudeCode::Settings

  def command(provider_options = {})
    Command.new(Settings.new(RubyLLM::Configuration.new, provider_options))
  end

  def test_plain_json_request
    assert_equal %w[claude -p --output-format json], command.build
  end

  def test_fresh_session_with_everything
    argv = command(claude_code: { permission_mode: 'plan', args: ['--max-turns', '2'] }).build(
      model: 'opus', stream: true, system_prompt: 'Be terse.', schema: { schema: { type: 'object', strict: true } },
      effort: 'high'
    )
    expected = ['claude', '-p', '--output-format', 'stream-json', '--verbose', '--include-partial-messages',
                '--model', 'opus', '--append-system-prompt', 'Be terse.', '--permission-mode', 'plan',
                '--json-schema', '{"type":"object"}', '--effort', 'high', '--max-turns', '2']
    assert_equal expected, argv
  end

  def test_resume_sends_no_system_prompt
    argv = command.build(model: 'default', resume_id: 'sess-9', system_prompt: 'Be terse.')
    assert_equal %w[claude -p --output-format json --resume sess-9], argv
  end

  def test_replace_mode_uses_system_prompt_flag
    argv = command(claude_code: { system_prompt_mode: :replace }).build(system_prompt: 'X')
    assert_includes argv, '--system-prompt'
    refute_includes argv, '--append-system-prompt'
  end

  def test_named_and_schema_helpers
    refute Command.named?(nil)
    refute Command.named?('')
    refute Command.named?('default')
    assert Command.named?('sonnet')
    assert_equal({ 'a' => { 'b' => 1 } },
                 Command.schema_definition({ 'schema' => { 'a' => { 'b' => 1, 'strict' => false } } }))
    assert_equal({ type: 'x' }, Command.schema_definition({ type: 'x' }))
  end
end
