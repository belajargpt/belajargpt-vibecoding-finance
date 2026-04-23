# Seeds the single Owner account from Rails credentials.
# Add to encrypted credentials with: EDITOR=vim bin/rails credentials:edit
#
#   owner:
#     email_address: you@example.com
#     password: your-password
#
# In development the seed falls back to a predictable dev-only credential so
# `bin/rails db:seed` works out of the box.

owner_config = Rails.application.credentials.owner || {}
email = owner_config[:email_address] || ENV["OWNER_EMAIL"] || "owner@finance-chatbot.local"
password = owner_config[:password] || ENV["OWNER_PASSWORD"] || "changeme"

if Rails.env.production? && owner_config.empty? && ENV["OWNER_EMAIL"].blank?
  raise "Production seed requires Rails.application.credentials.owner or OWNER_EMAIL / OWNER_PASSWORD env vars"
end

User.find_or_create_by!(email_address: email) do |u|
  u.password = password
end

puts "Seeded Owner: #{email}"
