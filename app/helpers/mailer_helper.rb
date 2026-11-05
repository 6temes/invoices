module MailerHelper
  # Amounts are rendered as email-safe live text (never an image) so they stay
  # legible with images disabled and survive dark-mode inversion: "¥110,000".
  def yen(amount)
    "¥#{number_with_delimiter(amount)}"
  end

  def business_bank_rows(business)
    {
      "invoice.bank_name" => business.bank_name,
      "invoice.bank_branch" => business.bank_branch,
      "invoice.bank_account_type" => business.bank_account_type,
      "invoice.bank_account_number" => business.bank_account_number,
      "invoice.bank_account_holder" => business.bank_account_holder
    }
  end

  def transfer_bank_rows(bank_details)
    {
      "invoice.bank_name" => bank_details[:bank_name],
      "invoice.bank_branch" => bank_details[:branch_name],
      "invoice.bank_account_type" => t("invoice.bank_account_types.#{bank_details[:account_type]}", default: bank_details[:account_type]),
      "invoice.bank_account_number" => bank_details[:account_number],
      "invoice.bank_account_holder" => bank_details[:account_holder_name]
    }
  end
end
