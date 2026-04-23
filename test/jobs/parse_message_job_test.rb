require "test_helper"

class ParseMessageJobTest < ActiveJob::TestCase
  setup do
    @user = users(:owner)
    @message = @user.chat_messages.create!(
      role: :outgoing,
      content: "kemarin beli bensin 50rb",
      parser_status: :pending
    )
  end

  test "logs transactions and flips status to :logged on success" do
    result = TransactionParser::Result.new(
      ok: true,
      is_transaction: true,
      entries: [
        { amount_cents: 50_000, direction: "expense", category: "Transport",
          occurred_on: (Date.current - 1).to_s, description: "bensin" }
      ],
      reply_text: nil,
      error: nil
    )

    assert_difference -> { @message.transactions.count }, 1 do
      with_stubbed_parser(result) { ParseMessageJob.perform_now(@message) }
    end

    @message.reload
    assert_equal "logged", @message.parser_status
    tx = @message.transactions.first
    assert_equal 50_000, tx.amount_cents
    assert_equal "Transport", tx.category
    assert_equal Date.current - 1, tx.occurred_on
  end

  test "creates multiple rows under one DB transaction for multi-item" do
    result = TransactionParser::Result.new(
      ok: true,
      is_transaction: true,
      entries: [
        { amount_cents: 25_000, direction: "expense", category: "Makanan & Minuman",
          occurred_on: Date.current.to_s, description: "nasi" },
        { amount_cents: 5_000, direction: "expense", category: "Makanan & Minuman",
          occurred_on: Date.current.to_s, description: "es teh" }
      ],
      reply_text: nil,
      error: nil
    )

    assert_difference -> { @message.transactions.count }, 2 do
      with_stubbed_parser(result) { ParseMessageJob.perform_now(@message) }
    end
    assert_equal "logged", @message.reload.parser_status
  end

  test "marks non-transaction and stores reply_text" do
    result = TransactionParser::Result.new(
      ok: true,
      is_transaction: false,
      entries: [],
      reply_text: "Berapa harganya?",
      error: nil
    )

    assert_no_difference -> { Transaction.count } do
      with_stubbed_parser(result) { ParseMessageJob.perform_now(@message) }
    end

    @message.reload
    assert_equal "not_transaction", @message.parser_status
    assert_equal "Berapa harganya?", @message.reply_text
  end

  test "marks failed on parser error" do
    result = TransactionParser::Result.new(
      ok: false, is_transaction: false, entries: [], reply_text: nil, error: "Timeout::Error"
    )

    assert_no_difference -> { Transaction.count } do
      with_stubbed_parser(result) { ParseMessageJob.perform_now(@message) }
    end

    @message.reload
    assert_equal "failed", @message.parser_status
    assert_equal "Gagal mencatat, coba lagi.", @message.reply_text
  end

  test "rolls back whole batch when one entry is invalid" do
    result = TransactionParser::Result.new(
      ok: true,
      is_transaction: true,
      entries: [
        { amount_cents: 25_000, direction: "expense", category: "Makanan & Minuman",
          occurred_on: Date.current.to_s, description: "nasi" },
        # Invalid: category doesn't belong to expense direction.
        { amount_cents: 5_000, direction: "expense", category: "Gaji",
          occurred_on: Date.current.to_s, description: "bogus" }
      ],
      reply_text: nil,
      error: nil
    )

    assert_no_difference -> { Transaction.count } do
      with_stubbed_parser(result) { ParseMessageJob.perform_now(@message) }
    end

    assert_equal "failed", @message.reload.parser_status
  end

  private
    def with_stubbed_parser(result)
      fake_parser = Class.new do
        define_method(:parse) { result }
      end.new
      stub_method(TransactionParser, :new, fake_parser) { yield }
    end
end
