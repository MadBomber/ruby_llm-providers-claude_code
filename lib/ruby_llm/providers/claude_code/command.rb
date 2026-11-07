# frozen_string_literal: true

require 'json'

module RubyLLM
  module Providers
    class ClaudeCode < Provider
      # Builds the argv for one `claude -p` invocation.
      class Command
        EFFORTS = %w[low medium high xhigh max].freeze

        def initialize(settings)
          @settings = settings
        end

        # @param model [String, nil] model id or alias; "default" means the CLI's own choice
        # @param stream [Boolean] ask for stream-json output with partial messages
        # @param resume_id [String, nil] CLI session id to continue
        # @param system_prompt [String, nil] sent only when starting a session
        # @param schema [Hash, nil] RubyLLM schema payload for structured output
        # @param effort [String, nil] one of EFFORTS
        # @return [Array<String>]
        def build(model: nil, stream: false, resume_id: nil, system_prompt: nil, schema: nil, effort: nil)
          argv = [@settings.command, '-p', '--output-format', stream ? 'stream-json' : 'json']
          argv.push('--verbose', '--include-partial-messages') if stream
          argv.push('--model', model.to_s) if self.class.named?(model)
          argv.push('--resume', resume_id) if resume_id
          argv.concat(system_prompt_args(system_prompt)) unless resume_id
          argv.push('--permission-mode', @settings.permission_mode) if @settings.permission_mode
          argv.push('--json-schema', JSON.generate(self.class.schema_definition(schema))) if schema
          argv.push('--effort', effort) if effort
          argv.concat(@settings.args)
        end

        class << self
          def named?(model)
            !(model.nil? || model.to_s.empty? || model.to_s == DEFAULT_MODEL)
          end

          # The bare JSON Schema from RubyLLM's payload, without the "strict"
          # keys the CLI rejects.
          def schema_definition(schema)
            clean(schema[:schema] || schema['schema'] || schema)
          end

          def clean(schema)
            case schema
            when Hash then schema.reject { |key, _| key.to_s == 'strict' }.transform_values { |value| clean(value) }
            when Array then schema.map { |value| clean(value) }
            else schema
            end
          end
        end

        private

        def system_prompt_args(text)
          return [] if text.nil? || text.strip.empty?

          flag = @settings.system_prompt_mode == 'replace' ? '--system-prompt' : '--append-system-prompt'
          [flag, text]
        end
      end
    end
  end
end
