resource_name :mx_mta_sts_vhost
provides :mx_mta_sts_vhost

default_action :setup

property :fqdn, String, required: true
property :listen, [String, NilClass]
property :default_server, [true, false], default: false
property :access_log_options, String, default: 'combined'
property :error_log_options, String, default: 'error'
property :hsts_max_age, Integer, default: 15_724_800
property :ocsp_stapling, [true, false], default: true

property :vlt_provider, Proc, default: -> { nil }
property :vlt_format, Integer, default: 2

property :policy_mode, String, default: 'testing'
property :policy_mx, Array, required: true
property :policy_max_age, Integer, default: 86_400
property :policy_basedir, String, default: '/opt/chef-mx-mta-sts'

action :setup do
  mx_mta_sts_policy new_resource.fqdn do
    mode new_resource.policy_mode
    mx new_resource.policy_mx
    max_age new_resource.policy_max_age
    basedir new_resource.policy_basedir
    action :create
  end

  vhost_vars = {
    fqdn: new_resource.fqdn,
    listen: new_resource.listen,
    default_server: new_resource.default_server,
    access_log_options: new_resource.access_log_options,
    error_log_options: new_resource.error_log_options,
    basedir: ::File.join(new_resource.policy_basedir, new_resource.fqdn),
    hsts_max_age: new_resource.hsts_max_age,
    ocsp_stapling: new_resource.ocsp_stapling,
    certificate_entries: [],
  }

  tls_rsa_certificate new_resource.fqdn do
    vlt_provider new_resource.vlt_provider
    vlt_format new_resource.vlt_format
    action :deploy
  end

  tls = ::ChefCookbook::TLS.new(node, vlt_provider: new_resource.vlt_provider, vlt_format: new_resource.vlt_format)
  vhost_vars[:certificate_entries] << tls.rsa_certificate_entry(new_resource.fqdn)

  if tls.has_ec_certificate?(new_resource.fqdn)
    tls_ec_certificate new_resource.fqdn do
      vlt_provider new_resource.vlt_provider
      vlt_format new_resource.vlt_format
      action :deploy
    end

    vhost_vars[:certificate_entries] << tls.ec_certificate_entry(new_resource.fqdn)
  end

  nginx_vhost new_resource.name do
    cookbook 'mx'
    template 'mta-sts/nginx.vhost.erb'
    variables(lazy do
      vhost_vars.merge(
        access_log: ::File.join(
          node.run_state['nginx']['log_dir'],
          "#{new_resource.name}-access.log"
        ),
        error_log: ::File.join(
          node.run_state['nginx']['log_dir'],
          "#{new_resource.name}-error.log"
        )
      )
    end)
    action :enable
  end
end
