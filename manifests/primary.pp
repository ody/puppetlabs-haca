# == Class: haca::primary
#
# Full description of class haca here.
#
# === Parameters
#
# Document parameters here.
#
# [*sample_parameter*]
#   Explanation of what this parameter affects and what it defaults to.
#   e.g. "Specify one or more upstream ntp servers as an array."
#
# === Variables
#
# Here you should define a list of variables that this module would require.
#
# [*sample_variable*]
#   Explanation of how this variable affects the funtion of this class and if it
#   has a default. e.g. "The parameter enc_ntp_servers must be set by the
#   External Node Classifier as a comma separated list of hostnames." (Note,
#   global variables should not be used in preference to class parameters  as of
#   Puppet 2.6.)
#
# === Examples
#
#  class { haca:
#    servers => [ 'pool.ntp.org', 'ntp.local.company.com' ]
#  }
#
# === Authors
#
# Author Name <author@domain.com>
#
# === Copyright
#
# Copyright 2011 Your name here, unless otherwise noted.
#
class haca::primary {

  # Setup stunnel for authentication and encryption of our sensitive certificate
  # authority data.
  include stunnel
  Stunnel::Tun {
    require => Package[$stunnel::data::package],
    notify  => Service[$stunnel::data::service],
  }
  stunnel::tun { 'rsyncd':
    certificate => "/var/lib/puppet/ssl/certs/${::clientcert}.pem",
    private_key => "/var/lib/puppet/ssl/private_keys/${::clientcert}.pem",
    ca_file     => '/var/lib/puppet/ssl/certs/ca.pem',
    crl_file    => '/var/lib/puppet/ssl/crl.pem',
    chroot      => '/var/lib/stunnel4/rsyncd',
    user        => 'puppet',
    group       => 'puppet',
    client      => false,
    accept      => '1873',
    connect     => '873',
    subscribe   => Rsync::Server::Module['ca'],
  }

  cs_property { 'stonith-enabled':
    value   => 'false',
    require => Class['corosync'],
  }

  cs_property { 'no-quorum-policy':
    value   => 'ignore',
    require => Class['corosync'],
  }

  Cs_primitive { metadata => { 'resource-stickiness' => '100' } }

  cs_primitive { 'ca_vip':
    primitive_class => 'ocf',
    primitive_type  => 'IPaddr2',
    provided_by     => 'heartbeat',
    parameters      => { 'ip' => '172.16.210.100', 'cidr_netmask' => '32' },
    operations      => { 'monitor' => { 'interval' => '30s' } },
    require         => Cs_property[[ 'no-quorum-policy', 'stonith-enabled' ]],
  }
  # I really really wished we used symlinks a la debian in PE so a could more
  # easily select what I wanted to run on a specific machine.
  cs_primitive { 'ca_service':
    primitive_class => 'ocf',
    primitive_type  => 'apache',
    provided_by     => 'heartbeat',
    operations      => {
      'monitor' => { 'interval' => '10s', 'timeout' => '30s' },
      'start'   => { 'interval' => '0', 'timeout' => '30s', 'on-fail' => 'restart' }
    },
    parameters      => { 'configfile' => '/etc/apache2/apache2.conf' },
    require         => Cs_primitive['ca_vip'],
  }

  # This is a dummy primititive that set some data for us.
  cs_primitive { 'ca_data':
    primitive_class => 'ocf',
    primitive_type  => 'ppdata',
    provided_by     => 'pacemaker',
    operations      => { 'monitor' => { 'interval' => '30s' } },
    metadata        => {
      'target-role'         => 'Master',
      'resource-stickiness' => '100'
    },
    promotable      => true,
    require         => Cs_primitive['ca_service'],
  }

  # This is a dummy primitive that kicks puppet for us.
  cs_primitive { 'puppet_kicker':
    primitive_class => 'ocf',
    primitive_type  => 'ppk',
    provided_by     => 'pacemaker',
    operations      => { 'start' => { 'interval' => '0', 'timeout' => '600s' } },
    require         => Cs_primitive['ca_data'],
  }

  cs_colocation { 'ca_vip_with_ca_service':
    primitives => [ 'ca_vip', 'ca_service' ],
    require    => Cs_primitive[[ 'ca_service', 'ca_vip' ]],
  }
  cs_order { 'ca_vip_then_ca_service':
    first   => 'ca_vip',
    second  => 'ca_service',
    require => Cs_colocation['ca_vip_with_ca_service'],
  }
  cs_colocation { 'ms_ca_data_with_ca_service':
    primitives => [ 'ms_ca_data', 'ca_service' ],
    require     => Cs_primitive[[ 'ca_service', 'ca_data' ]],
  }
  cs_order { 'ca_service_then_ms_ca_data':
    first   => 'ca_service',
    second  => 'ms_ca_data',
    require => Cs_colocation['ms_ca_data_with_ca_service'],
  }
  cs_colocation { 'puppet_kicker_with_ms_ca_data':
    primitives => [ 'puppet_kicker', 'ms_ca_data' ],
    require     => Cs_primitive[[ 'ca_data', 'puppet_kicker' ]],
  }
  cs_order { 'ms_ca_data_then_puppet_kicker':
    first   => 'ms_ca_data',
    second  => 'puppet_kicker',
    require => Cs_colocation['puppet_kicker_with_ms_ca_data'],
  }

  Cs_primitive['ca_vip'] -> Class['rsync::server']

  # Set up our rsync module for obtaining the certifate athority data.
  include rsync
  class { 'rsync::server': address => '127.0.0.1', use_xinetd => false }
  rsync::server::module { 'ca':
    path           => '/var/lib/puppet/ssl/ca',
    read_only      => true,
    write_only     => false,
    list           => true,
    uid            => 'puppet',
    gid            => 'puppet',
    incoming_chmod => false,
    outgoing_chmod => false,
    lock_file      => '/var/run/rsyncd.lock',
  }

  cron { 'pull_ca':
    command => '/usr/bin/rsync -avzPH --delete rsync://localhost/ca /var/lib/puppet/ssl/ca',
    ensure  => absent,
  }
}
