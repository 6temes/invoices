class InvoiceLineItem < ApplicationRecord
  belongs_to :invoice
  has_many :extra_hours, dependent: :restrict_with_error

  enum :origin, %w[extra_hours manual retainer].index_by(&:itself)

  validates :item_type, presence: true
  validates :description, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :amount, presence: true

  before_validation :calculate_amount
  private

  def calculate_amount
    return unless quantity && unit_price

    self.amount = (quantity * unit_price).floor
  end
end
