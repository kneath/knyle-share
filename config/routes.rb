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
      patch "bundles/:id/status", to: "bundles#update_status", as: :bundle_status
      patch "bundles/:id/password", to: "bundles#update_password", as: :bundle_password
      delete "bundles/:id", to: "bundles#destroy"
      get "bundles/:bundle_id/link", to: "bundle_links#new", as: :bundle_link
      post "bundles/:bundle_id/link", to: "bundle_links#create"
    end
  end

  constraints HostConstraint.new(public_host) do
    namespace :public, path: "/" do
      root "home#show", as: :root
      post ":slug/access", to: "access#create", as: :bundle_access
      get ":slug/raw", to: "bundles#raw", as: :raw_bundle
      get ":slug/download", to: "bundles#download", as: :download_bundle
      get ":slug/*asset_path", to: "bundles#asset", as: :bundle_asset
      get ":slug", to: "bundles#show", as: :bundle
    end
  end

  root "home#show"
end
