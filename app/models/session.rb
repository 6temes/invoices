class Session < ApplicationRecord
  # LIFETIME is also the cookie's expiry, which the signed cookie enforces on its own.
  LIFETIME = 30.days
  IDLE_TIMEOUT = 14.days
  # Recording activity at most this often keeps a write off most requests.
  ACTIVITY_INTERVAL = 1.hour

  belongs_to :user

  scope :active, -> { where(updated_at: IDLE_TIMEOUT.ago.., created_at: LIFETIME.ago..) }
  scope :expired, -> { where(updated_at: ...IDLE_TIMEOUT.ago).or(where(created_at: ...LIFETIME.ago)) }

  def self.resume(id)
    active.find_by(id:)&.tap(&:record_activity)
  end

  def self.delete_expired
    expired.delete_all
  end

  def record_activity
    touch if updated_at.before?(ACTIVITY_INTERVAL.ago)
  end
end
