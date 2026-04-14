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
# used by many builders are prefixed with the keyword `crucible`. Variables are grouped
# by their prefix. Current prefixes
# include:
#   * aws - amazon-ebs builder
#   * amigen - used across amigen versions ( amigen8 and amigen9)
#   * amigen8 - amigen8 only
#   * amigen9 - amigen9 only
#   * crucible - everything else
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
    name = "al2023-ami-minimal-*-x86_64"
    owners = [
      "amazon",
    ]
  }
}

variable "aws_source_ami_filter_alma9_hvm" {
  description = "Object with source AMI filters for Alma Linux 9 HVM builds"
  type = object({
    name   = string
    owners = list(string)
  })
  default = {
    name = "AlmaLinux OS 9.* x86_64-*,crucible-bootstrap-alma-9*.x86_64-gp*"
    owners = [
      "679593333241", # Alma Commercial, https://wiki.almalinux.org/cloud/AWS.html#aws-marketplace
      "174003430611", # Crucible Commercial, https://github.com/MetroStar/crucible
      "216406534498", # Crucible GovCloud, https://github.com/MetroStar/crucible
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
    name = "OL8.*-x86_64-HVM-*,crucible-bootstrap-oraclelinux-8-hvm-*.x86_64-gp*,crucible-bootstrap-ol-8-*.x86_64-gp*"
    owners = [
      "131827586825", # Oracle Commercial, https://blogs.oracle.com/linux/post/running-oracle-linux-in-public-clouds
      "204182206073", # Crucible Commercial, https://github.com/MetroStar/crucible
      "317517796843", # Crucible GovCloud, https://github.com/MetroStar/crucible
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
    name = "OL9.*-x86_64-HVM-*,crucible-bootstrap-oraclelinux-9-hvm-*.x86_64-gp*,crucible-bootstrap-ol-9-*.x86_64-gp*"
    owners = [
      "131827586825", # Oracle Commercial, https://blogs.oracle.com/linux/post/running-oracle-linux-in-public-clouds
      "204182206073", # Crucible Commercial, https://github.com/MetroStar/crucible
      "317517796843", # Crucible GovCloud, https://github.com/MetroStar/crucible
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
    name = "RHEL-8.*_HVM-*-x86_64-*-Hourly*-GP*,crucible-bootstrap-rhel-8-*.x86_64-gp*"
    owners = [
      "309956199498", # Red Hat Commercial, https://access.redhat.com/solutions/15356
      "219670896067", # Red Hat GovCloud, https://access.redhat.com/solutions/15356
      "204182206073", # Crucible Commercial, https://github.com/MetroStar/crucible
      "317517796843", # Crucible GovCloud, https://github.com/MetroStar/crucible
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
    name = "RHEL-9.*_HVM-*-x86_64-*-Hourly*-GP*,crucible-bootstrap-rhel-9-*.x86_64-gp*"
    owners = [
      "309956199498", # Red Hat Commercial, https://access.redhat.com/solutions/15356
      "219670896067", # Red Hat GovCloud, https://access.redhat.com/solutions/15356
      "204182206073", # Crucible Commercial, https://github.com/MetroStar/crucible
      "317517796843", # Crucible GovCloud, https://github.com/MetroStar/crucible
    ]
  }
}

variable "aws_source_ami_filter_rl9_hvm" {
  description = "Object with source AMI filters for Rocky Linux 9 HVM builds"
  type = object({
    name   = string
    owners = list(string)
  })
  default = {
    name = "Rocky-9-EC2-Base-9.*-*.x86_64,crucible-bootstrap-rl-9-*.x86_64-gp*"
    owners = [
      "792107900819", # Rocky Linux, https://rockylinux.org/download (search for "AWS" tag and click)
      "204182206073", # Crucible Commercial, https://github.com/MetroStar/crucible
      "317517796843", # Crucible GovCloud, https://github.com/MetroStar/crucible
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

variable "aws_kms_key_id" {
  description = "ARN of the Customer Managed Key (CMK) to use for EBS volume encryption. When set, all EBS volumes will be encrypted using this key. Leave empty for no encryption or to use the default AWS-managed key"
  type        = string
  default     = ""
}

variable "amigen_repo_mirror_baseurl" {
  description = "Base URL for air-gapped yum repository mirrors. When set, disables RHUI repos and configures local mirrors. Example: http://mirror.internal.mil"
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
  description = "URL of the tar.gz bundle containing the CFN bootstrap utilities. Use file:// prefix for offline/Offline builds. Defaults to crucible_cfnbootstrap_source for Offline support"
  type        = string
  default     = ""
}

variable "amigen_aws_cliv1_source" {
  description = "URL of the .zip bundle containing the installer for AWS CLI v1"
  type        = string
  default     = ""
}

variable "amigen_aws_cliv2_source" {
  description = "URL of the .zip bundle containing the installer for AWS CLI v2. Use file:// prefix for offline/Offline builds"
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

variable "amigen_cross_distro" {
  description = "Use cross-distro build mode. When true, skips auto-detection of RHUI packages from the build host. Required for air-gapped builds using local mirrors."
  type        = bool
  default     = false
}

variable "amigen_repo_nosignature" {
  description = "Skip RPM signature check when installing repo source RPMs. Required for unsigned RPMs in air-gapped environments."
  type        = bool
  default     = false
}

variable "amigen_sslverify_disable" {
  description = "Disable SSL certificate verification for yum/dnf. Required for air-gapped environments using internal mirrors with self-signed certificates."
  type        = bool
  default     = false
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
  description = "List of package specs (rpm names or URLs to .rpm files) to install to the EL8 builders and images. Use file:// prefix for offline/Offline builds"
  type        = list(string)
  default = [
    "python39",
    "python39-pip",
    "python39-setuptools",
    "crypto-policies-scripts",
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
    "https://spel-packages.cloudarmor.io/spel-packages/repo/spel-release-latest-8.noarch.rpm",
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
  description = "List of package specs (rpm names or URLs to .rpm files) to install to the EL9 builders and images. Use file:// prefix for offline/Offline builds"
  type        = list(string)
  default = [
    "crypto-policies-scripts",
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

variable "amigen9_package_manifest_al2023" {
  description = "File containing a list of RPMs to use as the build manifest for AL2023 images"
  type        = string
  default     = "/tmp/el-build/install-manifests/al2023-minimal.txt"
}

variable "amigen9_repo_names" {
  description = "List of yum repo names to enable in the EL9 builders and EL9 images"
  type        = list(string)
  default     = ["spel"]
}

variable "amigen9_repo_sources" {
  description = "List of yum package refs (names or urls to .rpm files) that install yum repo definitions in EL9 builders and images"
  type        = list(string)
  default = [
    "https://spel-packages.cloudarmor.io/spel-packages/repo/spel-release-latest-9.noarch.rpm",
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
# Variables specific to crucible
###

variable "crucible_deprecation_lifetime" {
  description = "Duration after which image will be marked deprecated. If null, image will not be marked deprecated. The accepted units are: ns, us (or µs), ms, s, m, and h. For example, one day is 24h, and one year is 8760h."
  type        = string
  default     = null
}

variable "crucible_description_url" {
  description = "URL included in the AMI description"
  type        = string
  default     = "https://github.com/MetroStar/crucible"
}

variable "crucible_http_proxy" {
  description = "Used as the value for the git config http.proxy setting in the builder nodes"
  type        = string
  default     = ""
}

variable "crucible_identifier" {
  description = "Namespace that prefixes the name of the built images"
  type        = string
}

variable "crucible_root_volume_size" {
  description = "Size in GB of the root volume"
  type        = number
  default     = 20
}

variable "crucible_ssh_username" {
  description = "Name of the user for the ssh connection to the instance. Defaults to `crucible`, which is set by cloud-config userdata. If your starting image does not have `cloud-init` installed, override the default user name"
  type        = string
  default     = "crucible"
}

variable "crucible_version" {
  description = "Version appended to the name of the built images"
  type        = string
}

variable "crucible_cfnbootstrap_source" {
  description = "Source URL or file path for AWS CloudFormation Bootstrap package. Use file:// for offline/Offline builds"
  type        = string
  default     = "https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz"
}

variable "crucible_awscli_source" {
  description = "Source URL or file path for AWS CLI v2 package. Use file:// for offline/Offline builds"
  type        = string
  default     = "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
}

variable "crucible_ssm_agent_source" {
  description = "Source URL or file path for AWS SSM Agent RPM. Use file:// for offline/Offline builds"
  type        = string
  default     = "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm"
}

###
# End of variables blocks
###
# Start of source blocks
###

source "amazon-ebssurrogate" "base" {
  ami_root_device {
    source_device_name    = "/dev/xvdf"
    delete_on_termination = true
    device_name           = source.name == "minimal-amzn-2023-hvm" ? "/dev/xvda" : "/dev/sda1"
    volume_size           = var.crucible_root_volume_size
    volume_type           = "gp3"
  }
  ami_groups                  = var.aws_ami_groups
  ami_name                    = "${var.crucible_identifier}-${source.name}-${var.crucible_version}.x86_64-gp3"
  ami_regions                 = local.effective_ami_regions
  ami_users                   = var.aws_ami_users
  ami_virtualization_type     = "hvm"
  associate_public_ip_address = true
  communicator                = "ssh"
  deprecate_at                = local.aws_ami_deprecate_at
  ena_support                 = true
  force_deregister            = var.aws_force_deregister
  instance_type               = var.aws_instance_type
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = source.name == "minimal-amzn-2023-hvm" ? "/dev/xvda" : "/dev/sda1"
    volume_size           = var.crucible_root_volume_size
    volume_type           = "gp3"
  }
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvdf"
    volume_size           = var.crucible_root_volume_size
    volume_type           = "gp3"
  }
  max_retries   = 20
  region        = var.aws_region
  sriov_support = true
  ssh_interface = var.aws_ssh_interface
  ssh_port      = 22
  ssh_pty       = true
  ssh_username  = var.crucible_ssh_username
  ssh_timeout   = "10m"
  ssh_key_exchange_algorithms = [
    "ecdh-sha2-nistp521",
    "ecdh-sha2-nistp256",
    "ecdh-sha2-nistp384",
    "ecdh-sha2-nistp521",
    "diffie-hellman-group14-sha1",
    "diffie-hellman-group1-sha1"
  ]
  subnet_id                             = var.aws_subnet_id
  vpc_id                                = var.aws_vpc_id
  temporary_security_group_source_cidrs = var.aws_temporary_security_group_source_cidrs
  use_create_image                      = true
  user_data_file                        = "${path.root}/userdata/userdata.cloud"
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
  effective_alma9_owners         = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_alma9_hvm.owners
  effective_ol8_owners           = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_ol8_hvm.owners
  effective_ol9_owners           = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_ol9_hvm.owners
  effective_rhel8_owners         = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_rhel8_hvm.owners
  effective_rhel9_owners         = local.use_offline_ami_owners ? [var.aws_offline_account_id] : var.aws_source_ami_filter_rhel9_hvm.owners

  # Template the description string
  description = "STIG-partitioned [*NOT HARDENED*], LVM-enabled, \"minimal\" %s, with updates through ${formatdate("YYYY-MM-DD", local.timestamp)}. Default username `maintuser`. See ${var.crucible_description_url}."

  # Calculate AWS AMI deprecate_at timestamp
  aws_ami_deprecate_at = var.crucible_deprecation_lifetime != null ? timeadd(local.timestamp, var.crucible_deprecation_lifetime) : null

  timestamp = timestamp()
}

###
# End of locals block
###
# Start of build blocks
###

# amigen builds
build {
  source "amazon-ebssurrogate.base" {
    ami_description = format(local.description, "Alma Linux 9 AMI")
    name            = "minimal-alma-9-hvm"
    source_ami_filter {
      filters = {
        virtualization-type = "hvm"
        name                = var.aws_source_ami_filter_alma9_hvm.name
        root-device-type    = "ebs"
      }
      owners      = local.effective_alma9_owners
      most_recent = true
    }
  }

  source "amazon-ebssurrogate.base" {
    ami_description = format(local.description, "Amazon Linux 2023 AMI")
    name            = "minimal-amzn-2023-hvm"
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

  source "amazon-ebssurrogate.base" {
    ami_description = format(local.description, "Oracle Linux 8 AMI")
    name            = "minimal-ol-8-hvm"
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

  source "amazon-ebssurrogate.base" {
    ami_description = format(local.description, "Oracle Linux 9 AMI")
    name            = "minimal-ol-9-hvm"
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

  source "amazon-ebssurrogate.base" {
    ami_description = format(local.description, "RHEL 8 AMI")
    name            = "minimal-rhel-8-hvm"
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

  source "amazon-ebssurrogate.base" {
    ami_description = format(local.description, "RHEL 9 AMI")
    name            = "minimal-rhel-9-hvm"
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

  source "amazon-ebssurrogate.base" {
    ami_description = format(local.description, "Rocky Linux 9 AMI")
    name            = "minimal-rl-9-hvm"
    source_ami_filter {
      filters = {
        virtualization-type = "hvm"
        name                = var.aws_source_ami_filter_rl9_hvm.name
        root-device-type    = "ebs"
      }
      owners      = var.aws_source_ami_filter_rl9_hvm.owners
      most_recent = true
    }
  }

  # Configure air-gapped repositories for Linux builds
  provisioner "shell" {
    environment_vars = [
      "REPO_MIRROR_BASEURL=${var.amigen_repo_mirror_baseurl}",
    ]
    execute_command = "{{ .Vars }} sudo -E /bin/bash '{{ .Path }}'"
    inline = [
      "if [ -n \"$REPO_MIRROR_BASEURL\" ]; then",
      "  echo 'Configuring air-gapped repositories...'",
      "  ",
      "  # Detect OS version",
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
      "amazon-ebssurrogate.minimal-rhel-9-hvm",
      "amazon-ebssurrogate.minimal-rhel-8-hvm",
      "amazon-ebssurrogate.minimal-ol-9-hvm",
      "amazon-ebssurrogate.minimal-ol-8-hvm",
      "amazon-ebssurrogate.minimal-alma-9-hvm",
      "amazon-ebssurrogate.minimal-rl-9-hvm",
    ]
  }

  # Common provisioners
  
  # Upload offline packages directory if it exists (for offline/air-gapped builds)
  # Note: In online mode, this will upload an empty directory (no impact)
  # In offline mode, extract-offline-archives.sh populates this directory before Packer runs
  provisioner "file" {
    source      = "${path.root}/../offline-packages"
    destination = "/tmp/"
    only = [
      "amazon-ebssurrogate.minimal-rhel-9-hvm",
      "amazon-ebssurrogate.minimal-rhel-8-hvm",
      "amazon-ebssurrogate.minimal-ol-9-hvm",
      "amazon-ebssurrogate.minimal-ol-8-hvm",
      "amazon-ebssurrogate.minimal-amzn-2023-hvm",
      "amazon-ebssurrogate.minimal-alma-9-hvm",
      "amazon-ebssurrogate.minimal-rl-9-hvm",
    ]
  }
  
  provisioner "shell" {
    environment_vars = [
      "DNF_VAR_ociregion=",
      "DNF_VAR_ocidomain=oracle.com",
    ]
    execute_command = "{{ .Vars }} sudo -E /bin/bash -ex '{{ .Path }}'"
    inline = [
      "/usr/bin/cloud-init status --wait",
      "setenforce 0",
      "yum -y update",
    ]
  }

  # Want to try to run this pre-step early on EL9
  provisioner "shell" {
    environment_vars = [
      "DNF_VAR_ociregion=",
      "DNF_VAR_ocidomain=oracle.com",
      "CRUCIBLE_AMIGEN9SOURCE=${var.amigen9_source_url}",
      "CRUCIBLE_AMIGENREPOS=${local.amigen9_repo_names}",
      "CRUCIBLE_AMIGENREPOSRC=${local.amigen9_repo_sources}",
      "CRUCIBLE_BUILDDEPS=dosfstools git lvm2 parted python3-pip unzip yum-utils",
      "CRUCIBLE_EXTRARPMS=${local.amigen9_extra_rpms}",
      "CRUCIBLE_USEDEFAULTREPOS=${var.amigen_use_default_repos}",
    ]
    execute_command = "{{ .Vars }} sudo -E /bin/bash '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/builder-prep-9.sh",
    ]
    only = [
      "amazon-ebssurrogate.minimal-alma-9-hvm",
      "amazon-ebssurrogate.minimal-ol-9-hvm",
      "amazon-ebssurrogate.minimal-rhel-9-hvm",
      "amazon-ebssurrogate.minimal-rl-9-hvm",
    ]
  }

  # Want to try to run this pre-step early on AL2023
  provisioner "shell" {
    environment_vars = [
      "CRUCIBLE_AMIGEN9SOURCE=${var.amigen9_source_url}",
      "CRUCIBLE_AMIGENREPOS=${local.amigen9_repo_names}",
      "CRUCIBLE_AMIGENREPOSRC=${local.amigen9_repo_sources}",
      "CRUCIBLE_BUILDDEPS=dnf-utils dosfstools git lvm2 parted python3-pip unzip",
      "CRUCIBLE_EXTRARPMS=${local.amigen9_extra_rpms}",
      "CRUCIBLE_USEDEFAULTREPOS=${var.amigen_use_default_repos}",
    ]
    execute_command = "{{ .Vars }} sudo -E /bin/bash '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/builder-prep-9.sh",
    ]
    only = [
      "amazon-ebssurrogate.minimal-amzn-2023-hvm",
    ]
  }

  # AWS EL8 provisioners
  provisioner "shell" {
    environment_vars = [
      "DNF_VAR_ocidomain=oracle.com",
      "DNF_VAR_ociregion=",
      "CRUCIBLE_AMIGEN8SOURCE=${var.amigen8_source_url}",
      "CRUCIBLE_AMIGENBOOTDEVMULT=${var.amigen8_bootdev_mult}",
      "CRUCIBLE_AMIGENBOOTDEVSZ=${var.amigen8_bootdev_size}",
      "CRUCIBLE_AMIGENBOOTSIZE=17m",
      "CRUCIBLE_AMIGENBRANCH=${var.amigen8_source_branch}",
      "CRUCIBLE_AMIGENCHROOT=/mnt/ec2-root",
      "CRUCIBLE_AMIGENCROSSDISTRO=${var.amigen_cross_distro}",
      "CRUCIBLE_AMIGENNOSIGNATURE=${var.amigen_repo_nosignature}",
      "CRUCIBLE_AMIGENSSLVERIFY=${var.amigen_sslverify_disable ? "false" : "true"}",
      "CRUCIBLE_AMIGENMANFST=${var.amigen8_package_manifest}",
      "CRUCIBLE_AMIGENPKGGRP=${local.amigen8_package_groups}",
      "CRUCIBLE_AMIGENREPOS=${local.amigen8_repo_names}",
      "CRUCIBLE_AMIGENREPOSRC=${local.amigen8_repo_sources}",
      "CRUCIBLE_AMIGENROOTNM=${var.amigen8_filesystem_label}",
      "CRUCIBLE_AMIGENSTORLAY=${local.amigen8_storage_layout}",
      "CRUCIBLE_AMIGENVGNAME=RootVG",
      "CRUCIBLE_AWSCFNBOOTSTRAP=${var.amigen_aws_cfnbootstrap != "" ? var.amigen_aws_cfnbootstrap : var.crucible_cfnbootstrap_source}",
      "CRUCIBLE_AWSCLIV1SOURCE=${var.amigen_aws_cliv1_source}",
      "CRUCIBLE_AWSCLIV2SOURCE=${var.amigen_aws_cliv2_source != "" ? var.amigen_aws_cliv2_source : var.crucible_awscli_source}",
      "CRUCIBLE_CLOUDPROVIDER=aws",
      "CRUCIBLE_EXTRARPMS=${local.amigen8_extra_rpms}",
      "CRUCIBLE_FIPSDISABLE=${var.amigen_fips_disable}",
      "CRUCIBLE_GRUBTMOUT=${var.amigen_grub_timeout}",
      "CRUCIBLE_USEDEFAULTREPOS=${var.amigen_use_default_repos}",
      "CRUCIBLE_USEROOTDEVICE=false",
    ]
    execute_command = "{{ .Vars }} sudo -E /bin/bash '{{ .Path }}'"
    only = [
      "amazon-ebssurrogate.minimal-ol-8-hvm",
      "amazon-ebssurrogate.minimal-rhel-8-hvm",
    ]
    scripts = [
      "${path.root}/scripts/amigen8-build.sh",
    ]
  }

  # AWS EL9 provisioners
  provisioner "shell" {
    environment_vars = [
      "DNF_VAR_ocidomain=oracle.com",
      "DNF_VAR_ociregion=",
      "CRUCIBLE_AMIGEN9SOURCE=${var.amigen9_source_url}",
      "CRUCIBLE_AMIGENBOOTDEVLBL=${var.amigen9_boot_dev_label}",
      "CRUCIBLE_AMIGENBOOTDEVSZ=${var.amigen9_boot_dev_size}",
      "CRUCIBLE_AMIGENBOOTDEVSZMLT=${var.amigen9_boot_dev_size_mult}",
      "CRUCIBLE_AMIGENBRANCH=${var.amigen9_source_branch}",
      "CRUCIBLE_AMIGENCHROOT=/mnt/ec2-root",
      "CRUCIBLE_AMIGENCROSSDISTRO=${var.amigen_cross_distro}",
      "CRUCIBLE_AMIGENNOSIGNATURE=${var.amigen_repo_nosignature}",
      "CRUCIBLE_AMIGENSSLVERIFY=${var.amigen_sslverify_disable ? "false" : "true"}",
      "CRUCIBLE_AMIGENMANFST=${var.amigen9_package_manifest}",
      "CRUCIBLE_AMIGENMANFSTAL2023=${var.amigen9_package_manifest_al2023}",
      "CRUCIBLE_AMIGENPKGGRP=${local.amigen9_package_groups}",
      "CRUCIBLE_AMIGENREPOS=${local.amigen9_repo_names}",
      "CRUCIBLE_AMIGENREPOSRC=${local.amigen9_repo_sources}",
      "CRUCIBLE_AMIGENROOTNM=${var.amigen9_filesystem_label}",
      "CRUCIBLE_AMIGENSTORLAY=${local.amigen9_storage_layout}",
      "CRUCIBLE_AMIGENUEFIDEVLBL=${var.amigen9_uefi_dev_label}",
      "CRUCIBLE_AMIGENUEFIDEVSZ=${var.amigen9_uefi_dev_size}",
      "CRUCIBLE_AMIGENVGNAME=RootVG",
      "CRUCIBLE_AWSCFNBOOTSTRAP=${var.amigen_aws_cfnbootstrap != "" ? var.amigen_aws_cfnbootstrap : var.crucible_cfnbootstrap_source}",
      "CRUCIBLE_AWSCLIV1SOURCE=${var.amigen_aws_cliv1_source}",
      "CRUCIBLE_AWSCLIV2SOURCE=${var.amigen_aws_cliv2_source != "" ? var.amigen_aws_cliv2_source : var.crucible_awscli_source}",
      "CRUCIBLE_CLOUDPROVIDER=aws",
      "CRUCIBLE_EXTRARPMS=${local.amigen9_extra_rpms}",
      "CRUCIBLE_FIPSDISABLE=${var.amigen_fips_disable}",
      "CRUCIBLE_GRUBTMOUT=${var.amigen_grub_timeout}",
      "CRUCIBLE_USEDEFAULTREPOS=${var.amigen_use_default_repos}",
      "CRUCIBLE_USEROOTDEVICE=false",
    ]
    execute_command = "{{ .Vars }} sudo -E /bin/bash '{{ .Path }}'"
    only = [
      "amazon-ebssurrogate.minimal-alma-9-hvm",
      "amazon-ebssurrogate.minimal-amzn-2023-hvm",
      "amazon-ebssurrogate.minimal-ol-9-hvm",
      "amazon-ebssurrogate.minimal-rhel-9-hvm",
      "amazon-ebssurrogate.minimal-rl-9-hvm",
    ]
    scripts = [
      "${path.root}/scripts/amigen9-build.sh",
    ]
  }

  # Common post-processors
  provisioner "file" {
    destination = ".crucible/${var.crucible_version}/${var.crucible_identifier}-${source.name}.${source.type}.manifest.txt"
    direction   = "download"
    source      = "/tmp/manifest.txt"
  }

  post-processor "artifice" {
    files = [
      ".crucible/${var.crucible_version}/${var.crucible_identifier}-${source.name}.${source.type}.manifest.txt",
    ]
  }

  post-processor "manifest" {
    output = ".crucible/${var.crucible_version}/packer-manifest.json"
  }
}

###
# End of build blocks
###
