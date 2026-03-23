variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_source_ami_alma9_hvm" {
  type    = string
  default = env("amazon_ebssurrogate_minimal_alma_9_hvm")
}

variable "aws_source_ami_amzn2023_hvm" {
  type    = string
  default = env("amazon_ebssurrogate_minimal_amzn_2023_hvm")
}

variable "aws_source_ami_centos8stream_hvm" {
  type    = string
  default = env("amazon_ebssurrogate_minimal_centos_8stream_hvm")
}

variable "aws_source_ami_centos9stream_hvm" {
  type    = string
  default = env("amazon_ebssurrogate_minimal_centos_9stream_hvm")
}

variable "aws_source_ami_ol_8_hvm" {
  type    = string
  default = env("amazon_ebssurrogate_minimal_ol_8_hvm")
}

variable "aws_source_ami_ol_9_hvm" {
  type    = string
  default = env("amazon_ebssurrogate_minimal_ol_9_hvm")
}

variable "aws_source_ami_rhel8_hvm" {
  type    = string
  default = env("amazon_ebssurrogate_minimal_rhel_8_hvm")
}

variable "aws_source_ami_rhel9_hvm" {
  type    = string
  default = env("amazon_ebssurrogate_minimal_rhel_9_hvm")
}

variable "aws_source_ami_rl9_hvm" {
  type    = string
  default = env("amazon_ebssurrogate_minimal_rl_9_hvm")
}

variable "aws_ssh_interface" {
  type    = string
  default = "public_dns"
}

variable "aws_subnet_id" {
  type    = string
  default = ""
}

variable "aws_temporary_security_group_source_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "granite_amiutilsource" {
  type    = string
  default = env("GRANITE_AMIUTILSOURCE")
}

variable "granite_disablefips" {
  type    = string
  default = ""
}

variable "granite_identifier" {
  type    = string
  default = env("GRANITE_IDENTIFIER")
}

variable "granite_pypi_url" {
  type    = string
  default = "https://pypi.org/simple"
}

variable "granite_version" {
  type    = string
  default = env("GRANITE_VERSION")
}

source "amazon-ebs" "base" {
  ami_description             = "This is a validation AMI for ${var.granite_identifier}-${source.name}-${var.granite_version}.x86_64-gp3"
  ami_name                    = "validation-${var.granite_identifier}-${source.name}-${var.granite_version}.x86_64-gp3"
  associate_public_ip_address = true
  communicator                = "ssh"
  ena_support                 = true
  force_deregister            = true
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = source.name == "minimal-amzn-2023-hvm" ? "/dev/xvda" : "/dev/sda1"
    volume_size           = 21
    volume_type           = "gp3"
  }
  max_retries                           = 20
  region                                = var.aws_region
  skip_create_ami                       = true
  skip_save_build_region                = true
  sriov_support                         = true
  ssh_interface                         = var.aws_ssh_interface
  ssh_port                              = 22
  ssh_pty                               = true
  ssh_username                          = "granite"
  subnet_id                             = var.aws_subnet_id
  temporary_security_group_source_cidrs = var.aws_temporary_security_group_source_cidrs
  user_data_file                        = "${path.root}/userdata/validation.cloud"
}

build {

  source "amazon-ebs.base" {
    source_ami = var.aws_source_ami_alma9_hvm
    name       = "minimal-alma-9-hvm"
  }

  source "amazon-ebs.base" {
    source_ami = var.aws_source_ami_amzn2023_hvm
    name       = "minimal-amzn-2023-hvm"
  }

  source "amazon-ebs.base" {
    source_ami = var.aws_source_ami_centos9stream_hvm
    name       = "minimal-centos-9stream-hvm"
  }

  source "amazon-ebs.base" {
    source_ami = var.aws_source_ami_ol_8_hvm
    name       = "minimal-ol-8-hvm"
  }

  source "amazon-ebs.base" {
    source_ami = var.aws_source_ami_ol_9_hvm
    name       = "minimal-ol-9-hvm"
  }

  source "amazon-ebs.base" {
    source_ami = var.aws_source_ami_rhel8_hvm
    name       = "minimal-rhel-8-hvm"
  }

  source "amazon-ebs.base" {
    source_ami = var.aws_source_ami_rhel9_hvm
    name       = "minimal-rhel-9-hvm"
  }

  source "amazon-ebs.base" {
    source_ami = var.aws_source_ami_rl9_hvm
    name       = "minimal-rl-9-hvm"
  }

  provisioner "shell" {
    execute_command = "{{ .Vars }} sudo -E /bin/bash -ex -o pipefail '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/grow_check.sh",
    ]
  }

  provisioner "shell" {
    execute_command = "{{ .Vars }} sudo -E /bin/sh -ex -o pipefail '{{ .Path }}'"
    inline = [
      "mkdir -p /tmp/granite/tests",
      "chown -R granite:granite /tmp/granite",
    ]
    pause_before = "5s"
  }

  provisioner "file" {
    destination  = "/tmp/granite/tests"
    direction    = "upload"
    pause_before = "5s"
    source       = "tests/"
  }

  provisioner "shell" {
    environment_vars = [
      "PYPI_URL=${var.granite_pypi_url}",
    ]
    execute_command = "{{ .Vars }} sudo -E /bin/sh -ex -o pipefail '{{ .Path }}'"
    inline = [
      "PYPI_URL=$${PYPI_URL:-https://pypi.org/simple}",
      "ls -alR /tmp",
      "python3 -m ensurepip",
      "python3 -m pip install --index-url=\"$PYPI_URL\" -r /tmp/granite/tests/requirements.txt",
      "for DEV in $(lsblk -ln | awk '/ part /{ print $1}'); do pvresize /dev/$${DEV} || true; done",
    ]
    pause_before = "5s"
  }

  provisioner "shell" {
    environment_vars = [
      "LVM_SUPPRESS_FD_WARNINGS=1",
      "GRANITE_AMIUTILSOURCE=${var.granite_amiutilsource}",
      "GRANITE_DISABLEFIPS=${var.granite_disablefips}",
    ]
    execute_command = "{{ .Vars }} sudo -E /bin/sh -ex -o pipefail '{{ .Path }}'"
    inline = [
      "PATH=/usr/local/bin:\"$PATH\"",
      "export PATH",
      "pytest --strict-markers -s -v --color=no /tmp/granite | tee /tmp/pytest.log",
    ]
    pause_before = "5s"
  }

  provisioner "file" {
    destination = ".granite/${var.granite_version}/validation-${var.granite_identifier}-${source.name}.log"
    direction   = "download"
    source      = "/tmp/pytest.log"
  }

  post-processor "artifice" {
    files = [
      ".granite/${var.granite_version}/validation-${var.granite_identifier}-${source.name}.log",
    ]
  }
}
