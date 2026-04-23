require "test_helper"

class ChatMessageTest < ActiveSupport::TestCase
  setup { @user = users(:owner) }

  test "defaults role to outgoing and status to pending" do
    message = ChatMessage.create!(user: @user, content: "abis beli batagor 5rb")
    assert_equal "outgoing", message.role
    assert_equal "pending", message.parser_status
  end

  test "requires content" do
    message = ChatMessage.new(user: @user)
    assert_not message.valid?
    assert_includes message.errors[:content], "can't be blank"
  end

  test "user.chat_messages returns owner's messages" do
    message = ChatMessage.create!(user: @user, content: "test")
    assert_includes @user.chat_messages.reload, message
  end

  test "user.transactions returns rows through chat_messages" do
    assert_includes @user.transactions.reload, transactions(:batagor)
  end

  test "deleting chat_message nullifies transactions.chat_message_id" do
    tx = transactions(:batagor)
    tx.chat_message.destroy
    tx.reload
    assert_nil tx.chat_message_id
  end
end
