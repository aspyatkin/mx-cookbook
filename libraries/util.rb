module ChefCookbook
  module Mx
    module Util
      def self.which_exec(program)
        `which #{program}`.strip
      end
    end
  end
end
