require 'bcrypt'

module ChefCookbook
  module Mx
    module Postfixadmin
      def self.setup_password(password, salt)
        ::BCrypt::Password.new(::BCrypt::Engine.hash_secret(password, salt))
      end
    end
  end
end
