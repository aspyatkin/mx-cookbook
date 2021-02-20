require 'mixlib/shellout'
require 'etc'

module ChefCookbook
  module Mx
    module Rspamd
      def self.genpw(password)
        env = {
          'INPUT_PASSWORD' => password,
        }
        cmd = ::Mixlib::ShellOut.new('rspamd-genpw', environment: env)
        cmd.run_command
        cmd.error!
        cmd.stdout.strip
      end

      def self.checkpw?(password, filename)
        encrypted_pw = encrypted_password(filename)
        return false if encrypted_pw.nil?

        env = {
          'INPUT_PASSWORD' => password,
          'ENCRYPTED_PASSWORD' => encrypted_pw,
        }
        cmd = ::Mixlib::ShellOut.new('rspamd-checkpw', environment: env)
        cmd.run_command
        cmd.error!
        cmd.stdout.strip == 'correct'
      end

      def self.check_file_permissions(path, mode)
        return false unless ::File.exist?(path)

        ::File.stat(path).mode.to_s(8)[2..5] == mode
      end

      def self.encrypted_password(filename)
        return unless ::File.exist?(filename)

        s = IO.read(filename)
        m = s.match /password = "(?<encrypted_password>[a-z0-9$]+)";/
        !m.nil? && m.names.include?('encrypted_password') ? m['encrypted_password'] : nil
      end
    end
  end
end
