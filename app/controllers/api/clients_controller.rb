class Api::ClientsController < Api::BaseController
  def index
    clients = Client.order(:name).select(:id, :name, :github_repos)

    render json: clients.map { |c|
      { id: c.id, name: c.name, github_repos: c.github_repos }
    }
  end
end
