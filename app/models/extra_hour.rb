class ExtraHour < ApplicationRecord
  has_paper_trail skip: %i[created_at updated_at]

  belongs_to :client
  belongs_to :invoice_line_item, optional: true

  validates :hours, presence: true, numericality: { greater_than: 0 }
  validates :performed_on, presence: true
  validate :line_item_belongs_to_same_client
  validate :immutable_when_billed, on: :update
  before_destroy :prevent_destroy_when_billed

  scope :unbilled, -> { where(invoice_line_item_id: nil) }

  def billed?
    invoice_line_item_id.present?
  end

  private

  def immutable_when_billed
    return unless invoice_line_item_id_was.present?
    errors.add :base, "cannot modify a billed extra hour"
  end

  def prevent_destroy_when_billed
    if billed?
      errors.add :base, "cannot delete a billed extra hour"
      throw :abort
    end
  end

  def line_item_belongs_to_same_client
    return if invoice_line_item.nil?

    return if invoice_line_item.invoice.client_id == client_id

    errors.add :invoice_line_item, "must belong to the same client"
  end
end
