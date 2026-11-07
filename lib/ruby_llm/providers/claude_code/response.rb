# frozen_string_literal: true

require 'json'

module RubyLLM
  module Providers
    class ClaudeCode < Provider
      # Reads the CLI's JSON output line by line. While streaming, text deltas
      # from the top-level agent become Chunks; the final "result" event
      # becomes the Message.
      class Response
        STOP_REASONS = { 'end_turn' => :stop, 'stop_sequence' => :stop, 'max_tokens' => :max_tokens }.freeze

        attr_reader :session_id, :result, :model_id

        def initialize(model:, schema: nil)
          @model  = model
          @schema = schema
          @blocks = {}
        end

        # @param line [String] one line of stdout
        # @yield [RubyLLM::Chunk] a streamed piece of assistant text
        # @return [Hash, nil] the parsed event, or nil for non-JSON lines
        def ingest(line)
          event = self.class.parse(line)
          return nil unless event

          case event['type']
          when 'stream_event'
            text = text_delta(event)
            yield chunk(text) if text && block_given?
          when 'assistant' then @model_id ||= event.dig('message', 'model')
          when 'result'
            @result = event
            @session_id = event['session_id']
          when 'system' then @session_id ||= event['session_id']
          end
          event
        end

        # @param run [Runner::Result, nil] used for diagnostics when no result arrived
        # @return [RubyLLM::Message]
        def message(run = nil)
          raise_without_result!(run) unless @result
          raise Error, "claude -p failed: #{error_detail}" if @result['is_error']

          usage = @result['usage'] || {}
          Message.new(
            role: :assistant,
            content: content,
            model: @model,
            input_tokens: usage['input_tokens'],
            output_tokens: usage['output_tokens'],
            cache_read_tokens: usage['cache_read_input_tokens'],
            cache_write_tokens: usage['cache_creation_input_tokens'],
            thinking_tokens: usage.dig('output_tokens_details', 'thinking_tokens'),
            reported_cost: @result['total_cost_usd'],
            finish_reason: STOP_REASONS.fetch(@result['stop_reason'], :stop),
            raw: @result
          )
        end

        def self.parse(line)
          text = line.to_s.strip
          return nil unless text.start_with?('{')

          JSON.parse(text)
        rescue JSON::ParserError
          RubyLLM.logger.debug { "claude_code: non-JSON output #{text.inspect}" }
          nil
        end

        private

        def content
          structured = @result['structured_output']
          return JSON.generate(structured) if @schema && !structured.nil?

          @result['result'].to_s
        end

        def error_detail
          detail = @result['result'].to_s
          detail = Array(@result['errors']).join('; ') if detail.empty?
          detail = @result['subtype'].to_s if detail.empty?
          detail
        end

        def raise_without_result!(run)
          status = run&.status&.exitstatus
          stderr = run&.stderr.to_s.strip
          raise Error,
                "claude -p exited#{" (#{status})" if status} without a result#{": #{stderr}" unless stderr.empty?}"
        end

        # Text from the top-level agent only: subagent output carries a
        # parent_tool_use_id and is not part of the reply.
        def text_delta(event)
          return nil unless event['parent_tool_use_id'].nil?

          data  = event['event'] || {}
          index = data['index']
          case data['type']
          when 'content_block_start'
            @blocks[index] = data.dig('content_block', 'type')
            nil
          when 'content_block_delta'
            delta = data['delta'] || {}
            delta['text'] if delta['type'] == 'text_delta' && (@blocks[index].nil? || @blocks[index] == 'text')
          end
        end

        def chunk(text)
          Chunk.new(role: :assistant, content: text, model: @model)
        end
      end
    end
  end
end
