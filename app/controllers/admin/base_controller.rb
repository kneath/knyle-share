module Admin
  class BaseController < ApplicationController
    layout "admin"

    helper_method :installation, :admin_signed_in?

    private

    def installation
      @installation ||= Installation.current
    end

    def admin_signed_in?
      installation.claimed? && session[:admin_github_uid] == installation.admin_github_uid
    end

    def require_admin!
      return if admin_signed_in?

      redirect_to(installation.claimed? ? admin_login_path : admin_setup_path)
    end

    def sample_bundles
      @sample_bundles ||= [
        {
          slug: "poke-recipes",
          presentation_label: "Static Site",
          access_label: "Protected",
          access_class: "badge-protected",
          status_label: "Active",
          status_class: "badge-active",
          views: "12 views",
          unique_viewers: "4",
          last_viewed: "2 hours ago",
          created_at: "Mar 13, 2026",
          bundle_url: "https://share.warpspire.com/poke-recipes",
          password: "river maple lantern",
          source_label: "Directory",
          size: "2.4 MB",
          files: "14 files",
          last_replaced: "Never"
        },
        {
          slug: "landscaping-project",
          presentation_label: "Single Download",
          access_label: "Public",
          access_class: "badge-public",
          status_label: "Active",
          status_class: "badge-active",
          views: "3 views",
          unique_viewers: "n/a",
          last_viewed: "Yesterday",
          created_at: "Mar 10, 2026",
          bundle_url: "https://share.warpspire.com/landscaping-project",
          password: nil,
          source_label: "File",
          size: "43 MB",
          files: "1 file",
          last_replaced: "Mar 18, 2026"
        },
        {
          slug: "sierra-draft",
          presentation_label: "Markdown",
          access_label: "Protected",
          access_class: "badge-protected",
          status_label: "Active",
          status_class: "badge-active",
          views: "8 views",
          unique_viewers: "3",
          last_viewed: "3 days ago",
          created_at: "Mar 08, 2026",
          bundle_url: "https://share.warpspire.com/sierra-draft",
          password: "cedar lantern harbor",
          source_label: "File",
          size: "186 KB",
          files: "1 file",
          last_replaced: "Never"
        },
        {
          slug: "old-mockups",
          presentation_label: "File Listing",
          access_label: "Public",
          access_class: "badge-public",
          status_label: "Disabled",
          status_class: "badge-disabled",
          views: "0 views",
          unique_viewers: "n/a",
          last_viewed: "Never viewed",
          created_at: "Feb 22, 2026",
          bundle_url: "https://share.warpspire.com/old-mockups",
          password: nil,
          source_label: "Directory",
          size: "12 MB",
          files: "22 files",
          last_replaced: "Mar 01, 2026"
        }
      ]
    end

    def find_sample_bundle(slug)
      sample_bundles.find { |bundle| bundle[:slug] == slug } || sample_bundles.first
    end
  end
end
