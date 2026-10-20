Rails.application.routes.draw do
  mount RailsInformant::Engine => "/informant"

  if Rails.env.development?
    # Hyperdrive's MCP endpoint runs arbitrary Ruby with no authentication, and the gem
    # itself only rejects foreign browser Origins. A tunnel delivers requests from
    # 127.0.0.1 too, so this reads the raw socket address and Host header (request.host
    # and remote_ip trust X-Forwarded-*) and refuses anything a proxy forwarded.
    forwarded = %w[HTTP_FORWARDED HTTP_X_FORWARDED_FOR HTTP_X_FORWARDED_HOST HTTP_CF_CONNECTING_IP]
    direct_loopback = lambda do |request|
      request.remote_addr.in?(%w[127.0.0.1 ::1]) &&
        request.get_header("HTTP_HOST").to_s.sub(/:\d+\z/, "").in?(%w[localhost 127.0.0.1 [::1]]) &&
        forwarded.none? { request.has_header? it }
    end
    constraints direct_loopback do
      mount Rails::Hyperdrive::Engine => "/_hyperdrive"
    end
  end
  mount MissionControl::Jobs::Engine, at: "/jobs"
  resource :session, only: [ :new, :create, :destroy ]
  resources :passwords, param: :token, only: [ :new, :create, :edit, :update ]

  resource :business, only: [ :edit, :update ] do
    resources :api_tokens, only: [ :create, :destroy ]
  end

  resources :clients do
    resources :retainers, except: [ :index ]
    resources :extra_hours, only: [ :new, :create, :edit, :update, :destroy ]
  end

  resources :invoices do
    member do
      post :deliver
      get :payment
      post :mark_as_paid
      patch :update_payment
      post :retry_delivery
      post :revert_to_draft
      post :send_reminder
    end
  end

  # Public (unauthenticated) payment flow
  get "pay/:token", to: "payments#show", as: :public_payment
  post "pay/:token", to: "payments#create", as: :public_payment_create

  # Stripe webhook (unauthenticated, signature-verified)
  post "webhooks/stripe", to: "webhooks#stripe"

  # Tax export
  resource :tax_export, only: [ :show ] do
    get :csv
    get :zip
  end

  # JSON API for Chrome extension
  namespace :api do
    resources :extra_hours, only: [ :create ]
    resources :clients, only: [ :index ]
  end

  # Address form helpers
  resource :postal_code_lookup, only: [ :show ]
  resource :address_fields, only: [ :show ]

  root "invoices#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
