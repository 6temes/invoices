class Api::ExtraHoursController < Api::BaseController
  def create
    extra_hour = ExtraHour.new extra_hour_params

    if extra_hour.save
      render json: extra_hour.as_json(only: %i[id client_id hours description performed_on github_url created_at]),
             status: :created
    else
      render json: { errors: extra_hour.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def extra_hour_params
    params.permit(:client_id, :hours, :description, :performed_on, :github_url)
  end
end
