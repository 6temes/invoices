class TaxExportsController < ApplicationController
  before_action :set_year

  def show
    @years = available_years
    @invoices = invoices_for_year.to_a
    @total_subtotal = @invoices.sum(&:subtotal)
    @total_tax = @invoices.sum(&:tax_amount)
    @total_total = @invoices.sum(&:total)

    @by_client = @invoices.group_by(&:client).transform_values do |invs|
      { subtotal: invs.sum(&:subtotal), tax: invs.sum(&:tax_amount), total: invs.sum(&:total), count: invs.size }
    end
  end

  def csv
    csv_data = CSV.generate do |csv|
      csv << %w[invoice_number issue_date paid_on client_name subtotal tax_amount total status]
      invoices_for_year.each do |inv|
        csv << [
          inv.invoice_number, inv.issue_date, inv.paid_on,
          inv.client.name, inv.subtotal, inv.tax_amount, inv.total, inv.status
        ]
      end
    end

    send_data csv_data, filename: "invoices_#{@year}.csv", type: "text/csv"
  end

  def zip
    invoices = invoices_for_year.includes(pdf_attachment: :blob, ubl_xml_attachment: :blob)

    zip_data = StringIO.new("")
    Zip::OutputStream.write_buffer(zip_data) do |zip|
      invoices.each do |inv|
        base_name = "#{inv.invoice_number}_#{inv.client.name.parameterize}_#{inv.issue_date}"

        if inv.pdf.attached?
          zip.put_next_entry "#{base_name}.pdf"
          zip.write inv.pdf.download
        end

        if inv.ubl_xml.attached?
          zip.put_next_entry "#{base_name}.xml"
          zip.write inv.ubl_xml.download
        end
      end
    end

    zip_data.rewind
    send_data zip_data.read, filename: "invoices_#{@year}.zip", type: "application/zip"
  end

  private

  def set_year
    @year = params[:year]&.to_i || Date.current.year
  end

  def invoices_for_year
    Invoice.includes(:client)
      .where(issue_date: Date.new(@year, 1, 1)..Date.new(@year, 12, 31))
      .where.not(status: :draft)
      .order(:issue_date)
  end

  def available_years
    first_invoice = Invoice.minimum(:issue_date)
    return [ Date.current.year ] unless first_invoice

    (first_invoice.year..Date.current.year).to_a.reverse
  end
end
