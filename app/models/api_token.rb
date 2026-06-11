class ApiToken < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  attr_reader :plain_token

  def self.find_by_token(token)
    return unless token.present?

    find_by token_digest: Digest::SHA256.hexdigest(token)
  end

  def touch_last_used
    return if last_used_at && last_used_at > 1.hour.ago

    update_column :last_used_at, Time.current
  end

  private

  def generate_token
    @plain_token = SecureRandom.base58(24)
    self.token_digest = Digest::SHA256.hexdigest(@plain_token)
  end
end
