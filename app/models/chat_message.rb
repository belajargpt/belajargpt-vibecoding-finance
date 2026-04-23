class ChatMessage < ApplicationRecord
  belongs_to :user
  has_many :transactions, dependent: :nullify

  enum :role, { outgoing: 0, incoming: 1 }, validate: true
  enum :parser_status, {
    pending: 0,
    logged: 1,
    not_transaction: 2,
    failed: 3
  }, validate: true

  validates :content, presence: true

  scope :chronological, -> { order(created_at: :asc) }
end
