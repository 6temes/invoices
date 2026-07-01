module MailerHelper
  # Amounts are rendered as email-safe live text (never an image) so they stay
  # legible with images disabled and survive dark-mode inversion: "¥110,000".
  def yen(amount)
    "¥#{number_with_delimiter(amount)}"
  end
end
