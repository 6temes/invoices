Rails.application.routes.draw do
  mount RailsInformant::Engine => "/informant"
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
