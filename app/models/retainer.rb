class Retainer < ApplicationRecord
  has_paper_trail skip: %i[created_at updated_at]

  belongs_to :client

  scope :active, -> { where(ends_on: nil).where(starts_on: ..Date.current) }

  def subject(locale: client.locale)
    key = includes_infrastructure? ? "invoice.retainer_subject_with_infrastructure" : "invoice.retainer_subject"
    I18n.with_locale(locale) { I18n.t key }
  end

  validates :monthly_hours, presence: true, numericality: { greater_than: 0 }
  validates :monthly_amount, presence: true, numericality: { greater_than: 0 }
  validates :hourly_rate, presence: true, numericality: { greater_than: 0 }
  validates :starts_on, presence: true
  validate :no_overlapping_retainer

  private

  def no_overlapping_retainer
    return if client.nil?

    scope = client.retainers.where.not(id:)

    overlapping = if ends_on.nil?
      scope.where(ends_on: nil)
        .or(scope.where("ends_on >= ?", starts_on))
    else
      scope.where(ends_on: nil).where("starts_on <= ?", ends_on)
        .or(scope.where.not(ends_on: nil).where("starts_on <= ? AND ends_on >= ?", ends_on, starts_on))
    end

    errors.add(:base, "overlaps with an existing retainer") if overlapping.exists?
  end
end
