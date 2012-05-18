Facter.add(:ca_master) do
  confine :operatingsystem => %w{Debian}
  setcode do
    command = 'crm resource status'
    output = Facter::Util::Resolution.exec(command)
    if output
      master = output.scan(/\s+Master\/Slave.*\n\W.+Masters:\W\[\W([a-z,A-Z,0-9,\.-].*)\]/).to_s.chop
      master
    end
  end
end
