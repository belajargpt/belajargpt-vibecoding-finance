require "test_helper"

# Exercises the full round-trip that a real user experiences, at the HTML level.
# System tests with Capybara would add browser-level coverage; these integration
# tests focus on what the server renders and what persists, which is where the
# load-bearing behavior lives for this app.
class ChatFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:owner)
    sign_in_as(@user)
  end

  test "Chat index renders header nav and empty-state when ledger is empty" do
    @user.chat_messages.destroy_all
    get root_path
    assert_response :success
    assert_select "a[href=?]", root_path, text: /Chat/
    assert_select "a[href=?]", transactions_path, text: /Ledger/
    assert_select "#messages", text: /Kirim pesan pertamamu/
  end

  test "posting a message enqueues the job and renders the outgoing bubble" do
    assert_enqueued_with(job: ParseMessageJob) do
      post chat_messages_path,
        params: { chat_message: { content: "kemarin beli bensin 50rb" } },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_match /turbo-stream action="append"/, response.body
    assert_match /kemarin beli bensin 50rb/, response.body
    assert_match /thinking_/, response.body
  end

  test "Ledger renders a transaction row with Indonesian rupiah formatting" do
    get transactions_path
    assert_response :success
    # Fixture batagor = 5000, expense.
    assert_select "article.transaction-expense, article" do |nodes|
      texts = nodes.map(&:text).join(" ")
      assert_includes texts, "batagor"
      assert_includes texts, "Rp 5.000"
      assert_match /Makanan & Minuman/, texts
    end
  end

  test "editing a transaction's category persists the change" do
    tx = transactions(:batagor)
    patch transaction_path(tx), params: { transaction: { category: "Belanja" } }
    assert_redirected_to transactions_path
    assert_equal "Belanja", tx.reload.category
  end

  test "deleting a transaction removes the row" do
    tx = transactions(:batagor)
    delete transaction_path(tx)
    assert_redirected_to transactions_path
    assert_nil Transaction.find_by(id: tx.id)
  end

  test "Transaction::CATEGORIES appears in the form so the Stimulus controller can rebuild options" do
    tx = transactions(:batagor)
    get edit_transaction_path(tx)
    assert_response :success
    assert_match(/Makanan (&|&amp;) Minuman/, response.body)
    assert_match(/Gaji/, response.body)
    assert_match(/data-controller="category-filter"/, response.body)
  end

  test "inline edit form does not expose other users' transactions" do
    # R12: single user. Nevertheless, the controller scopes via Current.user —
    # simulate an attempt to find a foreign id and expect a 404.
    other_user = User.create!(email_address: "intruder@example.com", password: "secret123")
    foreign_chat = other_user.chat_messages.create!(role: :outgoing, content: "steal me", parser_status: :logged)
    foreign_tx = Transaction.create!(
      chat_message: foreign_chat, amount_cents: 1000, direction: :expense,
      category: "Lainnya", occurred_on: Date.current, description: "nope"
    )

    # Integration tests render the exception as a 404 rather than raising in-process.
    get edit_transaction_path(foreign_tx)
    assert_response :not_found
  end
end
