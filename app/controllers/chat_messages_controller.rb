class ChatMessagesController < ApplicationController
  # Abuse protection: cap chat submissions so a leaked password cannot burn
  # Anthropic credits unboundedly. Single user app, 60/minute is generous.
  rate_limit to: 60, within: 1.minute, only: :create,
    with: -> { redirect_to root_path, alert: "Pelan-pelan dulu." }

  def index
    @chat_messages = Current.user.chat_messages.chronological.last(200)
  end

  def create
    @chat_message = Current.user.chat_messages.create!(
      role: :outgoing,
      content: params.require(:chat_message).fetch(:content).to_s.strip,
      parser_status: :pending
    )

    ParseMessageJob.perform_later(@chat_message)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path }
    end
  end
end
