require "test_helper"

class TransactionParserTest < ActiveSupport::TestCase
  # Minimal stand-in for a RubyLLM chat chain. All chain methods return self so
  # the service can call with_instructions / with_schema / ask in any order.
  class FakeChat
    attr_reader :captured_prompt, :captured_message

    def initialize(content: nil, raises: nil)
      @content = content
      @raises = raises
    end

    def with_instructions(prompt)
      @captured_prompt = prompt
      self
    end

    def with_schema(_schema) = self

    def ask(message)
      @captured_message = message
      raise @raises if @raises
      Struct.new(:content).new(@content)
    end
  end

  setup do
    @chat_message = chat_messages(:pending_message)
  end

  def stub_ruby_llm(content: nil, raises: nil, &block)
    fake = FakeChat.new(content: content, raises: raises)
    stub_method(RubyLLM, :chat, fake) { block.call(fake) }
  end

  test "AE1: parses relative date expense (kemarin beli bensin 50rb)" do
    @chat_message.update!(content: "kemarin beli bensin 50rb")
    yesterday = (Time.current - 1.day).to_date.to_s

    result = stub_ruby_llm(content: {
      "is_transaction" => true,
      "entries" => [
        { "amount_cents" => 50_000, "direction" => "expense", "category" => "Transport",
          "occurred_on" => yesterday, "description" => "bensin" }
      ],
      "reply_text" => ""
    }) { TransactionParser.new(@chat_message).parse }

    assert result.ok?
    assert result.is_transaction?
    assert_equal 1, result.entries.size
    assert_equal 50_000, result.entries.first[:amount_cents]
    assert_equal "expense", result.entries.first[:direction]
    assert_equal "Transport", result.entries.first[:category]
    assert_equal yesterday, result.entries.first[:occurred_on]
  end

  test "AE2: parses income (gajian 10jt masuk)" do
    @chat_message.update!(content: "gajian 10jt masuk")

    result = stub_ruby_llm(content: {
      "is_transaction" => true,
      "entries" => [
        { "amount_cents" => 10_000_000, "direction" => "income", "category" => "Gaji",
          "occurred_on" => Date.current.to_s, "description" => "gajian" }
      ],
      "reply_text" => ""
    }) { TransactionParser.new(@chat_message).parse }

    assert result.is_transaction?
    assert_equal "income", result.entries.first[:direction]
    assert_equal "Gaji", result.entries.first[:category]
  end

  test "AE3: non-transaction sapaan" do
    @chat_message.update!(content: "halo apa kabar")

    result = stub_ruby_llm(content: {
      "is_transaction" => false,
      "entries" => [],
      "reply_text" => "Bukan transaksi — coba sebut jumlahnya ya."
    }) { TransactionParser.new(@chat_message).parse }

    assert result.ok?
    refute result.is_transaction?
    assert_empty result.entries
    assert_equal "Bukan transaksi — coba sebut jumlahnya ya.", result.reply_text
  end

  test "AE5: Parser Agent timeout returns ok=false" do
    result = stub_ruby_llm(raises: Timeout::Error.new("timed out")) { TransactionParser.new(@chat_message).parse }

    refute result.ok?
    assert_equal "Timeout::Error", result.error
    assert_empty result.entries
  end

  test "AE6: multi-item message splits into entries" do
    @chat_message.update!(content: "beli nasi 25rb sama es teh 5rb")

    result = stub_ruby_llm(content: {
      "is_transaction" => true,
      "entries" => [
        { "amount_cents" => 25_000, "direction" => "expense", "category" => "Makanan & Minuman",
          "occurred_on" => Date.current.to_s, "description" => "nasi" },
        { "amount_cents" => 5_000, "direction" => "expense", "category" => "Makanan & Minuman",
          "occurred_on" => Date.current.to_s, "description" => "es teh" }
      ],
      "reply_text" => ""
    }) { TransactionParser.new(@chat_message).parse }

    assert_equal 2, result.entries.size
    assert_equal [ 25_000, 5_000 ], result.entries.map { |e| e[:amount_cents] }
  end

  test "AE7: arithmetic 'beli 2 nasi @25rb' expands to two identical rows" do
    @chat_message.update!(content: "beli 2 nasi @25rb")

    result = stub_ruby_llm(content: {
      "is_transaction" => true,
      "entries" => [
        { "amount_cents" => 25_000, "direction" => "expense", "category" => "Makanan & Minuman",
          "occurred_on" => Date.current.to_s, "description" => "nasi" },
        { "amount_cents" => 25_000, "direction" => "expense", "category" => "Makanan & Minuman",
          "occurred_on" => Date.current.to_s, "description" => "nasi" }
      ],
      "reply_text" => ""
    }) { TransactionParser.new(@chat_message).parse }

    assert_equal 2, result.entries.size
    assert_equal [ 25_000, 25_000 ], result.entries.map { |e| e[:amount_cents] }
  end

  test "AE8: mixed income + expense in one message" do
    @chat_message.update!(content: "dapet transfer 500rb trus langsung beli baju 200rb")

    result = stub_ruby_llm(content: {
      "is_transaction" => true,
      "entries" => [
        { "amount_cents" => 500_000, "direction" => "income", "category" => "Lainnya (Income)",
          "occurred_on" => Date.current.to_s, "description" => "transfer dari teman" },
        { "amount_cents" => 200_000, "direction" => "expense", "category" => "Belanja",
          "occurred_on" => Date.current.to_s, "description" => "baju" }
      ],
      "reply_text" => ""
    }) { TransactionParser.new(@chat_message).parse }

    directions = result.entries.map { |e| e[:direction] }
    assert_equal [ "income", "expense" ], directions
  end

  test "AE9: amount-less transactional verb returns clarifying reply" do
    @chat_message.update!(content: "abis beli batagor")

    result = stub_ruby_llm(content: {
      "is_transaction" => false,
      "entries" => [],
      "reply_text" => "Berapa harganya?"
    }) { TransactionParser.new(@chat_message).parse }

    refute result.is_transaction?
    assert_equal "Berapa harganya?", result.reply_text
  end

  test "edge case: is_transaction=true with empty entries treated as non-transaction" do
    result = stub_ruby_llm(content: {
      "is_transaction" => true,
      "entries" => [],
      "reply_text" => ""
    }) { TransactionParser.new(@chat_message).parse }

    assert result.ok?
    refute result.is_transaction?
    # Falls back to a default Bahasa reply when reply_text is empty.
    assert_match(/Gak ada transaksi/, result.reply_text)
  end

  test "system prompt includes current Jakarta time so 'kemarin' resolves correctly" do
    fake = nil
    stub_ruby_llm(content: {
      "is_transaction" => false, "entries" => [], "reply_text" => "ok"
    }) do |f|
      fake = f
      TransactionParser.new(@chat_message).parse
    end
    assert_match(/Asia\/Jakarta/, fake.captured_prompt)
    assert_match(/#{Time.current.strftime('%Y-%m-%d')}/, fake.captured_prompt)
    assert_match(/Makanan & Minuman/, fake.captured_prompt)
    assert_match(/Gaji/, fake.captured_prompt)
  end
end
