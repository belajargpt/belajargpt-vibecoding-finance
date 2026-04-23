class ChatMessagesController < ApplicationController
  def index
    # Chat history rendered in views/chat_messages/index.html.erb.
    # Flesh out in U4 (streaming) and U5 (bubble partials).
  end

  def create
    # Message submission handled in U4 (enqueues ParseMessageJob, broadcasts bubbles).
    head :not_implemented
  end
end
