class Current < ActiveSupport::CurrentAttributes
  attribute :session, :business, :request_id
  delegate :user, to: :session, allow_nil: true
end
