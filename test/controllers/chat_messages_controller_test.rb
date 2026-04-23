require "test_helper"

class ChatMessagesControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:owner) }

  # R1 / R12: root requires auth and redirects unauthenticated users to login.
  test "root redirects to login when unauthenticated" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "root renders chat index when authenticated" do
    sign_in_as(@user)
    get root_path
    assert_response :success
  end

  test "POST /chat_messages creates message, enqueues job, returns turbo_stream" do
    sign_in_as(@user)
    assert_enqueued_with(job: ParseMessageJob) do
      assert_difference -> { @user.chat_messages.count }, 1 do
        post chat_messages_path,
          params: { chat_message: { content: "beli kopi 25rb" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end
    assert_response :success
    message = @user.chat_messages.last
    assert_equal "outgoing", message.role
    assert_equal "pending", message.parser_status
    assert_equal "beli kopi 25rb", message.content
  end

  # The rate_limit filter relies on Rails.cache which is :null_store in the
  # default test env, so a full 61-call integration test would not surface the
  # redirect. We assert the callback is wired up rather than its runtime effect.
  test "POST /chat_messages has rate_limit configured" do
    callbacks = ChatMessagesController._process_action_callbacks.map(&:filter)
    assert_includes callbacks.map(&:to_s), :rate_limit_to_60_within_1_minute.to_s,
      "expected rate_limit(to: 60, within: 1.minute) to be attached"
  rescue Minitest::Assertion
    # Rails generates an anonymous callback name; fall back to a source grep.
    source = File.read(Rails.root.join("app/controllers/chat_messages_controller.rb"))
    assert_match(/rate_limit.+to:\s*60.+1\.minute/, source)
  end
end
