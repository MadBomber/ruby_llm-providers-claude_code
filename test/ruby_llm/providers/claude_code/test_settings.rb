# frozen_string_literal: true

require 'test_helper'

class TestClaudeCodeSettings < Minitest::Test
  Settings = RubyLLM::Providers::ClaudeCode::Settings

  def config(**values)
    RubyLLM::Configuration.new.tap do |c|
      values.each { |key, value| c.public_send(:"claude_code_#{key}=", value) }
    end
  end

  def test_defaults
    settings = Settings.new(config)
    assert_equal 'claude', settings.command
    assert_nil settings.cwd
    assert_in_delta 600.0, settings.timeout
    assert_nil settings.permission_mode
    assert_empty settings.args
    assert_equal 'append', settings.system_prompt_mode
    assert_empty settings.env
    assert_nil settings.session_id
    assert_predicate settings, :resume?
  end

  def test_config_values
    settings = Settings.new(config(command: '/opt/claude', cwd: '/tmp', timeout: 30, permission_mode: :plan,
                                   args: '--max-turns 3', system_prompt_mode: 'replace', env: { FOO: 1 },
                                   resume: false))
    assert_equal '/opt/claude', settings.command
    assert_equal '/tmp', settings.cwd
    assert_in_delta 30.0, settings.timeout
    assert_equal 'plan', settings.permission_mode
    assert_equal ['--max-turns', '3'], settings.args
    assert_equal 'replace', settings.system_prompt_mode
    assert_equal({ 'FOO' => '1' }, settings.env)
    refute_predicate settings, :resume?
  end

  def test_provider_options_win
    options = { claude_code: { 'command' => 'c2', timeout: nil, args: %w[--add-dir /x], session_id: 'abc' } }
    settings = Settings.new(config(command: 'c1', timeout: 5), options)
    assert_equal 'c2', settings.command
    assert_nil settings.timeout
    assert_equal ['--add-dir', '/x'], settings.args
    assert_equal 'abc', settings.session_id
  end

  def test_zero_timeout_means_none
    assert_nil Settings.positive_or_nil(0)
    assert_in_delta 1.5, Settings.positive_or_nil('1.5')
  end

  def test_bad_mode_and_namespace
    assert_raises(ArgumentError) { Settings.mode('other') }
    assert_raises(ArgumentError) { Settings.namespaced({ claude_code: 'nope' }) }
    assert_empty Settings.namespaced(nil)
    assert_empty Settings.namespaced({ other: { a: 1 } })
  end

  def test_on_event_must_be_callable
    hook = ->(_event) {}
    assert_same hook, Settings.new(RubyLLM.config, { claude_code: { on_event: hook } }).on_event
    assert_nil Settings.new(RubyLLM.config, {}).on_event
    assert_raises(ArgumentError) { Settings.new(RubyLLM.config, { claude_code: { on_event: 'nope' } }) }
  end
end
