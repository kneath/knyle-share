module Admin
  class BundlesController < ProtectedController
    def index
      @bundles = sample_bundles
    end

    def show
      @bundle = find_sample_bundle(params[:id])
    end
  end
end
