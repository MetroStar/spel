packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "aws_instance_type" {
  type    = string
  default = "c5n.metal"
}

variable "aws_temporary_security_group_source_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "packer_version" {
  type    = string
  default = ""
}

variable "granite_ci" {
  type    = bool
  default = false
}

variable "granite_identifier" {
  type = string
}

variable "granite_repo_commit" {
  type    = string
  default = "master"
}

variable "granite_repo_url" {
  type    = string
  default = "https://github.com/MetroStar/granite.git"
}

variable "granite_version" {
  type = string
}

variable "vagrant_cloud_token" {
  type    = string
  default = env("VAGRANT_CLOUD_TOKEN")
}

variable "vagrant_cloud_user" {
  type    = string
  default = "MetroStar"
}

variable "virtualbox_iso_url_centos9stream" {
  type = string
}

source "amazon-ebs" "ubuntu" {
  ami_name                    = "builder-${var.granite_identifier}-vagrant-${var.granite_version}.x86_64-gp3"
  associate_public_ip_address = true
  communicator                = "ssh"
  force_deregister            = true
  instance_type               = var.aws_instance_type
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
    volume_type           = "gp3"
  }
  max_retries            = 20
  skip_create_ami        = true
  skip_save_build_region = true
  source_ami_filter {
    filters = {
      architecture        = "x86_64"
      name                = "ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"]
    most_recent = true
  }
  ssh_port                              = 22
  ssh_pty                               = true
  ssh_username                          = "ubuntu"
  temporary_security_group_source_cidrs = var.aws_temporary_security_group_source_cidrs
}

build {
  sources = ["amazon-ebs.ubuntu"]

  provisioner "shell" {
    environment_vars = [
      "PACKER_NO_COLOR=1",
      "PACKER_VERSION=${var.packer_version}",
      "GRANITE_CI=${var.granite_ci}",
      "GRANITE_IDENTIFIER=${var.granite_identifier}",
      "GRANITE_REPO_COMMIT=${var.granite_repo_commit}",
      "GRANITE_REPO_URL=${var.granite_repo_url}",
      "GRANITE_VERSION=${var.granite_version}",
      "VAGRANT_CLOUD_TOKEN=${var.vagrant_cloud_token}",
      "VAGRANT_CLOUD_USER=${var.vagrant_cloud_user}",
      "VIRTUALBOX_ISO_URL_CENTOS9STREAM=${var.virtualbox_iso_url_centos9stream}",
    ]
    execute_command = "{{ .Vars }} sudo -E /bin/bash '{{ .Path }}'"
    scripts = [
      "${path.root}/build-granite-vagrant.sh",
    ]
  }

  provisioner "file" {
    destination = ".granite/"
    direction   = "download"
    source      = "/tmp/granite/.granite/${var.granite_version}/"
  }
}
