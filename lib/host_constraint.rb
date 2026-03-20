class HostConstraint
  def initialize(*hosts)
    @hosts = hosts.flatten.compact.map(&:downcase)
  end

  def matches?(request)
    @hosts.include?(request.host.downcase)
  end
end
