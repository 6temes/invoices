class Client < ApplicationRecord
  # What Stripe charges to return a cash balance to the client's bank. Copy and
  # the return page read it from here, so a wrong figure is corrected once.
  CASH_BALANCE_RETURN_FEE = 275

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
  enum :payment_method, %w[ bank_transfer stripe ].index_by(&:itself)

  serialize :github_repos, coder: JSON, default: []

  validates :contact_name, presence: true
  validates :name, presence: true
  validates :email, presence: true
  validates :locale, presence: true
  validates :payment_method, presence: true
  validates :payment_terms_days, presence: true, numericality: { greater_than: 0 }
  validate :stripe_customer_id_absent_for_bank_transfer

  # Keyed on the credit last emailed, so a link dies once newer credit is announced
  # or a return empties the balance.
  generates_token_for :credit_refund, expires_in: Invoice::PAYMENT_LINK_VALIDITY do
    credit_notified_amount
  end

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

  def cash_balance
    return 0 if stripe_customer_id.blank?

    customer = Stripe::Customer.retrieve id: stripe_customer_id, expand: [ "cash_balance" ]
    customer.to_hash.dig(:cash_balance, :available, :jpy) || 0
  end

  # A return cancelled after Stripe's 45 days leaves the fee already charged, so
  # the next return is free.
  def return_fee
    prepaid_return_fee_payment_intent_id ? 0 : CASH_BALANCE_RETURN_FEE
  end

  def returnable_credit(balance)
    balance > return_fee ? balance - return_fee : 0
  end

  # The refund goes first, so a failed fee charge leaves the fee as credit rather
  # than charging the client for a return that never started. The keys turn a
  # double submit into a replay.
  def refund_cash_balance!(shown_balance)
    balance = cash_balance
    return :changed unless balance == shown_balance
    return :nothing_to_return if returnable_credit(balance).zero?

    fee = return_fee
    key = "#{id}-#{balance}-#{Date.current.iso8601}"
    refund = Stripe::Refund.create(
      { origin: "customer_balance", customer: stripe_customer_id, amount: balance - fee, currency: Invoice::Payable::CURRENCY, instructions_email: email },
      { idempotency_key: "return-#{key}" }
    )
    fee.positive? ? charge_return_fee(fee, refund, key) : update!(prepaid_return_fee_payment_intent_id: nil)
    update! credit_notified_amount: 0
    :returned
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

  def charge_return_fee(fee, refund, key)
    intent = Stripe::PaymentIntent.create({
      amount: fee,
      currency: Invoice::Payable::CURRENCY,
      customer: stripe_customer_id,
      automatic_payment_methods: { enabled: true, allow_redirects: "never" },
      payment_method_data: { type: "customer_balance" },
      confirm: true,
      metadata: { credit_return_refund: refund.id }
    }, { idempotency_key: "return-fee-#{key}" })

    # Left waiting, Stripe would collect the fee from the client's next transfer.
    Stripe::PaymentIntent.cancel intent.id if intent.status == "requires_action"
  end

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
