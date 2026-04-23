Rails.application.routes.draw do
  resource :session, only: [ :new, :create, :destroy ]

  resources :chat_messages, only: [ :index, :create ]
  resources :transactions, only: [ :index, :edit, :update, :destroy ]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  root "chat_messages#index"
end
