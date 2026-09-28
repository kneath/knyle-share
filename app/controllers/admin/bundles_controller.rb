module Admin
  class BundlesController < ProtectedController
    before_action :set_bundle, only: %i[show update update_status update_password destroy revoke_links]

    def index
      scope = Bundle.all
      @query = params[:q].to_s.strip.first(200)
      if @query.present?
        pattern = "%#{Bundle.sanitize_sql_like(@query)}%"
        scope = scope.where("title LIKE ? OR slug LIKE ?", pattern, pattern)
      end
      scope = scope.where(access_mode: params[:access]) if %w[public protected].include?(params[:access])
      scope = scope.where(status: params[:status]) if %w[active disabled].include?(params[:status])
      order = { "newest" => { created_at: :desc }, "name" => { title: :asc }, "views" => { total_views_count: :desc } }.fetch(params[:sort], { updated_at: :desc })
      @total = scope.count
      @pages = [(@total / 25.0).ceil, 1].max
      @page = [[params[:page].to_i, 1].max, @pages].min
      @bundles = scope.order(order).order(id: :desc).includes(:primary_asset).limit(25).offset((@page - 1) * 25)
      @cleanup_count = StorageCleanup.count
      @cleanup_failed = StorageCleanup.where.not(last_error: nil).exists?
    end

    def show
      @generated_password = flash[:generated_password]
      @library_path = SafeReturnPath.call(params[:from], fallback: admin_bundles_path)
    end

    def update
      attributes = params.require(:bundle).permit(:title, :description, :access_mode)
      @bundle.with_lock do
        if attributes[:access_mode].present? && attributes[:access_mode] != @bundle.access_mode
          @bundle.access_revision += 1
          if attributes[:access_mode] == "protected"
            @generated_password = GeneratedPassword.generate
            @bundle.password = @generated_password
          elsif attributes[:access_mode] == "public"
            @bundle.password_digest = nil
          end
        end
        @bundle.update!(attributes)
      end
      flash[:generated_password] = @generated_password if @generated_password
      redirect_to admin_bundle_path(@bundle), notice: "Bundle details saved."
    rescue ActiveRecord::RecordInvalid => error
      message = error.record.errors.full_messages.to_sentence
      @bundle.reload
      redirect_to admin_bundle_path(@bundle), alert: message
    end

    def revoke_links
      @bundle.rotate_access_revision!
      redirect_to admin_bundle_path(@bundle), notice: "Previous expiring links and password sessions have been revoked. The password is unchanged."
    end

    def retry_cleanup
      StorageCleanup.update_all(next_attempt_at: Time.current)
      StorageCleanup.find_each { |cleanup| StorageCleanupJob.perform_later(cleanup.id) }
      redirect_to admin_bundles_path, notice: "File cleanup queued for retry."
    end

    def update_status
      @bundle.toggle_status!

      redirect_to admin_bundle_path(@bundle), notice: "Bundle #{@bundle.active? ? "enabled" : "disabled"}."
    end

    def update_password
      unless @bundle.protected_access?
        redirect_to admin_bundle_path(@bundle), alert: "Passwords only apply to protected bundles."
        return
      end

      new_password =
        if params[:password_strategy] == "custom"
          bundle_password_params[:password].to_s.strip
        else
          GeneratedPassword.generate
        end

      if new_password.blank?
        redirect_to admin_bundle_path(@bundle), alert: "Enter a password or generate one."
        return
      end

      @bundle.set_password!(new_password)
      flash[:generated_password] = new_password
      redirect_to admin_bundle_path(@bundle), notice: "Password replaced for #{@bundle.slug}."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to admin_bundle_path(@bundle), alert: error.record.errors.full_messages.to_sentence
    end

    def destroy
      slug = @bundle.slug
      @bundle.destroy!

      redirect_to admin_bundles_path, notice: "Deleted #{slug}. Stored files are queued for removal; cleanup will retry automatically if storage is unavailable."
    end

    private

    def set_bundle
      @bundle = Bundle.find_by!(slug: params[:id])
    end

    def bundle_password_params
      params.fetch(:bundle, ActionController::Parameters.new).permit(:password)
    end
  end
end
