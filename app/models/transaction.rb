class Transaction < ApplicationRecord
  CATEGORIES = {
    "expense" => [
      "Makanan & Minuman",
      "Transport",
      "Belanja",
      "Hiburan",
      "Tagihan",
      "Kesehatan",
      "Lainnya"
    ].freeze,
    "income" => [
      "Gaji",
      "Lainnya (Income)"
    ].freeze
  }.freeze

  belongs_to :chat_message, optional: true

  enum :direction, { expense: 0, income: 1 }, validate: true

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :category, presence: true
  validates :occurred_on, presence: true
  validate :category_matches_direction

  before_validation :default_occurred_on, on: :create

  scope :recent_first, -> { order(occurred_on: :desc, created_at: :desc) }

  def signed_amount_cents
    income? ? amount_cents : -amount_cents
  end

  private
    def default_occurred_on
      self.occurred_on ||= Time.current.to_date
    end

    def category_matches_direction
      return if direction.blank? # presence covered by enum validate: true
      allowed = CATEGORIES[direction]
      return if allowed&.include?(category)
      errors.add(:category, "must be one of #{allowed&.join(', ')} when direction is #{direction}")
    end
end
