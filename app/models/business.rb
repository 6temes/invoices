class Business < ApplicationRecord
  has_paper_trail skip: %i[created_at updated_at next_invoice_number]

  has_one :address, as: :addressable, dependent: :destroy

  accepts_nested_attributes_for :address

  validates :name, presence: true
  validates :tax_registration_number, presence: true
  validates :bank_code, presence: true
  validates :bank_name, presence: true
  validates :bank_branch, presence: true
  validates :bank_branch_code, presence: true
  validates :bank_account_holder, presence: true
  validates :bank_account_type, presence: true
  validates :bank_account_number, presence: true
  validates :email, presence: true
  validates :tax_rate, presence: true, numericality: { greater_than: 0 }
  validates :next_invoice_number, presence: true, numericality: { greater_than: 0 }
  validates :address, presence: true
  validates_associated :address

  validate :singleton_guard

  def self.instance
    Current.business ||= includes(:address).first!
  end

  private

  def singleton_guard
    return unless self.class.where.not(id:).exists?

    errors.add :base, "only one Business record is allowed"
  end
end
