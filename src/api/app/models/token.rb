class Token < ActiveRecord::Base
  belongs_to :user, foreign_key: 'user_id', inverse_of: :tokens
  belongs_to :package, inverse_of: :tokens

  validates :user_id, presence: true
  after_create :update_token

  def self.find_by_string(token)
    token = Token.where(string: token.to_s).includes(:package, :user).first
    return nil unless token and token.user_id
    # is token bound to a package?
    if token.package
      # check if user has still access
      return nil unless token.user.can_modify_package? token.package
    end

    # package found and user has write access
    return token
  end

  def update_token
    # base64 with a length that is a multiple of 3 avoids trailing "=" chars
    self.string = SecureRandom.base64(30) # 30 bytes leads to 40 chars string
    self.save!
  end

end
