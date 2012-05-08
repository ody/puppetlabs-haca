Facter.add(:ca_master) do
  confine :operatingsystem => %w{Debian}
  setcode do
    command = 'crm resource status'
    output = Facter::Util::Resolution.exec(command)
    if output
      master = output.scan(/Master\/Slave.*ms_kicker\n\W.+Masters:\W\[\W([a-z,A-Z,0-9,\.-].*).\]/).to_s
      master
    end
  end
end
