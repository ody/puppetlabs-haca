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
    primitive_class => 'lsb',
    primitive_type  => 'apache2',
    provided_by     => 'heartbeat',
    operations      => { 'monitor' => { 'interval' => '10s' } },
    require         => Cs_primitive['ca_vip'],
  }

  # This is mostly a dummy primitive that kicks puppet for us.
  cs_primitive { 'kicker':
    primitive_class => 'ocf',
    primitive_type  => 'ppk',
    provided_by     => 'pacemaker',
    operations      => { 'monitor' => { 'interval' => '30s' } },
    metadata        => {
      'target-role'         => 'Master',
      'resource-stickiness' => '100'
    },
    promotable      => true,
    require         => Cs_primitive['ca_service'],
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
  cs_colocation { 'ms_kicker_with_ca_service':
    primitives => [ 'ms_kicker', 'ca_service' ],
    require     => Cs_primitive[[ 'ca_service', 'kicker' ]],
  }
  cs_order { 'ca_service_then_ms_kicker':
    first   => 'ca_service',
    second  => 'ms_kicker',
    require => Cs_colocation['ms_kicker_with_ca_service'],
  }

  Cs_primitive['ca_vip'] -> Class['rsync::server']

  # Set up our rsync module for obtaining the certifate athority data.
  include rsync
  class { 'rsync::server': address => '127.0.0.1' }
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
    notify         => Service['rsync'],
  }
}
