# Business (singleton)
business = Business.find_or_initialize_by(id: 1)
business.update!(
  name: "Taro Yamada",
  tax_registration_number: "T1234567890123",
  bank_code: "0001",
  bank_name: "みずほ銀行",
  bank_branch: "渋谷支店",
  bank_branch_code: "150",
  bank_account_holder: "YAMADA TARO",
  bank_account_type: "普通",
  bank_account_number: "1234567",
  email: "taro@example.com",
  tax_rate: 10.0,
  next_invoice_number: 150,
  address_attributes: {
    id: business.address&.id,
    country_code: "JP",
    postal_code: "150-0001",
    administrative_area: "東京都",
    locality: "渋谷区",
    sublocality: "神宮前",
    street: "1-2-3"
  }
)

# User
User.find_or_create_by!(email_address: "taro@example.com") do |u|
  u.password = "password"
  u.password_confirmation = "password"
end

puts "Seeded Business and User"
