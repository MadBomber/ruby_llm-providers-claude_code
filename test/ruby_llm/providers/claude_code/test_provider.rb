# frozen_string_literal: true

require 'test_helper'

class TestClaudeCodeProvider < Minitest::Test
  Provider = RubyLLM::Providers::ClaudeCode

  def teardown
    Provider.runner = nil
  end

  def chat(model: 'sonnet')
    RubyLLM.chat(model: model, provider: :claude_code)
  end

  def test_registration_and_class_facts
    assert_equal Provider, RubyLLM::Provider.resolve(:claude_code)
    assert_equal 'claude_code', Provider.slug
    assert_predicate Provider, :local?
    assert_predicate Provider, :assume_models_exist?
    refute_predicate Provider, :accepts_tools?
    assert_empty Provider.configuration_requirements
    assert_includes RubyLLM::Configuration.options, :claude_code_command
    refute_nil Provider::VERSION
    assert_equal %w[default opus sonnet haiku], Provider.new(RubyLLM.config).list_models.map(&:id)
  end

  def test_single_turn_through_rubyllm_chat
    Provider.runner = FakeRunner.new([ClaudeOutput.result('pong', session_id: 's1')])
    reply = chat.with_instructions('Answer briefly.').ask('ping')
    assert_equal 'pong', reply.content
    call = Provider.runner.calls.first
    expected = ['claude', '-p', '--output-format', 'json', '--model', 'sonnet', '--append-system-prompt',
                'Answer briefly.']
    assert_equal expected, call[:argv]
    assert_equal 'ping', call[:stdin]
  end

  def test_second_turn_resumes_the_session
    Provider.runner = FakeRunner.new([ClaudeOutput.result('one', session_id: 's1')],
                                     [ClaudeOutput.result('two', session_id: 's1')])
    c = chat
    c.ask('first')
    c.ask('second')
    second = Provider.runner.calls.last
    assert_includes second[:argv], '--resume'
    assert_includes second[:argv], 's1'
    assert_equal 'second', second[:stdin]
  end

  def test_rewound_history_replays_without_resume
    Provider.runner = FakeRunner.new([ClaudeOutput.result('one', session_id: 's1')],
                                     [ClaudeOutput.result('two', session_id: 's2')])
    c = chat
    c.ask('first')
    c.messages.pop # drop the assistant reply, as a checkpoint restore would
    c.ask('second')
    second = Provider.runner.calls.last
    refute_includes second[:argv], '--resume'
    assert_includes second[:stdin], '<user>'
  end

  def test_streaming_yields_chunks
    Provider.runner = FakeRunner.new(ClaudeOutput.streamed('po', 'ng'))
    pieces = []
    reply = chat.ask('ping') { |chunk| pieces << chunk.content }
    assert_equal %w[po ng], pieces
    assert_equal 'pong', reply.content
    assert_includes Provider.runner.calls.first[:argv], 'stream-json'
  end

  def test_default_model_sends_no_model_flag
    Provider.runner = FakeRunner.new([ClaudeOutput.result('ok')])
    chat(model: 'default').ask('x')
    refute_includes Provider.runner.calls.first[:argv], '--model'
  end

  def test_settings_reach_the_runner
    Provider.runner = FakeRunner.new([ClaudeOutput.result('ok')])
    chat.with_provider_options(claude_code: { cwd: '/tmp', timeout: 7, env: { 'A' => 'b' }, permission_mode: 'plan' })
        .ask('x')
    call = Provider.runner.calls.first
    assert_equal '/tmp', call[:cwd]
    assert_in_delta 7.0, call[:timeout]
    assert_equal({ 'A' => 'b' }, call[:env])
    assert_includes call[:argv], '--permission-mode'
  end

  def test_tools_are_rejected
    Provider.runner = FakeRunner.new([ClaudeOutput.result('ok')])
    tool = Class.new(RubyLLM::Tool) do
      description 'noop'
      def execute = 'x'
    end
    assert_raises(Provider::UnsupportedFeatureError) { chat.with_tools(tool).ask('x') }
  end

  def test_cli_error_surfaces
    Provider.runner = FakeRunner.new([ClaudeOutput.result('Invalid API key', is_error: true)])
    assert_raises(Provider::Error) { chat.ask('x') }
  end

  def test_model_and_effort_helpers
    assert_equal 'opus', Provider.model_id('opus')
    assert_equal 'sonnet', Provider.model_id(RubyLLM::Model.default('sonnet', 'claude_code'))
    assert_nil Provider.effort_for(nil)
    assert_equal 'high', Provider.effort_for(Struct.new(:effort).new(:high))
    assert_nil Provider.effort_for(Struct.new(:effort).new(:silly))
  end
end
