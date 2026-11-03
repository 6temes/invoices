class InvoicePayment < ApplicationRecord
  has_paper_trail skip: %i[created_at updated_at]

  belongs_to :invoice

  # credit is cash balance drawn at delivery and printed on the invoice; balance
  # is cash balance applied after sending, which leaves the issued documents alone.
  enum :kind, %w[ balance checkout credit manual ].index_by(&:itself)
  enum :status, %w[ pending succeeded ].index_by(&:itself)

  attribute :paid_on, default: -> { Date.current }

  scope :awaiting_refund, -> { where(excess_amount: 1.., stripe_refund_id: nil) }

  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validate :only_kept_credit_on_a_draft

  private

  # Reverting a failed delivery keeps its credit: Stripe can only refund a cash
  # balance payment to the client's bank, not back into the balance.
  def only_kept_credit_on_a_draft
    errors.add :kind, "cannot be recorded on a draft invoice" if invoice&.draft? && !credit?
  end
end
