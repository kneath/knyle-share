module Admin
  class BundleLinksController < ProtectedController
    def new
      @bundle = find_sample_bundle(params[:bundle_id])
    end
  end
end
