class User < ApplicationRecord
  PASSWORD_MINIMUM_LENGTH = 12

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :api_tokens, dependent: :destroy

  validates :password, length: { minimum: PASSWORD_MINIMUM_LENGTH }, allow_nil: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
