class ParseMessageJob < ApplicationJob
  queue_as :default

  # Single-user queue = strict FIFO without extra config. Retries are
  # intentionally disabled: if the Parser Agent fails, R7's error bubble is
  # the user-visible outcome and they can retry by re-sending the message.
  discard_on RubyLLM::Error

  def perform(chat_message)
    result = TransactionParser.new(chat_message).parse

    if result.ok? && result.is_transaction?
      record_transactions(chat_message, result.entries, result.reply_text)
    elsif result.ok?
      record_non_transaction(chat_message, result.reply_text)
    else
      record_failure(chat_message)
    end

    broadcast_reply(chat_message)
  end

  private
    def record_transactions(chat_message, entries, reply_text)
      records = entries.map do |entry|
        Transaction.new(
          chat_message: chat_message,
          amount_cents: entry[:amount_cents],
          direction: entry[:direction],
          category: entry[:category],
          occurred_on: parse_date(entry[:occurred_on]),
          description: entry[:description]
        )
      end

      # Pre-validate everything: if any entry is invalid we reject the whole
      # batch and surface an error bubble (R7). No partial writes.
      if records.all?(&:valid?)
        records.each(&:save!)
        chat_message.update!(parser_status: :logged, reply_text: reply_text.presence)
      else
        Rails.logger.warn("[ParseMessageJob] invalid batch for ##{chat_message.id}: " \
          "#{records.reject(&:valid?).flat_map { |r| r.errors.full_messages }.join('; ')}")
        record_failure(chat_message)
      end
    end

    def record_non_transaction(chat_message, reply_text)
      chat_message.update!(parser_status: :not_transaction, reply_text: reply_text)
    end

    def record_failure(chat_message)
      chat_message.update!(parser_status: :failed, reply_text: "Gagal mencatat, coba lagi.")
    end

    def broadcast_reply(chat_message)
      user = chat_message.user
      partial = case chat_message.parser_status
      when "logged"          then "chat_messages/confirmation"
      when "not_transaction" then "chat_messages/reply"
      when "failed"          then "chat_messages/error"
      end
      return unless partial

      Turbo::StreamsChannel.broadcast_replace_to(
        user,
        target: "thinking_#{chat_message.id}",
        partial: partial,
        locals: { chat_message: chat_message }
      )
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      Time.current.to_date
    end
end
