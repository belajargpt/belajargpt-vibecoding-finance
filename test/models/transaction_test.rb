require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:owner)
    @chat_message = chat_messages(:pending_message)
  end

  test "creates a valid expense transaction with today as default date" do
    tx = Transaction.create!(
      chat_message: @chat_message,
      amount_cents: 5000,
      direction: :expense,
      category: "Makanan & Minuman"
    )
    assert_equal Date.current, tx.occurred_on
    assert_equal "expense", tx.direction
  end

  test "creates a valid income transaction" do
    tx = Transaction.create!(
      chat_message: @chat_message,
      amount_cents: 10_000_000,
      direction: :income,
      category: "Gaji"
    )
    assert tx.income?
  end

  test "rejects expense with income category" do
    tx = Transaction.new(
      chat_message: @chat_message,
      amount_cents: 5000,
      direction: :expense,
      category: "Gaji"
    )
    assert_not tx.valid?
    assert_match(/when direction is expense/, tx.errors[:category].first)
  end

  test "rejects amount_cents of zero" do
    tx = Transaction.new(
      chat_message: @chat_message,
      amount_cents: 0,
      direction: :expense,
      category: "Makanan & Minuman"
    )
    assert_not tx.valid?
    assert_includes tx.errors[:amount_cents], "must be greater than 0"
  end

  test "rejects unknown category string" do
    tx = Transaction.new(
      chat_message: @chat_message,
      amount_cents: 5000,
      direction: :expense,
      category: "NotARealCategory"
    )
    assert_not tx.valid?
  end

  test "signed_amount_cents is negative for expense, positive for income" do
    expense = transactions(:batagor)
    assert_equal(-5000, expense.signed_amount_cents)

    income = Transaction.create!(
      chat_message: @chat_message,
      amount_cents: 10_000_000,
      direction: :income,
      category: "Gaji"
    )
    assert_equal 10_000_000, income.signed_amount_cents
  end

  test "CATEGORIES constant exposes both directions" do
    assert_includes Transaction::CATEGORIES["expense"], "Makanan & Minuman"
    assert_includes Transaction::CATEGORIES["income"], "Gaji"
    assert_not_includes Transaction::CATEGORIES["expense"], "Gaji"
  end
end
