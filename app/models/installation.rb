class Installation < ApplicationRecord
  def self.current
    order(:id).first || new
  end

  def claimed?
    admin_github_uid.present?
  end

  def admin_label
    admin_github_name.presence || admin_github_login.presence || "Admin"
  end

  def admin_matches?(auth)
    claimed? && admin_github_uid == auth.uid.to_s
  end

  def claim_from_auth!(auth)
    update!(
      admin_github_uid: auth.uid.to_s,
      admin_github_login: auth.info.nickname.presence || auth.info.name.to_s.parameterize.presence || auth.uid.to_s,
      admin_github_name: auth.info.name.presence || auth.info.nickname,
      admin_github_avatar_url: auth.info.image,
      admin_claimed_at: Time.current
    )
  end
end
