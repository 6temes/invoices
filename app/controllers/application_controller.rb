class ApplicationController < ActionController::Base
  include Authentication
  include GearedPagination::Controller

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_current_request_id

  private

  def set_current_request_id
    Current.request_id = request.request_id
  end

  def user_for_paper_trail
    Current.user
  end
end
