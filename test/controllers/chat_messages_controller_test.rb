require "test_helper"

class ChatMessagesControllerTest < ActionDispatch::IntegrationTest
  # R1 / R12: root requires auth and redirects unauthenticated users to login.
  test "root redirects to login when unauthenticated" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "root renders chat index when authenticated" do
    sign_in_as(users(:owner))
    get root_path
    assert_response :success
  end
end
