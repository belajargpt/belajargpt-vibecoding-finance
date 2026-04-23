RubyLLM.configure do |config|
  # Anthropic is the only provider used. Key lives in Rails credentials
  # (Rails.application.credentials.anthropic_api_key) or the ANTHROPIC_API_KEY
  # ENV var as a fallback for local dev.
  config.anthropic_api_key = Rails.application.credentials.anthropic_api_key || ENV["ANTHROPIC_API_KEY"]

  # Default model for the app. Override per-call when needed.
  # Exact dated slug is verified against Anthropic's model list at deploy time
  # (see plan Dependencies / Assumptions). `claude-haiku-4-5` is the current
  # alias; pin the dated slug once confirmed.
  config.default_model = Rails.application.credentials.anthropic_model || ENV["ANTHROPIC_MODEL"] || "claude-haiku-4-5"

  # Reasonable network timeouts so a stalled request surfaces as a failure
  # in R7's error bubble rather than hanging the background job forever.
  config.request_timeout = 15
end
