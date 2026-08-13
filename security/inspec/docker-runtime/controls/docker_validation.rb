container_id = input('container_id')

control 'docker-hardening-validation' do
  impact 1.0

  title 'Ensure validation container is configured with restricted privileges'

  desc 'Validates container hardening including read-only root filesystem, resource limits, dropped capabilities, no-new-privileges, seccomp, and restricted temporary storage.'

  describe docker_container(container_id) do

    # Container must exist
    it { should exist }

    # Root filesystem must be read-only
    its('HostConfig.ReadonlyRootfs') { should eq true }

    # Maximum memory: 512 MB
    its('HostConfig.Memory') do
      should cmp <= 536870912
    end

    # Swap must not exceed the configured memory limit
    its('HostConfig.MemorySwap') do
      should cmp <= 536870912
    end

    # Maximum number of processes
    its('HostConfig.PidsLimit') do
      should cmp <= 256
    end

    # Maximum CPU: 1 CPU
    its('HostConfig.NanoCpus') do
      should cmp <= 1000000000
    end

    # All Linux capabilities must be dropped
    its('HostConfig.CapDrop') do
      should include 'ALL'
    end

    # Prevent privilege escalation
    its('HostConfig.SecurityOpt') do
      should include 'no-new-privileges=true'
    end

    # Use Docker's default seccomp profile
    its('HostConfig.SecurityOpt') do
      should include 'seccomp=builtin'
    end
  end
end