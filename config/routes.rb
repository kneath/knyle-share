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
      namespace :api do
        namespace :v1 do
          get "bundles/availability", to: "bundles#availability"
          get "bundles/:slug", to: "bundles#show", as: :bundle
          post "bundles/:slug/links", to: "bundle_links#create", as: :bundle_links
          post "uploads", to: "uploads#create", as: :uploads
          put "uploads/:id", to: "uploads#update", as: :upload
          post "uploads/:id/process", to: "uploads#process_upload", as: :process_upload
        end
      end
      get "bundles", to: "bundles#index", as: :bundles
      get "bundles/new", to: "uploads#new", as: :new_bundle
      post "uploads", to: "uploads#create", as: :uploads
      post "uploads/:id/process", to: "uploads#process_upload", as: :process_upload
      get "bundles/:id", to: "bundles#show", as: :bundle
      patch "bundles/:id/status", to: "bundles#update_status", as: :bundle_status
      patch "bundles/:id/password", to: "bundles#update_password", as: :bundle_password
      delete "bundles/:id", to: "bundles#destroy"
      get "bundles/:bundle_id/link", to: "bundle_links#new", as: :bundle_link
      post "bundles/:bundle_id/link", to: "bundle_links#create"
      get "api-tokens", to: "api_tokens#index", as: :api_tokens
      post "api-tokens", to: "api_tokens#create"
      patch "api-tokens/:id/revoke", to: "api_tokens#revoke", as: :revoke_api_token
    end
  end

  constraints BundleSubdomainHostConstraint.new(public_host) do
    scope module: :public do
      get "/", to: "bundles#show", as: :public_static_bundle
      post "access", to: "access#create", as: :public_static_bundle_access
      get "raw", to: "bundles#raw", as: :public_static_bundle_raw
      get "download", to: "bundles#download", as: :public_static_bundle_download
      get "/*asset_path", to: "bundles#asset", as: :public_static_bundle_asset
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
