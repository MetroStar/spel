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

variable "chimera_ci" {
  type    = bool
  default = false
}

variable "chimera_identifier" {
  type = string
}

variable "chimera_repo_commit" {
  type    = string
  default = "master"
}

variable "chimera_repo_url" {
  type    = string
  default = "https://github.com/MetroStar/chimera.git"
}

variable "chimera_version" {
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
  ami_name                    = "builder-${var.chimera_identifier}-vagrant-${var.chimera_version}.x86_64-gp3"
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
      "CHIMERA_CI=${var.chimera_ci}",
      "CHIMERA_IDENTIFIER=${var.chimera_identifier}",
      "CHIMERA_REPO_COMMIT=${var.chimera_repo_commit}",
      "CHIMERA_REPO_URL=${var.chimera_repo_url}",
      "CHIMERA_VERSION=${var.chimera_version}",
      "VAGRANT_CLOUD_TOKEN=${var.vagrant_cloud_token}",
      "VAGRANT_CLOUD_USER=${var.vagrant_cloud_user}",
      "VIRTUALBOX_ISO_URL_CENTOS9STREAM=${var.virtualbox_iso_url_centos9stream}",
    ]
    execute_command = "{{ .Vars }} sudo -E /bin/bash '{{ .Path }}'"
    scripts = [
      "${path.root}/build-chimera-vagrant.sh",
    ]
  }

  provisioner "file" {
    destination = ".chimera/"
    direction   = "download"
    source      = "/tmp/chimera/.chimera/${var.chimera_version}/"
  }
}
