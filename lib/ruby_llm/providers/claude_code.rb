# frozen_string_literal: true

require 'ruby_llm'
require 'ruby_llm/providers/claude_code/version'
require 'ruby_llm/providers/claude_code/errors'
require 'ruby_llm/providers/claude_code/settings'
require 'ruby_llm/providers/claude_code/command'
require 'ruby_llm/providers/claude_code/transcript'
require 'ruby_llm/providers/claude_code/session'
require 'ruby_llm/providers/claude_code/runner'
require 'ruby_llm/providers/claude_code/response'

module RubyLLM
  module Providers
    # ClaudeCode: the Claude Code agent (`claude -p`) as a RubyLLM provider.
    #
    # Each completion spawns the claude CLI in batch mode, writes the prompt
    # to its stdin and reads its JSON result from stdout. The agent keeps its
    # own tools, settings and MCP servers and works in the current directory
    # (or config.claude_code_cwd), so the "model" can read and edit files and
    # run commands. Multi-turn chats resume the same CLI session (--resume)
    # as long as the RubyLLM transcript still matches what that session has
    # seen; otherwise a fresh session is started from the whole transcript.
    #
    #   require 'ruby_llm/providers/claude_code'
    #   chat = RubyLLM.chat(model: 'sonnet', provider: :claude_code)
    #   chat.ask('Summarise the README in this directory')
    class ClaudeCode < Provider
      DEFAULT_MODEL = 'default'
      MODELS = %w[default opus sonnet haiku].freeze
      CAPABILITIES = %w[streaming structured_output].freeze

      # Satisfies RubyLLM's protocol lookups; every request goes through
      # #complete below, never through a wire protocol.
      protocol :claude_code, RubyLLM::Protocol

      class << self
        # Anything responding to #run like Runner; tests inject fakes here.
        attr_accessor :runner

        def configuration_options
          %i[
            claude_code_command
            claude_code_cwd
            claude_code_timeout
            claude_code_permission_mode
            claude_code_args
            claude_code_system_prompt_mode
            claude_code_env
            claude_code_resume
          ]
        end

        def configuration_requirements
          []
        end

        def local?
          true
        end

        # Any id goes straight to --model, so there is no catalog to check.
        def assume_models_exist?
          true
        end

        # The agent runs its own tools; RubyLLM tools cannot be handed to it.
        # Hosts such as aia check this before attaching tools or MCP servers.
        def accepts_tools?
          false
        end

        def display_name
          'Claude Code'
        end
      end

      attr_reader :session

      def initialize(config)
        super
        @session = Session.new
      end

      # Never contacted; the transport layer only needs a base URL.
      def api_base
        'cli://claude'
      end

      # Messages go to the CLI as text, so there is nothing to upload or
      # convert beforehand.
      def preprocess_messages(messages, **)
        messages
      end

      def discard_missing_uploads(_messages, _error, **)
        []
      end

      # :reek:LongParameterList -- the keyword set is RubyLLM's Provider#complete contract
      def complete(messages, model:, tools: {}, provider_options: {}, schema: nil, thinking: nil,
                   temperature: nil, max_output_tokens: nil, before_request: [], **, &block)
        reject_tools!(tools)
        log_ignored(temperature:, max_output_tokens:)
        settings   = Settings.new(@config, provider_options)
        plan       = session.plan(messages, session_id: settings.session_id, resume: settings.resume?)
        transcript = Transcript.new(plan.messages)
        argv       = build_argv(settings, model, transcript, plan, schema, thinking, block)
        before_request.each { |hook| hook.call({ argv: argv, prompt: transcript.prompt }) }
        response   = Response.new(model: model, schema: schema)
        run        = runner.run(argv, stdin: transcript.prompt, cwd: settings.cwd, timeout: settings.timeout,
                                      env: settings.env) do |line|
          response.ingest(line) { |chunk| block.call(chunk) }
        end
        message = response.message(run)
        session.record(messages, message, id: response.session_id)
        message
      end

      # A static catalog: the CLI's aliases plus "default" for its own choice.
      def list_models
        MODELS.map { |id| static_model(id) }
      end

      private

      def runner
        self.class.runner || Runner.new
      end

      def build_argv(settings, model, transcript, plan, schema, thinking, block)
        Command.new(settings).build(
          model: self.class.model_id(model),
          stream: !block.nil?,
          resume_id: plan.resume_id,
          system_prompt: transcript.system_prompt,
          schema: schema,
          effort: self.class.effort_for(thinking)
        )
      end

      def static_model(id)
        Model.new(
          id: id,
          name: "Claude Code (#{id})",
          provider: slug,
          capabilities: CAPABILITIES,
          modalities: { input: %w[text], output: %w[text] },
          metadata: { source: 'ruby_llm-providers-claude_code' }
        )
      end

      def reject_tools!(tools)
        return if tools.nil? || tools.empty?

        raise UnsupportedFeatureError,
              'RubyLLM tools cannot be handed to the claude CLI; the agent brings its own tools. ' \
              'Remove with_tools or choose another provider.'
      end

      def log_ignored(**options)
        ignored = options.compact.keys
        return if ignored.empty?

        RubyLLM.logger.debug { "claude_code: ignoring #{ignored.join(', ')} (not supported by claude -p)" }
      end

      class << self
        def model_id(model)
          model.respond_to?(:id) ? model.id : model.to_s
        end

        def effort_for(thinking)
          return nil unless thinking.respond_to?(:effort) && thinking.effort

          value = thinking.effort.to_s
          Command::EFFORTS.include?(value) ? value : nil
        end
      end
    end
  end
end

RubyLLM::Provider.register :claude_code, RubyLLM::Providers::ClaudeCode unless RubyLLM::Provider.resolve(:claude_code)
