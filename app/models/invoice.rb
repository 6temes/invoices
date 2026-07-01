class Invoice < ApplicationRecord
  class InvalidStatusError < StandardError; end

  has_paper_trail skip: %i[created_at updated_at]

  broadcasts_refreshes

  belongs_to :client
  has_many :line_items, class_name: "InvoiceLineItem", dependent: :destroy
  has_one_attached :pdf
  has_one_attached :ubl_xml

  accepts_nested_attributes_for :line_items, reject_if: :all_blank, allow_destroy: true

  enum :status, %w[ draft preparing sent failed paid ].index_by(&:itself)

  validates :billing_month, uniqueness: { scope: :client_id, message: "already has an invoice for this client" }
  validates :invoice_number, uniqueness: true
  # Denormalized string snapshot (not an enum) so the invoice preserves the
  # exact locale at time of creation even if the client's locale changes later
  validates :locale, presence: true
  validates :issue_date, presence: true
  validates :due_date, presence: true
  validates :tax_rate, presence: true
  validates :status, presence: true
  validates :paid_on, presence: true, if: :paid?
  validate :at_least_one_line_item
  validate :paid_on_in_valid_range, if: :paid?

  validate :pdf_presence_matches_status
  validate :ubl_xml_presence_matches_status
  validate :immutable_when_frozen, on: :update

  before_validation :recalculate_totals, if: :draft?
  after_save :persist_extra_hour_linkages, if: -> { @_pending_extra_hours.present? }

  scope :open, -> { where.not(status: :paid) }

  before_create :assign_next_number

  PAYMENT_FIELDS = %w[sent_at status paid_on paid_amount stripe_checkout_session_id stripe_payment_intent_id].freeze
  # Reminder metadata is operational, not invoice content, so it stays editable
  # on frozen (non-draft) invoices — see immutable_when_frozen.
  REMINDER_FIELDS = %w[reminded_at reminders_count].freeze

  def build_from_retainer
    retainer = client.active_retainer
    return unless retainer

    build_retainer_line_item retainer
    build_extra_hour_line_items retainer
    recalculate_totals
  end

  def recalculate_totals
    active_items = line_items.reject(&:marked_for_destruction?)
    active_items.each { _1.send(:calculate_amount) }
    self.subtotal = active_items.sum { _1.amount || 0 }
    self.tax_amount = (subtotal * tax_rate / 100).floor
    self.total = subtotal + tax_amount
  end

  def mark_as_paid!(paid_on: Date.current, stripe_checkout_session_id: nil, stripe_payment_intent_id: nil)
    update! status: :paid, paid_on:, paid_amount: total,
            stripe_checkout_session_id:, stripe_payment_intent_id:
  end

  def can_send_reminder?
    sent?
  end

  def record_reminder!
    update! reminded_at: Time.current, reminders_count: reminders_count + 1
  end

  def prepare_for_delivery!
    raise InvalidStatusError, "Invoice must be in draft status to prepare for delivery" unless draft?

    update! status: :preparing
  end

  def mark_as_failed!
    raise InvalidStatusError, "Invoice must be in preparing status to mark as failed" unless preparing?

    update! status: :failed
  end

  def retry_delivery!
    raise InvalidStatusError, "Invoice must be in failed status to retry delivery" unless failed?

    update! status: :preparing, stripe_checkout_session_id: nil
  end

  def revert_to_draft!
    raise InvalidStatusError, "Invoice must be in failed status to revert to draft" unless failed?

    update! status: :draft, stripe_checkout_session_id: nil
  end

  def deliver!
    raise InvalidStatusError, "Invoice must be in preparing status to deliver" unless preparing?

    create_checkout_session! if client.credit_card? && stripe_checkout_session_id.blank?

    html = render_standalone_html
    pdf_binary = CloudflarePdfGateway.render html
    xml_string = UblInvoiceBuilder.new(self).to_xml

    transaction do
      pdf.attach io: StringIO.new(pdf_binary), filename: pdf_filename, content_type: "application/pdf"
      ubl_xml.attach io: StringIO.new(xml_string), filename: ubl_filename, content_type: "application/xml"
      update! status: :sent, sent_at: Time.current
    end

    InvoiceMailer.send_invoice(self).deliver_later
  end

  def create_checkout_session!
    raise InvalidStatusError, "Cannot create checkout session for paid invoice" if paid?

    token = signed_id purpose: :payment, expires_in: 60.days
    host = default_host

    session = Stripe::Checkout::Session.create(
      customer: client.stripe_customer.id,
      line_items: [ {
        price_data: {
          currency: "jpy",
          product_data: { name: "Invoice ##{invoice_number} — #{subject}" },
          unit_amount: total
        },
        quantity: 1
      } ],
      mode: "payment",
      success_url: Rails.application.routes.url_helpers.public_payment_url(token:, host:),
      cancel_url: Rails.application.routes.url_helpers.public_payment_url(token:, host:),
      metadata: { invoice_id: id }
    )

    update! stripe_checkout_session_id: session.id
    session
  end

  def subject
    I18n.with_locale(locale) { I18n.t "invoice.subject" }
  end

  def localized_billing_period
    I18n.with_locale(locale) do
      I18n.t "invoice.month_year",
        year: billing_month.year,
        month: billing_month.month,
        month_name: billing_month.strftime("%B")
    end
  end

  private

  def at_least_one_line_item
    return if line_items.reject(&:marked_for_destruction?).any?

    errors.add :base, "must have at least one line item"
  end

  def paid_on_in_valid_range
    return if paid_on.blank?

    errors.add :paid_on, "can't be in the future" if paid_on > Date.current
    errors.add :paid_on, "can't be earlier than the issue date" if issue_date && paid_on < issue_date
  end

  def build_retainer_line_item(retainer)
    period = localized_billing_period

    description = I18n.with_locale(locale) do
      I18n.t "invoice.retainer_line",
        subject: retainer.subject(locale:),
        period:,
        hours: retainer.monthly_hours.to_i
    end

    line_items.build(
      item_type: "Service",
      description:,
      quantity: 1,
      unit_price: retainer.monthly_amount,
      amount: retainer.monthly_amount,
      origin: :retainer
    )
  end

  def build_extra_hour_line_items(retainer)
    unbilled = client.extra_hours.where(invoice_line_item_id: nil)

    # Entries with descriptions become individual line items
    unbilled.where.not(description: [ nil, "" ]).find_each do |extra|
      description = I18n.with_locale(locale) do
        I18n.t "invoice.extra_hours_with_desc",
          description: extra.description,
          hours: extra.hours
      end

      line_item = line_items.build(
        item_type: "Service",
        description:,
        quantity: extra.hours,
        unit_price: retainer.hourly_rate,
        amount: (extra.hours * retainer.hourly_rate).floor,
        origin: :extra_hours
      )
      (@_pending_extra_hours ||= []) << [ extra, line_item ]
    end

    # Entries without descriptions are aggregated
    generic_extras = unbilled.where(description: [ nil, "" ])
    return unless generic_extras.exists?

    total_hours = generic_extras.sum(:hours)
    description = I18n.with_locale(locale) do
      I18n.t "invoice.extra_hours_generic", hours: total_hours
    end

    line_item = line_items.build(
      item_type: "Service",
      description:,
      quantity: total_hours,
      unit_price: retainer.hourly_rate,
      amount: (total_hours * retainer.hourly_rate).floor,
      origin: :extra_hours
    )
    generic_extras.each { |e| (@_pending_extra_hours ||= []) << [ e, line_item ] }
  end

  def assign_next_number
    return if invoice_number.present?

    business = Business.instance
    business.with_lock do
      self.invoice_number = business.next_invoice_number
      business.increment! :next_invoice_number
    end
  end

  def persist_extra_hour_linkages
    return unless @_pending_extra_hours&.any?

    @_pending_extra_hours.group_by { |_, li| li }.each do |line_item, pairs|
      ExtraHour.where(id: pairs.map(&:first).map(&:id)).update_all(invoice_line_item_id: line_item.id)
    end
    @_pending_extra_hours = nil
  end

  def pdf_presence_matches_status
    if draft? && pdf.attached?
      errors.add :pdf, "must not be attached for draft invoices"
    elsif (sent? || paid?) && !pdf.attached?
      errors.add :pdf, "must be attached for sent or paid invoices"
    end
  end

  def ubl_xml_presence_matches_status
    if draft? && ubl_xml.attached?
      errors.add :ubl_xml, "must not be attached for draft invoices"
    elsif (sent? || paid?) && !ubl_xml.attached?
      errors.add :ubl_xml, "must be attached for sent or paid invoices"
    end
  end

  def immutable_when_frozen
    return if draft?

    changed_fields = changed - PAYMENT_FIELDS - REMINDER_FIELDS - %w[updated_at]
    return if changed_fields.empty?

    errors.add :base, "cannot modify a #{status} invoice (only payment fields are allowed)"
  end

  def render_standalone_html
    ApplicationController.renderer.new(
      "HTTP_HOST" => default_host
    ).render(
      partial: "invoices/pdf_template",
      locals: { invoice: self, business: Business.instance },
      formats: [ :html ]
    )
  end

  def default_host
    ENV.fetch("APP_HOST", "localhost:3000")
  end

  def pdf_filename
    "invoice_#{invoice_number}.pdf"
  end

  def ubl_filename
    "invoice_#{invoice_number}.xml"
  end
end
