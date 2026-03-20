class BundleSubdomainHostConstraint
  def initialize(public_host)
    @public_host = public_host
  end

  def matches?(request)
    PublicBundleRouting.bundle_host?(host: request.host, public_host: @public_host)
  end
end
