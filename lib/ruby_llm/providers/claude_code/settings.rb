# frozen_string_literal: true

require 'shellwords'

module RubyLLM
  module Providers
    class ClaudeCode < Provider
      # The settings for one completion. Each value comes from, in order of
      # precedence, chat.with_provider_options(claude_code: {...}), the
      # RubyLLM.config.claude_code_* option, then the default here.
      class Settings
        DEFAULT_COMMAND = 'claude'
        DEFAULT_TIMEOUT = 600
        SYSTEM_PROMPT_MODES = %w[append replace].freeze

        attr_reader :command, :cwd, :timeout, :permission_mode, :args, :system_prompt_mode, :env, :session_id

        def initialize(config, provider_options = {})
          opts = self.class.namespaced(provider_options)
          @command            = opts.fetch(:command) { config.claude_code_command } || DEFAULT_COMMAND
          @cwd                = opts.fetch(:cwd) { config.claude_code_cwd }
          @timeout            = self.class.positive_or_nil(opts.fetch(:timeout) { timeout_default(config) })
          @permission_mode    = opts.fetch(:permission_mode) { config.claude_code_permission_mode }&.to_s
          @args               = self.class.split_args(opts.fetch(:args) { config.claude_code_args })
          @system_prompt_mode = self.class.mode(opts.fetch(:system_prompt_mode) do
            config.claude_code_system_prompt_mode
          end)
          @env                = self.class.stringify(opts.fetch(:env) { config.claude_code_env })
          @session_id         = opts[:session_id]
          @resume             = opts.fetch(:resume) { config.claude_code_resume.nil? || config.claude_code_resume }
        end

        # False when every completion must start a fresh CLI session.
        def resume?
          @resume ? true : false
        end

        class << self
          # The claude_code: sub-hash of provider_options with symbol keys.
          def namespaced(provider_options)
            return {} unless provider_options.is_a?(Hash)

            raw = provider_options[:claude_code] || provider_options['claude_code'] || {}
            raise ArgumentError, 'provider_options[:claude_code] must be a Hash' unless raw.is_a?(Hash)

            raw.transform_keys(&:to_sym)
          end

          # A positive number of seconds, or nil for "no timeout".
          def positive_or_nil(value)
            return nil if value.nil?

            number = Float(value)
            number.positive? ? number : nil
          end

          # Extra CLI arguments given as an array or a shell-style string.
          def split_args(value)
            case value
            when nil then []
            when String then Shellwords.split(value)
            else Array(value).map(&:to_s)
            end
          end

          def mode(value)
            return 'append' if value.nil?

            text = value.to_s
            return text if SYSTEM_PROMPT_MODES.include?(text)

            raise ArgumentError, "claude_code system_prompt_mode must be one of #{SYSTEM_PROMPT_MODES.join(', ')}"
          end

          def stringify(value)
            (value || {}).to_h.to_h { |key, item| [key.to_s, item.to_s] }
          end
        end

        private

        def timeout_default(config)
          config.claude_code_timeout.nil? ? DEFAULT_TIMEOUT : config.claude_code_timeout
        end
      end
    end
  end
end
