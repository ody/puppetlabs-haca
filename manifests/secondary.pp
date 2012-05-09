# == Class: haca::secondary
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
class haca::secondary {

  # Setup stunnel for authentication and encryption of our sensitive certificate
  # authority data.
  include stunnel
  Stunnel::Tun {
    require => Package[$stunnel::data::package],
    notify  => Service[$stunnel::data::service],
  }
  stunnel::tun { 'rsync':
    certificate => "/var/lib/puppet/ssl/certs/${::clientcert}.pem",
    private_key => "/var/lib/puppet/ssl/private_keys/${::clientcert}.pem",
    ca_file     => '/var/lib/puppet/ssl/certs/ca.pem',
    crl_file    => '/var/lib/puppet/ssl/crl.pem',
    chroot      => '/var/lib/stunnel4/rsync',
    user        => 'puppet',
    group       => 'puppet',
    client      => true,
    accept      => '873',
    connect     => "${pe_master}:1873",
  }

  package { 'rsync': ensure => present }

  cron { 'pull_ca':
    command => 'rsync -avzPH rsync://localhost/ca /var/lib/puppet/ssl',
    minute  => '*',
  }
}
