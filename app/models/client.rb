class Client < ApplicationRecord
  has_paper_trail skip: %i[created_at updated_at]

  has_one :address, as: :addressable, dependent: :destroy
  has_many :retainers, dependent: :destroy
  has_many :extra_hours, dependent: :destroy
  has_many :invoices, dependent: :destroy

  before_destroy :ensure_no_finalized_invoices

  accepts_nested_attributes_for :address, allow_destroy: true
  validates :address, presence: true
  validates_associated :address

  enum :locale, %w[ en ja ].index_by(&:itself)
  enum :payment_method, %w[ bank_transfer credit_card ].index_by(&:itself)

  serialize :github_repos, coder: JSON, default: []

  validates :contact_name, presence: true
  validates :name, presence: true
  validates :email, presence: true
  validates :locale, presence: true
  validates :payment_method, presence: true
  validates :payment_terms_days, presence: true, numericality: { greater_than: 0 }
  validate :stripe_customer_id_absent_for_bank_transfer

  def email_with_name
    ActionMailer::Base.email_address_with_name email, contact_name
  end

  def stripe_customer
    if self[:stripe_customer_id].present?
      Stripe::Customer.retrieve self[:stripe_customer_id]
    else
      customer = Stripe::Customer.create(
        { name:, email: },
        { idempotency_key: "create-customer-for-client-#{id}" }
      )
      update_column :stripe_customer_id, customer.id
      customer
    end
  end

  def active_retainer
    retainers.active.first
  end

  def github_repos_text=(text)
    self.github_repos = text.split("\n").map(&:strip).reject(&:blank?)
  end

  def github_repos_text
    Array(github_repos).join("\n")
  end

  private

  def ensure_no_finalized_invoices
    return unless invoices.where.not(status: :draft).exists?

    errors.add :base, "cannot delete a client with sent or paid invoices"
    throw :abort
  end

  def stripe_customer_id_absent_for_bank_transfer
    return unless bank_transfer? && stripe_customer_id.present?

    errors.add :stripe_customer_id, "must be blank for bank transfer clients"
  end
end
