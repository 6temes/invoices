class InvoicesController < ApplicationController
  before_action :set_invoice, only: %i[show edit update destroy deliver payment mark_as_paid update_payment retry_delivery revert_to_draft send_reminder]

  def index
    scope = Invoice.includes(:client).order(issue_date: :desc, invoice_number: :desc)

    scope = scope.where(client_id: params[:client_id]) if params[:client_id].present?
    scope = scope.where(status: params[:status]) if params[:status].in?(Invoice.statuses.keys)

    if params[:year].present?
      year = params[:year].to_i
      scope = scope.where(issue_date: Date.new(year, 1, 1)..Date.new(year, 12, 31))
    end

    @tab = params[:tab] || "open"
    @scope = @tab == "open" ? scope.open : scope

    @invoices = set_page_and_extract_portion_from @scope

    respond_to do |format|
      format.turbo_stream if params[:page].present?
      format.html do
        @total_open = Invoice.open.sum(:total)
        @total_paid = Invoice.paid.sum(:total)
        @clients = Client.order(:name)
        @chart_data = build_chart_data
        @years = if (first = Invoice.minimum(:issue_date))
          (first.year..Date.current.year).to_a.reverse
        else
          [ Date.current.year ]
        end
      end
    end
  end

  def show
  end

  def new
    @client = Client.find params[:client_id] if params[:client_id].present?
    @business = Business.instance
    billing_month = Date.current.prev_month.beginning_of_month

    if @client && (existing = Invoice.find_by(client: @client, billing_month: billing_month))
      redirect_to existing, notice: "An invoice already exists for #{@client.name} in #{billing_month.strftime('%B %Y')}."
      return
    end

    @invoice = Invoice.new(
      client: @client,
      locale: @client&.locale || "en",
      issue_date: Date.current,
      due_date: Date.current + (@client&.payment_terms_days || 30).days,
      billing_month: billing_month,
      tax_rate: @business.tax_rate
    )

    @invoice.build_from_retainer if @client&.active_retainer
    @clients = Client.order(:name)
  end

  def create
    @invoice = Invoice.new invoice_params

    if @invoice.save
      redirect_to @invoice, notice: "Invoice created."
    else
      @business = Business.instance
      @clients = Client.order(:name)
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @invoice.errors.add :billing_month, "already has an invoice for this client"
    @business = Business.instance
    @clients = Client.order(:name)
    render :new, status: :unprocessable_entity
  end

  def edit
    unless @invoice.draft?
      redirect_to @invoice, alert: "Only draft invoices can be edited."
      return
    end
    @clients = Client.order(:name)
  end

  def update
    if @invoice.update invoice_params
      redirect_to @invoice, notice: "Invoice updated."
    else
      @clients = Client.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @invoice.draft?
      @invoice.destroy
      redirect_to invoices_path, notice: "Invoice deleted."
    else
      redirect_to @invoice, alert: "Only draft invoices can be deleted."
    end
  end

  def deliver
    unless @invoice.draft?
      redirect_to @invoice, alert: "Only draft invoices can be sent."
      return
    end

    @invoice.prepare_for_delivery!
    InvoiceDeliveryJob.perform_later @invoice

    redirect_to invoices_path, notice: "Invoice is being sent..."
  end

  def retry_delivery
    unless @invoice.failed?
      redirect_to @invoice, alert: "Only failed invoices can be retried."
      return
    end

    @invoice.retry_delivery!
    InvoiceDeliveryJob.perform_later @invoice

    redirect_to @invoice, notice: "Retrying invoice delivery..."
  end

  def revert_to_draft
    unless @invoice.failed?
      redirect_to @invoice, alert: "Only failed invoices can be reverted to draft."
      return
    end

    @invoice.revert_to_draft!

    redirect_to @invoice, notice: "Invoice reverted to draft."
  end

  def payment
    return if @invoice.sent? || @invoice.paid?

    redirect_to @invoice, alert: "Only sent or paid invoices have a payment date."
  end

  def mark_as_paid
    unless @invoice.sent?
      redirect_to @invoice, alert: "Only sent invoices can be marked as paid."
      return
    end

    @invoice.mark_as_paid! paid_on: params[:paid_on]&.to_date || Date.current

    redirect_to @invoice, notice: "Invoice marked as paid."
  end

  def send_reminder
    unless @invoice.can_send_reminder?
      redirect_to @invoice, alert: "Only sent invoices can be reminded."
      return
    end

    @invoice.record_reminder!
    InvoiceMailer.send_reminder(@invoice).deliver_later

    redirect_to @invoice, notice: "Reminder sent to #{@invoice.client.name}."
  end

  def update_payment
    unless @invoice.paid?
      redirect_to @invoice, alert: "Only paid invoices have an editable payment date."
      return
    end

    if @invoice.update paid_on: params[:paid_on]
      redirect_to @invoice, notice: "Payment date updated."
    else
      render :payment, status: :unprocessable_entity
    end
  end

  private

  def set_invoice
    @invoice = Invoice.includes(:line_items, client: :address).find params[:id]
    @business = Business.instance
  end

  def invoice_params
    params.expect(invoice: [
      :client_id, :locale, :billing_month, :issue_date, :due_date,
      :tax_rate, :notes,
      line_items_attributes: [ [ :id, :item_type, :description, :quantity, :unit_price, :amount, :_destroy ] ]
    ])
  end

  def build_chart_data
    year = params[:year]&.to_i || Date.current.year
    range = Date.new(year, 1, 1)..Date.new(year, 12, 31)

    totals_by_month = Invoice.where(billing_month: range).group(:billing_month).sum(:total)
    paid_by_month = Invoice.paid.where(billing_month: range).group(:billing_month).sum(:total)

    12.times.map do |i|
      month = Date.new(year, i + 1, 1)
      { month: month.strftime("%b"), total: totals_by_month[month] || 0, paid: paid_by_month[month] || 0 }
    end
  end
end
