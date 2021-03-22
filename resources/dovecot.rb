resource_name :mx_dovecot
provides :mx_dovecot

default_action :setup

property :fqdn, String, required: true

property :vmail_state, Hash, required: true
property :postfix_state, Hash, required: true

property :db_host, String, default: '127.0.0.1'
property :db_port, Integer, default: 5432
property :db_name, String, required: true
property :db_user, String, required: true
property :db_password, String, required: true
property :db_root_user, String, required: true
property :db_root_password, String, required: true

property :vlt_provider, Proc, default: -> { nil }
property :vlt_format, Integer, default: 2

property :postmaster, String, required: true

property :dh_param_file, String, required: true

property :imap_mail_max_userip_connections, Integer, default: 10

property :imap_login_service_count, Integer, default: 1
property :imap_login_process_min_avail, Integer, default: 0
property :imap_login_process_limit, [String, Integer], default: '$default_process_limit'
property :imap_login_vsz_limit, String, default: '64M'

property :pop3, [true, false], default: false
property :pop3_login_service_count, Integer, default: 1
property :pop3_lock_session, [true, false], default: true
property :pop3_fast_size_lookups, [true, false], default: true
property :pop3_no_flag_updates, [true, false], default: true

action :setup do
  package 'dovecot-core'
  package 'dovecot-imapd'
  package 'dovecot-lmtpd'
  package 'dovecot-pgsql'
  package 'dovecot-sieve'
  package 'dovecot-managesieved'

  if new_resource.pop3
    package 'dovecot-pop3d'
  end

  service 'dovecot' do
    action [:enable, :start]
  end

  postgresql_user new_resource.db_user do
    password new_resource.db_password
    action :create
  end

  dovecot_dir = '/etc/dovecot'

  grant_access_script = ::File.join(dovecot_dir, 'postgres_grant_access.sql')

  template grant_access_script do
    cookbook 'mx'
    source 'dovecot/postgres_grant_access.sql.erb'
    owner 'root'
    group node['root_group']
    mode '0640'
    variables(
      user: new_resource.db_user
    )
  end

  execute 'grant access to postfixadmin tables' do
    command "psql -h #{new_resource.db_host} -p #{new_resource.db_port} -U #{new_resource.db_root_user} -d #{new_resource.db_name} -f #{grant_access_script}"
    user 'root'
    group node['root_group']
    environment(
      'PGPASSWORD' => new_resource.db_root_password
    )
    sensitive true
    action :run
  end

  template '/etc/dovecot/dovecot-sql.conf.ext' do
    cookbook 'mx'
    source 'dovecot/dovecot-sql.conf.ext.erb'
    mode '0640'
    variables(
      user: new_resource.db_user,
      password: new_resource.db_password,
      host: new_resource.db_host,
      port: new_resource.db_port,
      dbname: new_resource.db_name,
      vmail_uid: new_resource.vmail_state['uid'],
      vmail_gid: new_resource.vmail_state['gid']
    )
    sensitive true
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  dict_sql_conf = ::File.join(dovecot_dir, 'dovecot-dict-sql.conf.ext')

  template dict_sql_conf do
    cookbook 'mx'
    source 'dovecot/dovecot-dict-sql.conf.ext.erb'
    mode '0640'
    variables(
      user: new_resource.db_user,
      password: new_resource.db_password,
      host: new_resource.db_host,
      port: new_resource.db_port,
      dbname: new_resource.db_name
    )
    sensitive true
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  dovecot_protocols = %w[imap lmtp sieve]

  if new_resource.pop3
    dovecot_protocols << 'pop3'
  end

  template '/etc/dovecot/local.conf' do
    cookbook 'mx'
    source 'dovecot/local.conf.erb'
    mode '0644'
    variables(
      protocols: dovecot_protocols,
      dict_sql_conf: dict_sql_conf
    )
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  template '/etc/dovecot/conf.d/10-mail.conf' do
    cookbook 'mx'
    source 'dovecot/10-mail.conf.erb'
    mode '0644'
    variables(
      vmail_mailbox_dir: new_resource.vmail_state['mailbox_dir'],
      vmail_user: new_resource.vmail_state['user'],
      vmail_group: new_resource.vmail_state['group']
    )
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  template '/etc/dovecot/conf.d/10-auth.conf' do
    cookbook 'mx'
    source 'dovecot/10-auth.conf.erb'
    mode '0644'
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  tls = ::ChefCookbook::TLS.new(node, vlt_provider: new_resource.vlt_provider, vlt_format: new_resource.vlt_format)

  tls_rsa_certificate new_resource.fqdn do
    vlt_provider new_resource.vlt_provider
    vlt_format new_resource.vlt_format
    action :deploy
  end

  if tls.has_ec_certificate?(new_resource.fqdn)
    tls_ec_certificate new_resource.fqdn do
      vlt_provider new_resource.vlt_provider
      vlt_format new_resource.vlt_format
      action :deploy
    end
  end

  template '/etc/dovecot/conf.d/10-ssl.conf' do
    cookbook 'mx'
    source 'dovecot/10-ssl.conf.erb'
    mode '0644'
    variables(
      dh_param_file: new_resource.dh_param_file,
      rsa_certificate_entry: tls.rsa_certificate_entry(new_resource.fqdn),
      ecc_certificate_entry: tls.has_ec_certificate?(new_resource.fqdn) ? tls.ec_certificate_entry(new_resource.fqdn) : nil
    )
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  template '/etc/dovecot/conf.d/10-master.conf' do
    cookbook 'mx'
    source 'dovecot/10-master.conf.erb'
    mode '0644'
    variables(
      vmail_user: new_resource.vmail_state['user'],
      vmail_group: new_resource.vmail_state['group'],
      postfix_user: new_resource.postfix_state['user'],
      postfix_group: new_resource.postfix_state['group'],
      imap_login_service_count: new_resource.imap_login_service_count,
      imap_login_process_min_avail: new_resource.imap_login_process_min_avail,
      imap_login_process_limit: new_resource.imap_login_process_limit,
      imap_login_vsz_limit: new_resource.imap_login_vsz_limit,
      pop3_login_service_count: new_resource.pop3_login_service_count
    )
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  template '/etc/dovecot/conf.d/10-logging.conf' do
    cookbook 'mx'
    source 'dovecot/10-logging.conf.erb'
    mode '0644'
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  template '/etc/dovecot/conf.d/15-mailboxes.conf' do
    cookbook 'mx'
    source 'dovecot/15-mailboxes.conf.erb'
    mode '0644'
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  template '/etc/dovecot/conf.d/20-imap.conf' do
    cookbook 'mx'
    source 'dovecot/20-imap.conf.erb'
    mode '0644'
    variables(
      mail_max_userip_connections: new_resource.imap_mail_max_userip_connections
    )
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  if new_resource.pop3
    template '/etc/dovecot/conf.d/20-pop3.conf' do
      cookbook 'mx'
      source 'dovecot/20-pop3.conf.erb'
      mode '0644'
      variables(
        pop3_lock_session: new_resource.pop3_lock_session,
        pop3_fast_size_lookups: new_resource.pop3_fast_size_lookups,
        pop3_no_flag_updates: new_resource.pop3_no_flag_updates
      )
      action :create
      notifies :restart, 'service[dovecot]', :delayed
    end
  end

  template '/etc/dovecot/conf.d/20-lmtp.conf' do
    cookbook 'mx'
    source 'dovecot/20-lmtp.conf.erb'
    mode '0644'
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  template '/etc/dovecot/conf.d/20-managesieve.conf' do
    cookbook 'mx'
    source 'dovecot/20-managesieve.conf.erb'
    mode '0644'
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  script_spam_global = ::File.join(new_resource.vmail_state['sieve_global_dir'], 'spam-global.sieve')

  cookbook_file script_spam_global do
    cookbook 'mx'
    source 'sieve/spam-global.sieve'
    owner new_resource.vmail_state['user']
    group new_resource.vmail_state['group']
    mode '0644'
    action :create
  end

  script_learn_spam = ::File.join(new_resource.vmail_state['sieve_global_dir'], 'learn-spam.sieve')

  cookbook_file script_learn_spam do
    cookbook 'mx'
    source 'sieve/learn-spam.sieve'
    owner new_resource.vmail_state['user']
    group new_resource.vmail_state['group']
    mode '0644'
    action :create
  end

  script_learn_ham = ::File.join(new_resource.vmail_state['sieve_global_dir'], 'learn-ham.sieve')

  cookbook_file script_learn_ham do
    cookbook 'mx'
    source 'sieve/learn-ham.sieve'
    owner new_resource.vmail_state['user']
    group new_resource.vmail_state['group']
    mode '0644'
    action :create
  end

  template '/etc/dovecot/conf.d/90-sieve.conf' do
    cookbook 'mx'
    source 'dovecot/90-sieve.conf.erb'
    mode '0644'
    variables(
      vmail_sieve_dir: new_resource.vmail_state['sieve_dir'],
      script_spam_global: script_spam_global,
      script_learn_spam: script_learn_spam,
      script_learn_ham: script_learn_ham
    )
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  script_quota_warning = ::File.join('/usr/local/bin', 'quota-warning')

  template script_quota_warning do
    cookbook 'mx'
    source 'dovecot/quota-warning.sh.erb'
    mode '0755'
    variables(
      dovecot_lda_bin: '/usr/lib/dovecot/dovecot-lda',
      postmaster: new_resource.postmaster
    )
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end

  template '/etc/dovecot/conf.d/90-quota.conf' do
    cookbook 'mx'
    source 'dovecot/90-quota.conf.erb'
    mode '0644'
    variables(
      vmail_user: new_resource.vmail_state['user'],
      vmail_group: new_resource.vmail_state['group'],
      script_quota_warning: script_quota_warning
    )
    action :create
    notifies :restart, 'service[dovecot]', :delayed
  end
end
