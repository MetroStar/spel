###
# Packer Plugins
###

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.3"
    }
    ansible = {
      version = ">= 1.1.0"
      source = "github.com/hashicorp/ansible"
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

variable "aws_source_ami_filter_al2023_hvm" {
  description = "Object with source AMI filters for Amazon Linux 2023 HVM builds"
  type = object({
    name   = string
    owners = list(string)
  })
  default = {
    name = "spel-*minimal-amzn-2023-hvm-*.x86_64-gp*"
    owners = [
      "self",
    ]
  }
}

variable "aws_source_ami_filter_centos9stream_hvm" {
  description = "Object with source AMI filters for CentOS Stream 9 HVM builds"
  type = object({
    name   = string
    owners = list(string)
  })
  default = {
    name = "spel-*minimal-centos-9stream-hvm-*.x86_64-gp*"
    owners = [
      "self",
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
    name = "spel-*minimal-ol-8-hvm-*.x86_64-gp*"
    owners = [
      "self",
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
    name = "spel-*minimal-ol-9-hvm-*.x86_64-gp*"
    owners = [
      "self",
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
    name = "spel-*minimal-rhel-8-hvm-*.x86_64-gp*"
    owners = [
      "self",
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
    name = "spel-*minimal-rhel-9-hvm-*.x86_64-gp*"
    owners = [
      "self",
    ]
  }
}

variable "aws_source_ami_filter_windows2016_hvm" {
  description = "Object with source AMI filters for Windows Server 2016 HVM builds"
  type = object({
    name   = string
    owners = list(string)
  })
  default = {
    name = "Windows_Server-2016-English-Full-Base-*"
    owners = [
      "amazon",
    ]
  }
}

variable "aws_source_ami_filter_windows2019_hvm" {
  description = "Object with source AMI filters for Windows Server 2019 HVM builds"
  type = object({
    name   = string
    owners = list(string)
  })
  default = {
    name = "Windows_Server-2019-English-Full-Base-*"
    owners = [
      "amazon",
    ]
  }
}

variable "aws_source_ami_filter_windows2022_hvm" {
  description = "Object with source AMI filters for Windows Server 2022 HVM builds"
  type = object({
    name   = string
    owners = list(string)
  })
  default = {
    name = "Windows_Server-2022-English-Full-Base-*"
    owners = [
      "amazon",
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

variable "aws_vpc_id" {
  description = "ID of the VPC where Packer will launch the EC2 instance. Required for Offline deployments"
  type        = string
  default     = null
}

variable "aws_vpc_endpoint_ec2" {
  description = "VPC endpoint DNS name for EC2 service (Offline environments)"
  type        = string
  default     = null
}

variable "aws_vpc_endpoint_s3" {
  description = "VPC endpoint DNS name for S3 service (Offline environments)"
  type        = string
  default     = null
}

variable "aws_vpc_endpoint_ssm" {
  description = "VPC endpoint DNS name for SSM service (Offline environments)"
  type        = string
  default     = null
}

variable "aws_offline_ami_regions" {
  description = "List of regions to copy AMIs to in Offline environment. Overrides aws_ami_regions for Offline builds"
  type        = list(string)
  default     = null
}

variable "spel_cfnbootstrap_source" {
  description = "URL or file path for CloudFormation bootstrap utilities. Use file:// prefix for local offline packages."
  type        = string
  default     = "https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz"
}

variable "spel_awscli_source" {
  description = "URL or file path for AWS CLI v2 installer. Use file:// prefix for local offline packages."
  type        = string
  default     = "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
}

variable "spel_ssm_agent_source" {
  description = "URL or file path for SSM Agent installer. Use file:// prefix for local offline packages."
  type        = string
  default     = "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm"
}

variable "aws_offline_account_id" {
  description = "AWS account ID for Offline marketplace AMIs. When set, overrides default commercial account IDs in source AMI filters"
  type        = string
  default     = ""
}

variable "aws_temporary_security_group_source_cidrs" {
  description = "List of IPv4 CIDR blocks to be authorized access to the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "amigen_repo_mirror_baseurl" {
  description = "Base URL for air-gapped yum repository mirrors. When set, disables RHUI repos and configures local mirrors. Example: http://mirror.internal.mil"
  type        = string
  default     = ""
}

variable "aws_kms_key_id" {
  description = "ARN of the Customer Managed Key (CMK) to use for EBS volume encryption. When set, all EBS volumes will be encrypted using this key. Leave empty for no encryption or to use the default AWS-managed key"
  type        = string
  default     = ""
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
  description = "URL of the tar.gz bundle containing the CFN bootstrap utilities. Leave empty to use spel_cfnbootstrap_source for offline support."
  type        = string
  default     = ""
}

variable "amigen_aws_cliv1_source" {
  description = "URL of the .zip bundle containing the installer for AWS CLI v1. Leave empty to use spel_awscli_source for offline support."
  type        = string
  default     = ""
}

variable "amigen_aws_cliv2_source" {
  description = "URL of the .zip bundle containing the installer for AWS CLI v2. Leave empty to use spel_awscli_source for offline support."
  type        = string
  default     = ""
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
    "amazon-ec2-net-utils",
    "ec2-hibinit-agent",
    "ec2-instance-connect",
    "ec2-instance-connect-selinux",
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
  default     = []
}

variable "amigen8_repo_sources" {
  description = "List of yum package refs (names or urls to .rpm files) that install yum repo definitions in EL8 builders and images"
  type        = list(string)
  default = [
    "https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm",
  ]
}

variable "amigen8_source_branch" {
  description = "Branch that will be checked out when cloning amigen8"
  type        = string
  default     = "master"
}

variable "amigen8_source_url" {
  description = "URL or file:// path for amigen8. Use file:///tmp/offline-packages/amigen8 for offline builds."
  type        = string
  default     = "file:///tmp/offline-packages/amigen8"
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
    "amazon-ec2-net-utils",
    "ec2-hibinit-agent",
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
  default     = []
}

variable "amigen9_repo_sources" {
  description = "List of yum package refs (names or urls to .rpm files) that install yum repo definitions in EL9 builders and images"
  type        = list(string)
  default = [
    "https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm",
  ]
}

variable "amigen9_source_branch" {
  description = "Branch that will be checked out when cloning amigen9"
  type        = string
  default     = "main"
}

variable "amigen9_source_url" {
  description = "URL or file:// path for amigen9. Use file:///tmp/offline-packages/amigen9 for offline builds."
  type        = string
  default     = "file:///tmp/offline-packages/amigen9"
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
  ami_regions                 = local.effective_ami_regions
  ami_users                   = var.aws_ami_users
  ami_virtualization_type     = "hvm"
  associate_public_ip_address = true
  communicator                = "ssh"
  deprecate_at                = local.aws_ami_deprecate_at
  ena_support                 = true
  encrypt_boot                = var.aws_kms_key_id != "" ? true : null
  kms_key_id                  = var.aws_kms_key_id != "" ? var.aws_kms_key_id : null
  force_deregister            = var.aws_force_deregister
  instance_type               = var.aws_instance_type
  max_retries                 = 20
  region                      = var.aws_region
  sriov_support               = true
  ssh_interface               = var.aws_ssh_interface
  ssh_port                    = 22
  ssh_pty                     = true
  ssh_username                = "maintuser"
  ssh_timeout                 = "30m"
  ssh_handshake_attempts      = 100
  ssh_key_exchange_algorithms = [
    "ecdh-sha2-nistp521",
    "ecdh-sha2-nistp384",
    "ecdh-sha2-nistp256",
    "diffie-hellman-group-exchange-sha256",
    "diffie-hellman-group16-sha512",
    "diffie-hellman-group18-sha512",
    "diffie-hellman-group14-sha256"
  ]
  subnet_id                             = var.aws_subnet_id
  vpc_id                                = var.aws_vpc_id
  tags                                  = { Name = "" } # Empty name tag avoids inheriting "Packer Builder"
  temporary_security_group_source_cidrs = var.aws_temporary_security_group_source_cidrs
}

source "amazon-ebs" "windows-base" {
  ami_groups                  = var.aws_ami_groups
  ami_name                    = "${var.spel_identifier}-${source.name}-${var.spel_version}.x86_64-gp3"
  ami_regions                 = local.effective_ami_regions
  ami_users                   = var.aws_ami_users
  ami_virtualization_type     = "hvm"
  associate_public_ip_address = true
  communicator                = "winrm"
  deprecate_at                = local.aws_ami_deprecate_at
  ena_support                 = true
  encrypt_boot                = var.aws_kms_key_id != "" ? true : null
  kms_key_id                  = var.aws_kms_key_id != "" ? var.aws_kms_key_id : null
  force_deregister            = true
  instance_type               = var.aws_instance_type
  max_retries                 = 20
  region                      = var.aws_region
  sriov_support               = true
  subnet_id                   = var.aws_subnet_id
  vpc_id                      = var.aws_vpc_id
  tags                        = { Name = "" } # Empty name tag avoids inheriting "Packer Builder"
  temporary_security_group_source_cidrs = var.aws_temporary_security_group_source_cidrs
  user_data_file              = "${path.root}/userdata/winrm_bootstrap.txt"
  winrm_insecure              = true
  winrm_timeout               = "15m"
  winrm_use_ssl               = true
  winrm_use_ntlm              = true
  winrm_username              = "TempPackerUser"
  winrm_password              = "ComplexP@ssw0rd123!"

  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_type = "gp3"
    delete_on_termination = true
    encrypted   = var.aws_kms_key_id != "" ? true : null
    kms_key_id  = var.aws_kms_key_id != "" ? var.aws_kms_key_id : null
  }
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

  # Offline-specific overrides
  # Use Offline AMI regions if specified, otherwise use commercial regions
  effective_ami_regions = var.aws_offline_ami_regions != null ? var.aws_offline_ami_regions : var.aws_ami_regions
  
  # Use Offline account ID for source AMI owners if specified
  # This allows using Offline marketplace AMIs instead of commercial marketplace AMIs
  use_offline_ami_owners = var.aws_offline_account_id != ""
  
  # Effective source AMI filter owners - use Offline account if specified, otherwise use commercial
  effective_al2023_owners        = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_al2023_hvm.owners
  effective_centos9stream_owners = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_centos9stream_hvm.owners
  effective_ol8_owners           = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_ol8_hvm.owners
  effective_ol9_owners           = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_ol9_hvm.owners
  effective_rhel8_owners         = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_rhel8_hvm.owners
  effective_rhel9_owners         = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_rhel9_hvm.owners
  effective_windows2016_owners   = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_windows2016_hvm.owners
  effective_windows2019_owners   = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_windows2019_hvm.owners
  effective_windows2022_owners   = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_windows2022_hvm.owners

  # Template the description strings
  description = "STIG-partitioned [*HARDENED*], LVM-enabled, \"minimal\" %s, with updates through ${formatdate("YYYY-MM-DD", local.timestamp)}. Default username `maintuser`. See ${var.spel_description_url}."
  windows_description = "STIG-partitioned [*HARDENED*] %s, with updates through ${formatdate("YYYY-MM-DD", local.timestamp)}. Default username `maintuser`. See ${var.spel_description_url}."

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
    ami_description = format(local.description, "Amazon Linux 2023 AMI")
    name            = "hardened-amzn-2023-hvm"
    source_ami_filter {
      filters = {
        virtualization-type = "hvm"
        name                = var.aws_source_ami_filter_al2023_hvm.name
        root-device-type    = "ebs"
      }
      owners      = local.effective_al2023_owners
      most_recent = true
    }
  }

  source "amazon-ebs.base" {
    ami_description = format(local.description, "CentOS Stream 9 AMI")
    name            = "hardened-centos-9stream-hvm"
    source_ami_filter {
      filters = {
        virtualization-type = "hvm"
        name                = var.aws_source_ami_filter_centos9stream_hvm.name
        root-device-type    = "ebs"
      }
      owners      = local.effective_centos9stream_owners
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
      owners      = local.effective_ol8_owners
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
      owners      = local.effective_ol9_owners
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
      owners      = local.effective_rhel8_owners
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
      owners      = local.effective_rhel9_owners
      most_recent = true
    }
  }

  source "amazon-ebs.windows-base" {
    ami_description = format(local.windows_description, "Windows Server 2016 AMI")
    name            = "hardened-windows-2016-hvm"
    source_ami_filter {
      filters = {
        virtualization-type = "hvm"
        name                = var.aws_source_ami_filter_windows2016_hvm.name
        root-device-type    = "ebs"
      }
      owners      = local.effective_windows2016_owners
      most_recent = true
    }
  }

  source "amazon-ebs.windows-base" {
    ami_description = format(local.windows_description, "Windows Server 2019 AMI")
    name            = "hardened-windows-2019-hvm"
    source_ami_filter {
      filters = {
        virtualization-type = "hvm"
        name                = var.aws_source_ami_filter_windows2019_hvm.name
        root-device-type    = "ebs"
      }
      owners      = local.effective_windows2019_owners
      most_recent = true
    }
  }

  source "amazon-ebs.windows-base" {
    ami_description = format(local.windows_description, "Windows Server 2022 AMI")
    name            = "hardened-windows-2022-hvm"
    source_ami_filter {
      filters = {
        virtualization-type = "hvm"
        name                = var.aws_source_ami_filter_windows2022_hvm.name
        root-device-type    = "ebs"
      }
      owners      = local.effective_windows2022_owners
      most_recent = true
    }
  }

  # Remove sslverify=0 from repo files that was added during minimal build
  # This restores proper SSL verification for the hardened AMI
  provisioner "shell" {
    execute_command = "{{ .Vars }} sudo -E /bin/bash '{{ .Path }}'"
    inline = [
      "echo 'Removing sslverify=0 from yum repo files (restoring SSL verification)...'",
      "for REPOFILE in /etc/yum.repos.d/*.repo; do",
      "  if [[ -f \"$REPOFILE\" ]]; then",
      "    if grep -q 'sslverify=0' \"$REPOFILE\"; then",
      "      echo \"  Removing sslverify=0 from $REPOFILE\"",
      "      sed -i '/^sslverify=0$/d' \"$REPOFILE\"",
      "    fi",
      "  fi",
      "done",
      "echo 'SSL verification restored for all repo files'",
    ]
    only = [
      "amazon-ebs.hardened-rhel-9-hvm",
      "amazon-ebs.hardened-rhel-8-hvm",
      "amazon-ebs.hardened-centos-9stream-hvm",
      "amazon-ebs.hardened-ol-9-hvm",
      "amazon-ebs.hardened-ol-8-hvm",
      "amazon-ebs.hardened-amzn-2023-hvm",
    ]
  }

  # Configure air-gapped repositories for Linux builds (runs before STIG hardening)
  provisioner "shell" {
    environment_vars = [
      "REPO_MIRROR_BASEURL=${var.amigen_repo_mirror_baseurl}",
    ]
    execute_command = "{{ .Vars }} sudo -E /bin/bash '{{ .Path }}'"
    inline = [
      "if [ -n \"$REPO_MIRROR_BASEURL\" ]; then",
      "  echo 'Configuring air-gapped repositories...'",
      "  ",
      "  # Detect OS version (escape %% for Packer template)",
      "  OS_VERSION=$(rpm -E %%{rhel})",
      "  ",
      "  # Disable Red Hat RHUI repositories",
      "  if ls /etc/yum.repos.d/redhat-rhui*.repo 1>/dev/null 2>&1; then",
      "    echo 'Disabling RHUI repositories...'",
      "    for repo in /etc/yum.repos.d/redhat-rhui*.repo; do",
      "      mv \"$$repo\" \"$${repo}.disabled\"",
      "    done",
      "  fi",
      "  ",
      "  # Create local mirror repo config",
      "  cat << EOF > /etc/yum.repos.d/rhel-local.repo",
      "[rhel-$${OS_VERSION}-baseos]",
      "name=RHEL $${OS_VERSION} BaseOS (Local Mirror)",
      "baseurl=$${REPO_MIRROR_BASEURL}/rhel$${OS_VERSION}/baseos",
      "enabled=1",
      "gpgcheck=0",
      "",
      "[rhel-$${OS_VERSION}-appstream]",
      "name=RHEL $${OS_VERSION} AppStream (Local Mirror)",
      "baseurl=$${REPO_MIRROR_BASEURL}/rhel$${OS_VERSION}/appstream",
      "enabled=1",
      "gpgcheck=0",
      "EOF",
      "  ",
      "  yum clean all",
      "  yum repolist",
      "  echo 'Air-gapped repositories configured successfully'",
      "else",
      "  echo 'REPO_MIRROR_BASEURL not set, using default repositories'",
      "fi"
    ]
    only = [
      "amazon-ebs.hardened-rhel-9-hvm",
      "amazon-ebs.hardened-rhel-8-hvm",
      "amazon-ebs.hardened-centos-9stream-hvm",
      "amazon-ebs.hardened-ol-9-hvm",
      "amazon-ebs.hardened-ol-8-hvm",
    ]
  }

  provisioner "ansible" {
    pause_before  = "30s"
    timeout       = "30m"
    only          = [
      "amazon-ebs.hardened-amzn-2023-hvm",
      "amazon-ebs.hardened-rhel-9-hvm",
      "amazon-ebs.hardened-ol-9-hvm",
      "amazon-ebs.hardened-rhel-8-hvm",
      "amazon-ebs.hardened-ol-8-hvm",
      "amazon-ebs.hardened-centos-9stream-hvm"
    ]
    playbook_file = "${path.root}/ansible/ca-certs-playbook.yml"
    use_proxy     = false
  }

  provisioner "ansible" {
    pause_before  = "30s"
    timeout       = "30m"
    only          = [
      "amazon-ebs.hardened-windows-2016-hvm",
      "amazon-ebs.hardened-windows-2019-hvm",
      "amazon-ebs.hardened-windows-2022-hvm"
    ]
    playbook_file = "${path.root}/ansible/ca-certs-playbook.yml"
    use_proxy     = false
    user          = "TempPackerUser"
    extra_arguments = [
      "--connection", "winrm",
      "--extra-vars", "{'winrm_password': 'ComplexP@ssw0rd123!', 'ansible_winrm_server_cert_validation': 'ignore', 'ansible_port': 5986}"
    ]
  }

  # =============================================================================
  # WINDOWS FILE UPLOADS - MUST BE BEFORE STIG HARDENING
  # STIG breaks WinRM file copy operations (winrmcp needs new shell context)
  # Inline PowerShell provisioners work after STIG (reuse existing session)
  # =============================================================================
  provisioner "file" {
    only = [
      "amazon-ebs.hardened-windows-2016-hvm",
      "amazon-ebs.hardened-windows-2019-hvm",
      "amazon-ebs.hardened-windows-2022-hvm"
    ]
    source      = "${path.root}/scripts/cleanup-sysprep.ps1"
    destination = "C:/Windows/Temp/cleanup-sysprep.ps1"
  }

  provisioner "file" {
    only = [
      "amazon-ebs.hardened-windows-2016-hvm",
      "amazon-ebs.hardened-windows-2019-hvm",
      "amazon-ebs.hardened-windows-2022-hvm"
    ]
    source      = "${path.root}/scripts/SetupComplete.cmd"
    destination = "C:/Windows/Temp/SetupComplete.cmd"
  }

  provisioner "file" {
    only = [
      "amazon-ebs.hardened-windows-2016-hvm",
      "amazon-ebs.hardened-windows-2019-hvm"
    ]
    source      = "${path.root}/scripts/post-stig-2016-2019.ps1"
    destination = "C:/Windows/Temp/post-stig.ps1"
  }

  provisioner "file" {
    only = [
      "amazon-ebs.hardened-windows-2022-hvm"
    ]
    source      = "${path.root}/scripts/post-stig-2022.ps1"
    destination = "C:/Windows/Temp/post-stig.ps1"
  }

  provisioner "file" {
    only = [
      "amazon-ebs.hardened-amzn-2023-hvm",
      "amazon-ebs.hardened-rhel-9-hvm",
      "amazon-ebs.hardened-centos-9stream-hvm",
      "amazon-ebs.hardened-ol-9-hvm",
      "amazon-ebs.hardened-rhel-8-hvm",
      "amazon-ebs.hardened-ol-8-hvm",
    ]
    source      = "${path.root}/../tools/python-deps"
    destination = "/tmp/python-deps"
  }

  provisioner "file" {
    only = [
      "amazon-ebs.hardened-amzn-2023-hvm",
      "amazon-ebs.hardened-rhel-9-hvm",
      "amazon-ebs.hardened-centos-9stream-hvm",
      "amazon-ebs.hardened-ol-9-hvm",
      "amazon-ebs.hardened-rhel-8-hvm",
      "amazon-ebs.hardened-ol-8-hvm",
    ]
    source      = "${path.root}/ansible/collections"
    destination = "/tmp/ansible-collections"
  }

  # =============================================================================
  # Amazon Linux 2023 STIG Hardening
  # =============================================================================
  # Uses AWS STIG Script (officially maintained by AWS) as primary option.
  # Falls back to AL2023-STIG Ansible role (RHEL9-STIG fork) if AWS script
  # doesn't support AL2023.
  #
  # NOTE: OpenSCAP scan is SKIPPED for AL2023 because:
  # - DISA has not published an official STIG benchmark for Amazon Linux 2023
  # - ssg-al2023-ds.xml only contains CIS profiles, not STIG
  # - Once DISA publishes AL2023 STIG, add OpenSCAP scan using that benchmark
  # =============================================================================

  # Upload base64-encoded AWS STIG Script from Docker container
  # The tarball is baked into the Docker image and base64-encoded for reliable transfer
  provisioner "file" {
    only = [
      "amazon-ebs.hardened-amzn-2023-hvm",
    ]
    source      = "/opt/offline-packages/LinuxAWSConfigureSTIG.tgz.b64"
    destination = "/tmp/LinuxAWSConfigureSTIG.tgz.b64"
  }

  # Decode the base64-encoded AWS STIG Script
  provisioner "shell" {
    only = [
      "amazon-ebs.hardened-amzn-2023-hvm",
    ]
    execute_command = "sudo -E bash '{{.Path}}'"
    inline = [
      "echo 'Decoding AWS STIG Script...'",
      "base64 -d /tmp/LinuxAWSConfigureSTIG.tgz.b64 > /tmp/LinuxAWSConfigureSTIG.tgz",
      "rm /tmp/LinuxAWSConfigureSTIG.tgz.b64",
      "echo 'Decoded successfully. Size:' $(stat -c%s /tmp/LinuxAWSConfigureSTIG.tgz) 'bytes'",
    ]
  }

  provisioner "file" {
    only = [
      "amazon-ebs.hardened-amzn-2023-hvm",
    ]
    source      = "${path.root}/ansible/roles/AL2023-STIG"
    destination = "/tmp/AL2023-STIG"
  }

  provisioner "shell" {
    pause_before        = "45s"
    start_retry_timeout = "5m"
    only = [
      "amazon-ebs.hardened-amzn-2023-hvm",
    ]
    execute_command = "sudo -E bash '{{.Path}}'"
    inline = [
      "echo '=== Amazon Linux 2023 STIG Hardening ===' ",
      "echo 'Using AWS STIG Script (officially maintained by AWS)...'",
      "",
      "# AWS STIG Script (supports AL2023 via linux_stigs/functions/amzn/al2023_stig.sh)",
      "AWS_STIG_SUCCESS=false",
      "if [ -f '/tmp/LinuxAWSConfigureSTIG.tgz' ]; then",
      "  echo 'Verifying AWS STIG tarball integrity...'",
      "  TARBALL_SIZE=$(stat -c%s /tmp/LinuxAWSConfigureSTIG.tgz)",
      "  echo \"  Tarball size: $TARBALL_SIZE bytes\"",
      "  if [ \"$TARBALL_SIZE\" -lt 10000 ]; then",
      "    echo 'ERROR: AWS STIG tarball appears truncated or corrupted (too small)'",
      "    echo 'Please rebuild Docker image with fresh LinuxAWSConfigureSTIG.tgz'",
      "  elif ! gzip -t /tmp/LinuxAWSConfigureSTIG.tgz 2>/dev/null; then",
      "    echo 'ERROR: AWS STIG tarball failed gzip integrity check'",
      "    echo 'File contents (first 100 bytes as hex):'",
      "    xxd /tmp/LinuxAWSConfigureSTIG.tgz 2>/dev/null | head -6 || od -A x -t x1 /tmp/LinuxAWSConfigureSTIG.tgz | head -6",
      "  else",
      "    echo 'Extracting AWS STIG Script...'",
      "    cd /tmp && tar xzf LinuxAWSConfigureSTIG.tgz",
      "    if [ -d '/tmp/linux_stigs' ] && [ -f '/tmp/linux_stigs/main.sh' ]; then",
      "      echo 'AWS STIG Script found, running STIG hardening...'",
      "      chmod +x /tmp/linux_stigs/main.sh",
      "      # Run with: -d <workdir> -l <level> -h yes (install packages) -s yes (legal banner)",
      "      /tmp/linux_stigs/main.sh -d /tmp/linux_stigs/ -l High -h yes -s yes && AWS_STIG_SUCCESS=true",
      "    else",
      "      echo 'ERROR: AWS STIG Script not found in tarball'",
      "      ls -la /tmp/linux_stigs/ 2>/dev/null || echo 'linux_stigs directory not found'",
      "    fi",
      "  fi",
      "  rm -rf /tmp/linux_stigs /tmp/LinuxAWSConfigureSTIG.tgz",
      "fi",
      "",
      "# Fallback to AL2023-STIG Ansible role (RHEL9-STIG fork) if AWS script fails",
      "if [ \"$AWS_STIG_SUCCESS\" != 'true' ]; then",
      "  echo 'AWS STIG failed, falling back to AL2023-STIG Ansible role...'",
      "  echo 'Ensuring Python 3.9 is available...'",
      "  if ! command -v python3.9 &>/dev/null; then yum install -y python3.9 python3.9-pip; fi",
      "  python3.9 --version",
      "  echo 'Checking for offline Python wheels...'",
      "  if [ -d '/tmp/python-deps' ]; then echo '  /tmp/python-deps directory exists'; ls -lh /tmp/python-deps/ | head -5; else echo '  /tmp/python-deps directory NOT found'; fi",
      "  if [ -d '/tmp/python-deps' ] && [ \"$(ls -A /tmp/python-deps 2>/dev/null)\" ]; then echo 'Installing Ansible from offline wheels...'; python3.9 -m pip install --no-index --ignore-installed --no-warn-conflicts /tmp/python-deps/*.whl; else echo 'Installing Ansible from PyPI...'; python3.9 -m pip install ansible-core; fi",
      "  export PATH=/usr/local/bin:$PATH",
      "  echo 'Installing Ansible collections...'",
      "  if [ -d '/tmp/ansible-collections' ]; then for tarball in /tmp/ansible-collections/*.tar.gz; do [ -f \"$tarball\" ] && ansible-galaxy collection install \"$tarball\" --force; done; fi",
      "  mkdir -p $HOME/.ansible/roles",
      "  cp -r /tmp/AL2023-STIG $HOME/.ansible/roles/",
      "  ansible-playbook -i localhost, -c local $HOME/.ansible/roles/AL2023-STIG/site.yml -e '{\"system_is_ec2\": true, \"rhel_09_251010\": false, \"rhel_09_251015\": false, \"rhel_09_251020\": false, \"rhel_09_251025\": false, \"rhel_09_251030\": false, \"rhel_09_251035\": false, \"rhel_09_251040\": false, \"rhel_09_251045\": false}'",
      "fi",
      "",
      "# NOTE: OpenSCAP scan skipped - no official DISA STIG benchmark for AL2023",
      "# Once DISA publishes AL2023 STIG, add: oscap xccdf eval --profile stig ...",
      "echo 'STIG hardening complete. OpenSCAP scan skipped (no DISA AL2023 STIG benchmark).'",
      "",
      "rm -rf /var/lib/cloud/seed/nocloud-net",
      "rm -rf /var/lib/cloud/sem",
      "rm -rf /var/lib/cloud/data",
      "rm -rf /var/lib/cloud/instance",
      "cloud-init clean --logs",
    ]
  }

  provisioner "file" {
    only = [
      "amazon-ebs.hardened-rhel-9-hvm",
      "amazon-ebs.hardened-centos-9stream-hvm",
      "amazon-ebs.hardened-ol-9-hvm",
    ]
    source      = "${path.root}/ansible/roles/RHEL9-STIG"
    destination = "/tmp/RHEL9-STIG"
  }

  provisioner "shell" {
    pause_before        = "45s"
    start_retry_timeout = "5m"
    only = [
      "amazon-ebs.hardened-rhel-9-hvm",
      "amazon-ebs.hardened-centos-9stream-hvm",
      "amazon-ebs.hardened-ol-9-hvm",
    ]
    execute_command = "sudo -E bash '{{.Path}}'"
    inline = [
      "echo 'Running Ansible Lockdown'",
      "echo 'Ensuring Python 3.9 is available...'",
      "if ! command -v python3.9 &>/dev/null; then yum install -y python3.9 python3.9-pip; fi",
      "python3.9 --version",
      "echo 'Checking for offline Python wheels...'",
      "if [ -d '/tmp/python-deps' ]; then echo '  /tmp/python-deps directory exists'; ls -lh /tmp/python-deps/ | head -5; else echo '  /tmp/python-deps directory NOT found'; fi",
      "if [ -d '/tmp/python-deps' ] && [ \"$(ls -A /tmp/python-deps 2>/dev/null)\" ]; then echo 'Installing Ansible from offline wheels...'; python3.9 -m pip install --no-index /tmp/python-deps/*.whl; else echo 'Installing Ansible from PyPI...'; python3.9 -m pip install ansible-core; fi",
      "export PATH=/usr/local/bin:$PATH",
      "echo 'Installing Ansible collections...'",
      "if [ -d '/tmp/ansible-collections' ]; then for tarball in /tmp/ansible-collections/*.tar.gz; do [ -f \"$tarball\" ] && ansible-galaxy collection install \"$tarball\" --force; done; fi",
      "mkdir -p $HOME/.ansible/roles",
      "cp -r /tmp/RHEL9-STIG $HOME/.ansible/roles/",
      "ansible-playbook -i localhost, -c local $HOME/.ansible/roles/RHEL9-STIG/site.yml -e '{\"system_is_ec2\": true, \"rhel_09_251010\": false, \"rhel_09_251015\": false, \"rhel_09_251020\": false, \"rhel_09_251025\": false, \"rhel_09_251030\": false, \"rhel_09_251035\": false, \"rhel_09_251040\": false, \"rhel_09_251045\": false}'",
      "echo 'Installing OpenSCAP for compliance scanning...'",
      "yum install -y openscap-scanner scap-security-guide",
      "echo 'Running OpenSCAP STIG compliance scan...'",
      "SCAP_DS=/usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml",
      "if grep -qi 'oracle' /etc/os-release; then SCAP_DS=/usr/share/xml/scap/ssg/content/ssg-ol9-ds.xml; fi",
      "echo \"Using SCAP datastream: $SCAP_DS\"",
      "oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_stig --results /tmp/oscap-results.xml --report /tmp/oscap-report.html $SCAP_DS || true",
      "echo 'OpenSCAP scan complete. Report saved to /tmp/oscap-report.html'",
      "rm -rf /var/lib/cloud/seed/nocloud-net",
      "rm -rf /var/lib/cloud/sem",
      "rm -rf /var/lib/cloud/data",
      "rm -rf /var/lib/cloud/instance",
      "cloud-init clean --logs",
    ]
  }

  provisioner "file" {
    only = [
      "amazon-ebs.hardened-rhel-8-hvm",
      "amazon-ebs.hardened-ol-8-hvm",
    ]
    source      = "${path.root}/scripts/boot-fips-wrapper.sh"
    destination = "/tmp/boot-fips-wrapper.sh"
  }

  provisioner "file" {
    only = [
      "amazon-ebs.hardened-rhel-8-hvm",
      "amazon-ebs.hardened-ol-8-hvm",
    ]
    source      = "${path.root}/ansible/roles/RHEL8-STIG"
    destination = "/tmp/RHEL8-STIG"
  }

  provisioner "shell" {
    pause_before        = "45s"
    start_retry_timeout = "5m"
    only = [
      "amazon-ebs.hardened-rhel-8-hvm",
    ]
    execute_command = "sudo -E bash '{{.Path}}'"
    inline = [
      "bash /tmp/boot-fips-wrapper.sh pre",
      "echo 'Running Ansible Lockdown'",
      "echo 'Installing Python packages for EL8...'",
      "yum install -y python39 python39-pip python3-pip python3-libselinux policycoreutils-python-utils",
      "python3.9 --version",
      "python3.6 --version",
      "echo 'Upgrading pip for Python 3.9 to support newer wheel formats...'",
      "python3.9 -m pip install --upgrade pip",
      "echo 'Checking for offline Python wheels...'",
      "if [ -d '/tmp/python-deps' ]; then echo '  /tmp/python-deps directory exists'; ls -lh /tmp/python-deps/ | head -5; else echo '  /tmp/python-deps directory NOT found'; fi",
      "if [ -d '/tmp/python-deps' ] && [ \"$(ls -A /tmp/python-deps 2>/dev/null)\" ]; then echo 'Installing Ansible from offline wheels to Python 3.9...'; python3.9 -m pip install --no-index /tmp/python-deps/*.whl; else echo 'Installing Ansible from PyPI to Python 3.9...'; python3.9 -m pip install ansible-core; fi",
      "echo 'Installing Ansible for Python 3.6 (for SELinux module compatibility)...'",
      "python3.6 -m pip install ansible-core",
      "export PATH=/usr/local/bin:$PATH",
      "echo 'Installing Ansible collections...'",
      "if [ -d '/tmp/ansible-collections' ]; then for tarball in /tmp/ansible-collections/*.tar.gz; do [ -f \"$tarball\" ] && ansible-galaxy collection install \"$tarball\" --force; done; fi",
      "mkdir -p $HOME/.ansible/roles",
      "cp -r /tmp/RHEL8-STIG $HOME/.ansible/roles/",
      "echo 'Running RHEL8-STIG playbook with Python 3.6 (for SELinux module support)...'",
      "ansible-playbook -i localhost, -c local $HOME/.ansible/roles/RHEL8-STIG/site.yml -e '{\"ansible_python_interpreter\": \"/usr/bin/python3.6\", \"system_is_ec2\": true, \"rhel8stig_copy_existing_zone\": false, \"rhel_08_040136\":false}'",
      "echo 'Installing OpenSCAP for compliance scanning...'",
      "yum install -y openscap-scanner scap-security-guide",
      "echo 'Running OpenSCAP STIG compliance scan...'",
      "oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_stig --results /tmp/oscap-results.xml --report /tmp/oscap-report.html /usr/share/xml/scap/ssg/content/ssg-rhel8-ds.xml || true",
      "echo 'OpenSCAP scan complete. Report saved to /tmp/oscap-report.html'",
      "bash /tmp/boot-fips-wrapper.sh post",
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
    only = ["amazon-ebs.hardened-ol-8-hvm"]
    execute_command = "sudo -E bash '{{.Path}}'"
    inline = [
      "bash /tmp/boot-fips-wrapper.sh pre",
      "echo 'Running Ansible Lockdown'",
      "echo 'Installing Python packages for EL8...'",
      "yum install -y python39 python39-pip python3-pip python3-libselinux policycoreutils-python-utils",
      "python3.9 --version",
      "python3.6 --version",
      "echo 'Upgrading pip for Python 3.9 to support newer wheel formats...'",
      "python3.9 -m pip install --upgrade pip",
      "echo 'Checking for offline Python wheels...'",
      "if [ -d '/tmp/python-deps' ]; then echo '  /tmp/python-deps directory exists'; ls -lh /tmp/python-deps/ | head -5; else echo '  /tmp/python-deps directory NOT found'; fi",
      "if [ -d '/tmp/python-deps' ] && [ \"$(ls -A /tmp/python-deps 2>/dev/null)\" ]; then echo 'Installing Ansible from offline wheels to Python 3.9...'; python3.9 -m pip install --no-index /tmp/python-deps/*.whl; else echo 'Installing Ansible from PyPI to Python 3.9...'; python3.9 -m pip install ansible-core; fi",
      "echo 'Installing Ansible for Python 3.6 (for SELinux module compatibility)...'",
      "python3.6 -m pip install ansible-core",
      "export PATH=/usr/local/bin:$PATH",
      "echo 'Installing Ansible collections...'",
      "if [ -d '/tmp/ansible-collections' ]; then for tarball in /tmp/ansible-collections/*.tar.gz; do [ -f \"$tarball\" ] && ansible-galaxy collection install \"$tarball\" --force; done; fi",
      "mkdir -p $HOME/.ansible/roles",
      "cp -r /tmp/RHEL8-STIG $HOME/.ansible/roles/",
      "echo 'Running RHEL8-STIG playbook with Python 3.6 (for SELinux module support)...'",
      "ansible-playbook -i localhost, -c local $HOME/.ansible/roles/RHEL8-STIG/site.yml -e '{\"ansible_python_interpreter\": \"/usr/bin/python3.6\", \"system_is_ec2\": true, \"rhel8stig_copy_existing_zone\": false, \"rhel_08_040136\":false}'",
      "echo 'Installing OpenSCAP for compliance scanning...'",
      "yum install -y openscap-scanner scap-security-guide",
      "echo 'Running OpenSCAP STIG compliance scan...'",
      "oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_stig --results /tmp/oscap-results.xml --report /tmp/oscap-report.html /usr/share/xml/scap/ssg/content/ssg-ol8-ds.xml || true",
      "echo 'OpenSCAP scan complete. Report saved to /tmp/oscap-report.html'",
      "bash /tmp/boot-fips-wrapper.sh post",
      "rm -rf /var/lib/cloud/seed/nocloud-net",
      "rm -rf /var/lib/cloud/sem",
      "rm -rf /var/lib/cloud/data",
      "rm -rf /var/lib/cloud/instance",
      "cloud-init clean --logs",
    ]
  }

  # Download OpenSCAP compliance report as build artifact
  provisioner "file" {
    only = [
      "amazon-ebs.hardened-rhel-9-hvm",
      "amazon-ebs.hardened-centos-9stream-hvm",
      "amazon-ebs.hardened-ol-9-hvm",
      "amazon-ebs.hardened-rhel-8-hvm",
      "amazon-ebs.hardened-ol-8-hvm",
    ]
    source      = "/tmp/oscap-report.html"
    destination = "${path.root}/.spel/"
    direction   = "download"
  }

  provisioner "ansible" {
    pause_before         = "30s"
    timeout              = "30m"
    only                 = ["amazon-ebs.hardened-windows-2016-hvm"]
    roles_path           = "${path.root}/ansible/roles"
    playbook_file        = "${path.root}/ansible/windows-2016-stig-playbook.yml"
    use_proxy            = false
    user = "TempPackerUser"
    extra_arguments = [
      "--connection", "winrm",
      "--extra-vars", "{'winrm_password': 'ComplexP@ssw0rd123!', 'ansible_winrm_server_cert_validation': 'ignore', 'ansible_port': 5986, 'ansible_winrm_operation_timeout_sec': 60, 'ansible_winrm_read_timeout_sec': 70, 'ansible_windows_domain_role': 'Standalone', 'ansible_windows_domain_member': false, 'wn16_00_000030_pass_age': '60', 'win_skip_for_test': false, 'wn16_cc_000500': false, 'wn16_cc_000510': false, 'wn16_cc_000520': false, 'wn16_cc_000530': false, 'wn16_cc_000540': false, 'wn16_cc_000550': false, 'wn16_so_000010': false, 'wn16_so_000020': false, 'wn16_so_000030': false, 'wn16_00_000450': false, 'wn16_cc_000010': false, 'wn16_cc_000020': false, 'wn16stig_newadministratorname': 'maintuser'}"
    ]
  }

  provisioner "ansible" {
    pause_before = "30s"
    timeout      = "30m"
    only = ["amazon-ebs.hardened-windows-2019-hvm"]
    roles_path = "${path.root}/ansible/roles"
    playbook_file = "${path.root}/ansible/windows-2019-stig-playbook.yml"
    use_proxy     = false
    user = "TempPackerUser"
    extra_arguments = [
      "--connection", "winrm",
      "--extra-vars", "{'winrm_password': 'ComplexP@ssw0rd123!', 'ansible_winrm_server_cert_validation': 'ignore', 'ansible_port': 5986, 'ansible_winrm_operation_timeout_sec': 60, 'ansible_winrm_read_timeout_sec': 70, 'ansible_system_vendor': 'NA', 'ansible_virtualization_type': 'hvm', 'ansible_windows_domain_role': 'Standalone', 'ansible_windows_domain_member': false, 'win_skip_for_test': false, 'wn19_cc_000470': false, 'wn19_cc_000480': false, 'wn19_cc_000500': false, 'wn19_cc_000510': false, 'wn19_cc_000520': false, 'wn19_so_000010': false, 'wn19_so_000020': false, 'wn19_so_000030': false, 'wn19_00_000450': false, 'wn19_cc_000010': false, 'wn19_cc_000020': false, 'wn19stig_newadministratorname': 'maintuser'}"
    ]
  }

  provisioner "ansible" {
    pause_before = "30s"
    timeout      = "30m"
    only = ["amazon-ebs.hardened-windows-2022-hvm"]
    roles_path = "${path.root}/ansible/roles"
    playbook_file = "${path.root}/ansible/windows-2022-stig-playbook.yml"
    use_proxy     = false
    user = "TempPackerUser"
    extra_arguments = [
      "--connection", "winrm",
      "--extra-vars", "{'winrm_password': 'ComplexP@ssw0rd123!', 'ansible_winrm_server_cert_validation': 'ignore', 'ansible_port': 5986, 'ansible_winrm_operation_timeout_sec': 60, 'ansible_winrm_read_timeout_sec': 70, 'ansible_system_vendor': 'NA', 'ansible_virtualization_type': 'hvm', 'ansible_windows_domain_role': 'Standalone', 'ansible_windows_domain_member': false, 'win_skip_for_test': false, 'wn22_ac_000010': false, 'wn22_cc_000470': false, 'wn22_cc_000480': false, 'wn22_cc_000500': false, 'wn22_cc_000510': false, 'wn22_cc_000520': false, 'wn22_so_000010': false, 'wn22_so_000020': false, 'wn22_so_000030': false, 'wn22_00_000450': false, 'wn22_cc_000010': false, 'wn22_cc_000020': false, 'wn22stig_newadministratorname': 'maintuser'}"
    ]
  }


  # =============================================================================
  # POST-STIG: EC2 Network Restoration Only
  # No WinRM restoration needed - inline PowerShell reuses existing session
  # File uploads were done BEFORE STIG hardening
  # =============================================================================
  # CRITICAL: All post-STIG operations MUST be in a SINGLE provisioner per OS
  # Packer uploads each inline script via WinRM, which fails after STIG
  # Only the FIRST provisioner after STIG works (reuses existing session)
  # =============================================================================

  # Windows 2016/2019: Run post-STIG script via scheduled task to survive WinRM death
  # Windows 2016/2019: Create scheduled task for post-STIG script
  # The scheduled task runs as SYSTEM and survives WinRM disconnection
  provisioner "powershell" {
    pause_before = "10s"
    only = [
      "amazon-ebs.hardened-windows-2016-hvm",
      "amazon-ebs.hardened-windows-2019-hvm"
    ]
    inline = [
      "$ErrorActionPreference = 'Continue'",
      "Write-Host 'Creating scheduled task for post-STIG script...'",
      "",
      "# Create scheduled task to run immediately - survives WinRM disconnection",
      "$scriptPath = 'C:\\Windows\\Temp\\post-stig.ps1'",
      "$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument \"-ExecutionPolicy Bypass -NoProfile -File `\"$scriptPath`\"\"",
      "$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10)",
      "$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest",
      "$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd",
      "Register-ScheduledTask -TaskName 'PostSTIG' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null",
      "",
      "Write-Host 'Scheduled task created. Script will run in 10 seconds.'",
      "Write-Host 'Packer will now wait on the host machine for the script to complete.'"
    ]
  }

  # Windows 2022: Create scheduled task for post-STIG script (includes Sysprep)
  provisioner "powershell" {
    pause_before = "10s"
    only = [
      "amazon-ebs.hardened-windows-2022-hvm"
    ]
    inline = [
      "$ErrorActionPreference = 'Continue'",
      "Write-Host 'Creating scheduled task for post-STIG script...'",
      "",
      "# Create scheduled task to run immediately - survives WinRM disconnection",
      "$scriptPath = 'C:\\Windows\\Temp\\post-stig.ps1'",
      "$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument \"-ExecutionPolicy Bypass -NoProfile -File `\"$scriptPath`\"\"",
      "$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10)",
      "$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest",
      "$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd",
      "Register-ScheduledTask -TaskName 'PostSTIG' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null",
      "",
      "Write-Host 'Scheduled task created. Script will run in 10 seconds.'",
      "Write-Host 'Post-STIG script includes Sysprep which will shutdown the instance.'",
      "Write-Host 'Packer will now wait on the host machine for the script to complete.'"
    ]
  }

  # Wait on the Packer HOST machine for post-STIG script to complete
  # This runs locally on the build machine, NOT over WinRM, so it works even after WinRM dies
  # 60 minutes allows time for: DISM cleanup (~20-30 min) + EC2Launch + Sysprep (~10-15 min)
  provisioner "shell-local" {
    only = [
      "amazon-ebs.hardened-windows-2016-hvm",
      "amazon-ebs.hardened-windows-2019-hvm",
      "amazon-ebs.hardened-windows-2022-hvm"
    ]
    inline = [
      "echo 'Waiting 60 minutes for post-STIG script to complete on Windows instance...'",
      "echo 'This includes DISM cleanup, EC2Launch sysprep prep, and SetupComplete.cmd installation.'",
      "for i in $(seq 1 60); do echo \"Minute $i of 60...\"; sleep 60; done",
      "echo 'Wait complete. Packer will now stop the instance and create the AMI.'"
    ]
  }
}
