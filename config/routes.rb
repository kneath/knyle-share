admin_host = ENV.fetch("ADMIN_HOST", "admin.lvh.me")
public_host = ENV.fetch("PUBLIC_HOST", "share.lvh.me")

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  constraints HostConstraint.new(admin_host) do
    namespace :admin, path: "/" do
      root "root#show", as: :root
      get "login", to: "logins#show", as: :login
      get "setup", to: "setup#show", as: :setup
      post "setup/validate", to: "setup#validate", as: :validate_setup
      get "auth/github/callback", to: "sessions#create", as: :github_callback
      get "auth/failure", to: "sessions#failure", as: :auth_failure
      post "logout", to: "sessions#destroy", as: :logout
      get "bundles", to: "bundles#index", as: :bundles
      get "bundles/:id", to: "bundles#show", as: :bundle
      get "bundles/:bundle_id/link", to: "bundle_links#new", as: :bundle_link
    end
  end

  constraints HostConstraint.new(public_host) do
    namespace :public, path: "/" do
      root "home#show", as: :root
    end
  end

  root "home#show"
end
