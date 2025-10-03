###
# Packer Plugins
###

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.3"
    }
  }
}

# Guidance on naming and organizing variables
#
# Variable names are prefixed by builder, or by amigen project. Any variables
# used by many builders are prefixed with the keyword `spel`. Variables are grouped
# by their prefix. Current prefixes
# include:
#   * aws - amazon-ebs builder
#   * azure - azure-arm builder
#   * openstack - openstack builder
#   * virtualbox - virtualbox builder
#   * amigen - used across amigen versions ( amigen8 and amigen9)
#   * amigen8 - amigen8 only
#   * amigen9 - amigen9 only
#   * spel - everything else
#
# For variables passed to a builder argument, just apply prefix to the argument
# name. Do not "reinterpret" the argument and create a new name. E.g. for the
# argument `instance_type`, the variable name should be `aws_instance_type`.
#
# For variables used by amigen, consider what the variable is actually being applied
# to within the amigen project, and provide a descriptive name. Avoid abbreviations!
#
# Within each prefix, all variables should be sort alphabetically by name.

###
# Variables for AWS builders
###

variable "aws_ami_groups" {
  description = "List of groups that have access to launch the resulting AMIs. Keyword `all` will make the AMIs publicly accessible"
  type        = list(string)
  default     = []
}

variable "aws_ami_regions" {
  description = "List of regions to copy the AMIs to. Tags and attributes are copied along with the AMIs"
  type        = list(string)
  default     = []
}

variable "aws_ami_users" {
  description = "List of account IDs that have access to launch the resulting AMIs"
  type        = list(string)
  default     = []
}

variable "aws_instance_type" {
  description = "EC2 instance type to use while building the AMIs"
  type        = string
  default     = "t3.2xlarge"
}

variable "aws_force_deregister" {
  description = "Force deregister an existing AMI if one with the same name already exists"
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "Name of the AWS region in which to launch the EC2 instance to create the AMIs"
  type        = string
  default     = "us-east-1"
}

variable "aws_source_ami_filter_centos9stream_hvm" {
  description = "Object with source AMI filters for CentOS Stream 9 HVM builds"
  type = object({
    name   = string
    owners = list(string)
  })
  default = {
    name = "spel-minimal-centos-9stream-hvm-*.x86_64-gp*"
    owners = [
      "879381286673",
    ]
  }
}

variable "aws_source_ami_filter_ol8_hvm" {
  description = "Object with source AMI filters for Oracle Linux 8 HVM builds"
  type = object({
    name   = string
    owners = list(string)
  })
  default = {
    name = "spel-minimal-ol-8-hvm-*.x86_64-gp*"
    owners = [
      "879381286673",
    ]
  }
}

variable "aws_source_ami_filter_ol9_hvm" {
  description = "Object with source AMI filters for Oracle Linux 9 HVM builds"
  type = object({
    name   = string
    owners = list(string)
  })
  default = {
    name = "spel-minimal-ol-9-hvm-*.x86_64-gp*"
    owners = [
      "879381286673",
    ]
  }
}

variable "aws_source_ami_filter_rhel8_hvm" {
  description = "Object with source AMI filters for RHEL 8 HVM builds"
  type = object({
    name   = string
    owners = list(string)
  })
  default = {
    name = "spel-minimal-rhel-8-hvm-*.x86_64-gp*"
    owners = [
      "879381286673",
    ]
  }
}

variable "aws_source_ami_filter_rhel9_hvm" {
  description = "Object with source AMI filters for RHEL 9 HVM builds"
  type = object({
    name   = string
    owners = list(string)
  })
  default = {
    name = "spel-minimal-rhel-9-hvm-*.x86_64-gp*"
    owners = [
      "879381286673",
    ]
  }
}

variable "aws_ssh_interface" {
  description = "Specifies method used to select the value for the host in the SSH connection"
  type        = string
  default     = "public_dns"

  validation {
    condition     = contains(["public_ip", "private_ip", "public_dns", "private_dns", "session_manager"], var.aws_ssh_interface)
    error_message = "Variable `aws_ssh_interface` must be one of: public_ip, private_ip, public_dns, private_dns, or session_manager."
  }
}

variable "aws_subnet_id" {
  description = "ID of the subnet where Packer will launch the EC2 instance. Required if using an non-default VPC"
  type        = string
  default     = null
}

variable "aws_temporary_security_group_source_cidrs" {
  description = "List of IPv4 CIDR blocks to be authorized access to the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

###
# Variables used by all AMIGEN platforms
###

variable "amigen_amiutils_source_url" {
  description = "URL of the AMI Utils repo to be cloned using git, containing AWS utility rpms that will be installed to the AMIs"
  type        = string
  default     = ""
}

variable "amigen_aws_cfnbootstrap" {
  description = "URL of the tar.gz bundle containing the CFN bootstrap utilities"
  type        = string
  default     = "https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz"
}

variable "amigen_aws_cliv1_source" {
  description = "URL of the .zip bundle containing the installer for AWS CLI v1"
  type        = string
  default     = ""
}

variable "amigen_aws_cliv2_source" {
  description = "URL of the .zip bundle containing the installer for AWS CLI v2"
  type        = string
  default     = "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
}

variable "amigen_fips_disable" {
  description = "Toggles whether FIPS will be disabled in the images"
  type        = bool
  default     = false
}

variable "amigen_grub_timeout" {
  description = "Timeout value to set in the grub config of each image"
  type        = number
  default     = 1
}

variable "amigen_use_default_repos" {
  description = "Modifies the behavior of `amigen_repo_names`. When true, `amigen_repo_names` are appended to the enabled repos. When false, `amigen_repo_names` are used exclusively"
  type        = bool
  default     = true
}

###
# Variables used by amigen8
###

variable "amigen8_bootdev_mult" {
  description = "Factor by which to increase /boot's size on \"special\" distros (like OL8)"
  type        = string
  default     = "1.2"
}

variable "amigen8_bootdev_size" {
  description = "Size, in MiB, to make the /boot partition (this will be multiplied by the 'amigen8_bootdev_mult' value for Oracle Linux images)"
  type        = string
  default     = "1024"
}

variable "amigen8_extra_rpms" {
  description = "List of package specs (rpm names or URLs to .rpm files) to install to the EL8 builders and images"
  type        = list(string)
  default = [
    "python39",
    "python39-pip",
    "python39-setuptools",
    "crypto-policies-scripts",
    "spel-release",
    "spel-dod-certs",
    "spel-wcf-certs",
    "amazon-ec2-net-utils",
    "ec2-hibinit-agent",
    "ec2-instance-connect",
    "ec2-instance-connect-selinux",
    "ec2-utils",
    "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm",
  ]
}

variable "amigen8_filesystem_label" {
  description = "Label for the root filesystem when creating bare partitions for EL8 images"
  type        = string
  default     = ""
}

variable "amigen8_package_groups" {
  description = "List of yum repo groups to install into EL8 images"
  type        = list(string)
  default     = ["core"]
}

variable "amigen8_package_manifest" {
  description = "File containing a list of RPMs to use as the build manifest for EL8 images"
  type        = string
  default     = ""
}

variable "amigen8_repo_names" {
  description = "List of yum repo names to enable in the EL8 builders and EL8 images"
  type        = list(string)
  default     = ["spel"]
}

variable "amigen8_repo_sources" {
  description = "List of yum package refs (names or urls to .rpm files) that install yum repo definitions in EL8 builders and images"
  type        = list(string)
  default = [
    "https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm",
    "https://spel-packages.cloudarmor.io/spel-packages/repo/spel-release-latest-8.noarch.rpm",
  ]
}

variable "amigen8_source_branch" {
  description = "Branch that will be checked out when cloning amigen8"
  type        = string
  default     = "master"
}

variable "amigen8_source_url" {
  description = "URL that will be used to clone amigen8"
  type        = string
  default     = "https://github.com/MetroStar/amigen8.git"
}

variable "amigen8_storage_layout" {
  description = "List of colon-separated tuples (mount:name:size) that describe the desired partitions for LVM-partitioned disks on EL8 images"
  type        = list(string)
  default = [
    "/:rootVol:6",
    "swap:swapVol:2",
    "/home:homeVol:1",
    "/var:varVol:2",
    "/var/tmp:varTmpVol:2",
    "/var/log:logVol:2",
    "/var/log/audit:auditVol:100%FREE",
  ]
}

###
# Variables used by amigen9
###
variable "amigen9_boot_dev_size" {
  description = "Size of the partition hosting the '/boot' partition"
  type        = number
  default     = 768
}

variable "amigen9_boot_dev_size_mult" {
  description = "Factor by which to increase /boot's size on \"special\" distros (like OL9)"
  type        = number
  default     = "1.1"
}

variable "amigen9_boot_dev_label" {
  description = "Filesystem-label to apply to the '/boot' partition"
  type        = string
  default     = "boot_disk"
}

variable "amigen9_extra_rpms" {
  description = "List of package specs (rpm names or URLs to .rpm files) to install to the EL9 builders and images"
  type        = list(string)
  default = [
    "crypto-policies-scripts",
    "spel-release",
    "spel-dod-certs",
    "spel-wcf-certs",
    "amazon-ec2-net-utils",
    "ec2-hibinit-agent",
    "ec2-utils",
    "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm",
  ]
}

variable "amigen9_filesystem_label" {
  description = "Label for the root filesystem when creating bare partitions for EL9 images"
  type        = string
  default     = ""
}

variable "amigen9_package_groups" {
  description = "List of yum repo groups to install into EL9 images"
  type        = list(string)
  default     = ["core"]
}

variable "amigen9_package_manifest" {
  description = "File containing a list of RPMs to use as the build manifest for EL9 images"
  type        = string
  default     = ""
}

variable "amigen9_repo_names" {
  description = "List of yum repo names to enable in the EL9 builders and EL9 images"
  type        = list(string)
  default = [
    "epel",
    "spel",
  ]
}

variable "amigen9_repo_sources" {
  description = "List of yum package refs (names or urls to .rpm files) that install yum repo definitions in EL9 builders and images"
  type        = list(string)
  default = [
    "https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm",
    "https://spel-packages.cloudarmor.io/spel-packages/repo/spel-release-latest-9.noarch.rpm",
  ]
}

variable "amigen9_source_branch" {
  description = "Branch that will be checked out when cloning amigen9"
  type        = string
  default     = "main"
}

variable "amigen9_source_url" {
  description = "URL that will be used to clone amigen9"
  type        = string
  default     = "https://github.com/MetroStar/amigen9.git"
}

variable "amigen9_storage_layout" {
  description = "List of colon-separated tuples (mount:name:size) that describe the desired partitions for LVM-partitioned disks on EL9 images"
  type        = list(string)
  default = [
    "/:rootVol:6",
    "swap:swapVol:2",
    "/home:homeVol:1",
    "/var:varVol:2",
    "/var/tmp:varTmpVol:2",
    "/var/log:logVol:2",
    "/var/log/audit:auditVol:100%FREE",
  ]
}

variable "amigen9_uefi_dev_size" {
  description = "Size of the partition hosting the '/boot/efi' partition"
  type        = number
  default     = 128
}

variable "amigen9_uefi_dev_label" {
  description = "Filesystem-label to apply to the '/boot/efi' partition"
  type        = string
  default     = "UEFI_DISK"
}



###
# Variables specific to spel
###

variable "spel_deprecation_lifetime" {
  description = "Duration after which image will be marked deprecated. If null, image will not be marked deprecated. The accepted units are: ns, us (or µs), ms, s, m, and h. For example, one day is 24h, and one year is 8760h."
  type        = string
  default     = null
}

variable "spel_description_url" {
  description = "URL included in the AMI description"
  type        = string
  default     = "https://github.com/MetroStar/spel"
}

variable "spel_http_proxy" {
  description = "Used as the value for the git config http.proxy setting in the builder nodes"
  type        = string
  default     = ""
}

variable "spel_identifier" {
  description = "Namespace that prefixes the name of the built images"
  type        = string
}

variable "spel_root_volume_size" {
  description = "Size in GB of the root volume"
  type        = number
  default     = 20
}

variable "spel_version" {
  description = "Version appended to the name of the built images"
  type        = string
}

###
# End of variables blocks
###
# Start of source blocks
###

source "amazon-ebs" "base" {
  ami_groups                  = var.aws_ami_groups
  ami_name                    = "${var.spel_identifier}-${source.name}-${var.spel_version}.x86_64-gp3"
  ami_regions                 = var.aws_ami_regions
  ami_users                   = var.aws_ami_users
  ami_virtualization_type     = "hvm"
  associate_public_ip_address = true
  communicator                = "ssh"
  deprecate_at                = local.aws_ami_deprecate_at
  ena_support                 = true
  force_deregister            = var.aws_force_deregister
  instance_type               = var.aws_instance_type
  max_retries                 = 20
  region                      = var.aws_region
  sriov_support               = true
  ssh_interface               = var.aws_ssh_interface
  ssh_port                    = 22
  ssh_pty                     = true
  ssh_username                = "maintuser"
  ssh_timeout                 = "10m"
  ssh_key_exchange_algorithms = [
    "ecdh-sha2-nistp521",
    "ecdh-sha2-nistp256",
    "ecdh-sha2-nistp384",
    "ecdh-sha2-nistp521",
    "diffie-hellman-group14-sha1",
    "diffie-hellman-group1-sha1"
  ]
  subnet_id                             = var.aws_subnet_id
  tags                                  = { Name = "" } # Empty name tag avoids inheriting "Packer Builder"
  temporary_security_group_source_cidrs = var.aws_temporary_security_group_source_cidrs
}

###
# End of source blocks
###
# Start of locals block
###

locals {
  # Join lists to create strings appropriate for environment variables and amigen
  # expectations. amigen expects some vars to be comma-delimited, and others to
  # be space-delimited.
  amigen8_extra_rpms     = join(",", var.amigen8_extra_rpms)
  amigen8_package_groups = join(" ", var.amigen8_package_groups) # space-delimited
  amigen8_repo_names     = join(",", var.amigen8_repo_names)
  amigen8_repo_sources   = join(",", var.amigen8_repo_sources)
  amigen8_storage_layout = join(",", var.amigen8_storage_layout)
  amigen9_extra_rpms     = join(",", var.amigen9_extra_rpms)
  amigen9_package_groups = join(" ", var.amigen9_package_groups) # space-delimited
  amigen9_repo_names     = join(",", var.amigen9_repo_names)
  amigen9_repo_sources   = join(",", var.amigen9_repo_sources)
  amigen9_storage_layout = join(",", var.amigen9_storage_layout)

  # Template the description string
  description = "STIG-partitioned [*HARDENED*], LVM-enabled, \"minimal\" %s, with updates through ${formatdate("YYYY-MM-DD", local.timestamp)}. Default username `maintuser`. See ${var.spel_description_url}."

  # Calculate AWS AMI deprecate_at timestamp
  aws_ami_deprecate_at = var.spel_deprecation_lifetime != null ? timeadd(local.timestamp, var.spel_deprecation_lifetime) : null

  timestamp = timestamp()
}

###
# End of locals block
###
# Start of build blocks
###

# amigen builds
build {
  source "amazon-ebs.base" {
    ami_description = format(local.description, "CentOS Stream 9 AMI")
    name            = "hardened-centos-9stream-hvm"
    source_ami_filter {
      filters = {
        virtualization-type = "hvm"
        name                = var.aws_source_ami_filter_centos9stream_hvm.name
        root-device-type    = "ebs"
      }
      owners      = var.aws_source_ami_filter_centos9stream_hvm.owners
      most_recent = true
    }
  }

  source "amazon-ebs.base" {
    ami_description = format(local.description, "Oracle Linux 8 AMI")
    name            = "hardened-ol-8-hvm"
    source_ami_filter {
      filters = {
        virtualization-type = "hvm"
        name                = var.aws_source_ami_filter_ol8_hvm.name
        root-device-type    = "ebs"
      }
      owners      = var.aws_source_ami_filter_ol8_hvm.owners
      most_recent = true
    }
  }

  source "amazon-ebs.base" {
    ami_description = format(local.description, "Oracle Linux 9 AMI")
    name            = "hardened-ol-9-hvm"
    source_ami_filter {
      filters = {
        virtualization-type = "hvm"
        name                = var.aws_source_ami_filter_ol9_hvm.name
        root-device-type    = "ebs"
      }
      owners      = var.aws_source_ami_filter_ol9_hvm.owners
      most_recent = true
    }
  }

  source "amazon-ebs.base" {
    ami_description = format(local.description, "RHEL 8 AMI")
    name            = "hardened-rhel-8-hvm"
    source_ami_filter {
      filters = {
        virtualization-type = "hvm"
        name                = var.aws_source_ami_filter_rhel8_hvm.name
        root-device-type    = "ebs"
      }
      owners      = var.aws_source_ami_filter_rhel8_hvm.owners
      most_recent = true
    }
  }

  source "amazon-ebs.base" {
    ami_description = format(local.description, "RHEL 9 AMI")
    name            = "hardened-rhel-9-hvm"
    source_ami_filter {
      filters = {
        virtualization-type = "hvm"
        name                = var.aws_source_ami_filter_rhel9_hvm.name
        root-device-type    = "ebs"
      }
      owners      = var.aws_source_ami_filter_rhel9_hvm.owners
      most_recent = true
    }
  }

  provisioner "shell" {
    pause_before        = "45s"
    start_retry_timeout = "5m"
    only = [
      "amazon-ebs.hardened-rhel-9-hvm",
      "amazon-ebs.hardened-centos-9stream-hvm",
    ]
    execute_command = "sudo -E bash '{{.Path}}'"
    inline = [
      "echo 'Running Ansible Lockdown'",
      "python3 -m pip install ansible",
      "export PATH=/usr/local/bin:$PATH",
      "yum install -y git",
      "ansible-galaxy install git+https://github.com/ansible-lockdown/RHEL9-STIG.git",
      "ansible-playbook -i localhost, -c local $HOME/.ansible/roles/RHEL9-STIG/site.yml -e '{\"system_is_ec2\": true, \"setup_audit\": true, \"run_audit\": true, \"fetch_audit_output\": true}'",
      "rm -rf /var/lib/cloud/seed/nocloud-net",
      "rm -rf /var/lib/cloud/sem",
      "rm -rf /var/lib/cloud/data",
      "rm -rf /var/lib/cloud/instance",
      "cloud-init clean --logs",
    ]
  }

  provisioner "shell" {
    pause_before        = "45s"
    start_retry_timeout = "5m"
    only = [
      "amazon-ebs.hardened-ol-9-hvm",
    ]
    execute_command = "sudo -E bash '{{.Path}}'"
    inline = [
      "echo 'Running Ansible Lockdown'",
      "python3 -m pip install ansible",
      "export PATH=/usr/local/bin:$PATH",
      "yum install -y git",
      "ansible-galaxy install git+https://github.com/ansible-lockdown/RHEL9-STIG.git",
      "ansible-playbook -i localhost, -c local $HOME/.ansible/roles/RHEL9-STIG/site.yml -e '{\"system_is_ec2\": true, \"setup_audit\": true, \"run_audit\": true, \"fetch_audit_output\": true, \"rhel_09_214010\": false}'",
      "rm -rf /var/lib/cloud/seed/nocloud-net",
      "rm -rf /var/lib/cloud/sem",
      "rm -rf /var/lib/cloud/data",
      "rm -rf /var/lib/cloud/instance",
      "cloud-init clean --logs",
    ]
  }

  provisioner "shell" {
    pause_before        = "45s"
    start_retry_timeout = "5m"
    only = [
      "amazon-ebs.hardened-rhel-8-hvm",
    ]
    execute_command = "sudo -E bash '{{.Path}}'"
    inline = [
      "echo 'Running Ansible Lockdown'",
      "python3 -m pip install ansible",
      "export PATH=/usr/local/bin:$PATH",
      "yum install -y git",
      "ansible-galaxy install git+https://github.com/ansible-lockdown/RHEL8-STIG.git",
      "ansible-playbook -i localhost, -c local $HOME/.ansible/roles/RHEL8-STIG/site.yml -e '{\"system_is_ec2\": true, \"rhel8stig_copy_existing_zone\": false, \"setup_audit\": true, \"run_audit\": true, \"fetch_audit_output\": true, \"rhel_08_040136\":false}'",
      "BOOT_UUID=$(findmnt --noheadings --output UUID /boot)",
      "grubby --update-kernel=ALL --remove-args=\"boot\" --args=\"boot=UUID=$BOOT_UUID\"",
      "sed -E -i.bak -e 's@(^[[:space:]]*GRUB_CMDLINE_LINUX=\"[^\"]*)[[:space:]]*boot=[^\" ]*([^\"]*\")@\1 boot=UUID='\"$BOOT_UUID\"'\2@' -e 't' -e 's@(^[[:space:]]*GRUB_CMDLINE_LINUX=\"[^\"]*)\"$@\1 boot=UUID='\"$BOOT_UUID\"'\"@' /etc/default/grub",
      "grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg",
      "rm -rf /var/lib/cloud/seed/nocloud-net",
      "rm -rf /var/lib/cloud/sem",
      "rm -rf /var/lib/cloud/data",
      "rm -rf /var/lib/cloud/instance",
      "cloud-init clean --logs",
    ]
  }

  provisioner "shell" {
    pause_before        = "45s"
    start_retry_timeout = "5m"
    only = [
      "amazon-ebs.hardened-ol-8-hvm",
    ]
    execute_command = "sudo -E bash '{{.Path}}'"
    inline = [
      "echo 'Running Ansible Lockdown'",
      "python3 -m pip install ansible",
      "export PATH=/usr/local/bin:$PATH",
      "yum install -y git",
      "ansible-galaxy install git+https://github.com/ansible-lockdown/RHEL8-STIG.git",
      "ansible-playbook -i localhost, -c local $HOME/.ansible/roles/RHEL8-STIG/site.yml -e '{\"ansible_python_interpreter\": \"/usr/libexec/platform-python\", \"system_is_ec2\": true, \"rhel8stig_copy_existing_zone\": false, \"setup_audit\": true, \"run_audit\": true, \"fetch_audit_output\": true, \"rhel_08_040136\":false}'",
      "BOOT_UUID=$(findmnt --noheadings --output UUID /boot)",
      "grubby --update-kernel=ALL --remove-args=\"boot\" --args=\"boot=UUID=$BOOT_UUID\"",
      "sed -E -i.bak -e 's@(^[[:space:]]*GRUB_CMDLINE_LINUX=\"[^\"]*)[[:space:]]*boot=[^\" ]*([^\"]*\")@\1 boot=UUID='\"$BOOT_UUID\"'\2@' -e 't' -e 's@(^[[:space:]]*GRUB_CMDLINE_LINUX=\"[^\"]*)\"$@\1 boot=UUID='\"$BOOT_UUID\"'\"@' /etc/default/grub",
      "grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg",
      "rm -rf /var/lib/cloud/seed/nocloud-net",
      "rm -rf /var/lib/cloud/sem",
      "rm -rf /var/lib/cloud/data",
      "rm -rf /var/lib/cloud/instance",
      "cloud-init clean --logs",
    ]
  }
}
