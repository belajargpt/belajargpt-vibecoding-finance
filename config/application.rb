require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module FinanceChatbot
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Single-user app operated from Indonesia. All timestamps and relative-date
    # parsing ("kemarin", "tadi pagi") resolve against this zone.
    config.time_zone = "Asia/Jakarta"

    # Redact chat content and auth tokens from logs. Chat messages contain
    # financial descriptions and amounts.
    config.filter_parameters += %i[ content message anthropic_api_key ]
  end
end
