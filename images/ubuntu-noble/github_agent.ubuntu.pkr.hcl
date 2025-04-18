packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "name_suffix" {
  description = "The suffix to append to the name of the runner"
  type        = string
  default     = "basic"
}

variable "global_tags" {
  description = "Tags to apply to everything"
  type        = map(string)
  default     = {}
}

variable "ami_tags" {
  description = "Tags to apply to the AMI"
  type        = map(string)
  default     = {}
}

variable "snapshot_tags" {
  description = "Tags to apply to the snapshot"
  type        = map(string)
  default     = {}
}

variable "custom_shell_commands" {
  description = "Additional commands to run on the EC2 instance, to customize the instance, like installing packages"
  type        = list(string)
  default     = []
}

variable "post_install_custom_shell_commands" {
  description = "Additional commands to run on the EC2 instance, to customize the instance, like installing packages"
  type        = list(string)
  default     = []
}

variable "runner_version" {
  description = "The version (no v prefix) of the runner software to install https://github.com/actions/runner/releases"
  type        = string
  default     = "2.322.0"
}

variable "runner_architecture" {
  description = "The architecture of the runner software to install"
  type        = string
  default     = "x64"
}

source "amazon-ebs" "githubrunner" {
  ami_name                    = join("-", [
    "github-runner",
    "ubuntu-noble",
    "${var.runner_architecture == "x64" ? "amd64" : "arm64"}",
    formatdate("YYYYMMDDhhmm", timestamp()),
    var.name_suffix
  ])
  instance_type               = "${var.runner_architecture == "x64" ? "t3.medium" : "m7g.medium"}"
  region                      = "us-east-1"

  source_ami_filter {
    filters = {
      name                = "*ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${var.runner_architecture == "x64" ? "amd64" : "arm64"}-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }
  ssh_username = "ubuntu"
  # https://github.com/hashicorp/packer/issues/11733
  temporary_key_pair_type = "ed25519"
  tags = merge(
    var.global_tags,
    var.ami_tags,
    {
      OS_Version    = "ubuntu-noble"
      Release       = "Latest"
      Base_AMI_Name = "{{ .SourceAMIName }}"
  })
  snapshot_tags = merge(
    var.global_tags,
    var.snapshot_tags,
  )

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = "30"
    volume_type           = "gp3"
    delete_on_termination = "true"
  }
}

build {
  name = "githubactions-runner"
  sources = [
    "source.amazon-ebs.githubrunner"
  ]

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = concat([
      "sudo useradd -m runner",
      "sudo usermod -a -G sudo runner",
      "sudo echo 'runner ALL=(ALL) NOPASSWD:ALL' | sudo tee -a /etc/sudoers"
    ])
  }

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = concat([
      "sudo cloud-init status --wait",
      "sudo apt-get -y update",
      "sudo apt-get -y install ca-certificates curl gnupg lsb-release",
      "sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get -y update",
      "sudo apt-get -y install docker-ce docker-ce-cli containerd.io jq git unzip",
      "sudo systemctl enable containerd.service",
      "sudo systemctl disable docker.service",
      // "sudo service docker start",
      "sudo usermod -a -G docker runner",
      "sudo curl -f https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/${var.runner_architecture == "x64" ? "amd64" : "arm64"}/latest/amazon-cloudwatch-agent.deb -o amazon-cloudwatch-agent.deb",
      "sudo dpkg -i amazon-cloudwatch-agent.deb",
      "sudo systemctl restart amazon-cloudwatch-agent",
      "sudo curl -f https://awscli.amazonaws.com/awscli-exe-linux-${var.runner_architecture == "x64" ? "x86_64" : "aarch64"}.zip -o awscliv2.zip",
      "unzip awscliv2.zip",
      "sudo ./aws/install",
    ], var.custom_shell_commands)
  }

  provisioner "file" {
    content = file("../sysctl.conf")
    destination = "/tmp/sysctl.conf"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/sysctl.conf /etc/sysctl.conf",
    ]
  }

  provisioner "file" {
    content = templatefile("../install-runner.sh", {
      ARM_PATCH                       = ""
      S3_LOCATION_RUNNER_DISTRIBUTION = ""
      RUNNER_ARCHITECTURE             = "${var.runner_architecture}"
    })
    destination = "/tmp/install-runner.sh"
  }

  provisioner "shell" {
    environment_vars = [
      "RUNNER_TARBALL_URL=https://github.com/actions/runner/releases/download/v${var.runner_version}/actions-runner-linux-${var.runner_architecture}-${var.runner_version}.tar.gz"
    ]
    inline = [
      "sudo chmod +x /tmp/install-runner.sh",
      "echo runner | tee -a /tmp/install-user.txt",
      "sudo RUNNER_ARCHITECTURE=${var.runner_architecture} RUNNER_TARBALL_URL=$RUNNER_TARBALL_URL /tmp/install-runner.sh",
      "echo ImageOS=ubuntu24 | sudo tee -a /home/runner/.env"
    ]
  }

  provisioner "file" {
    content = templatefile("../start-runner.sh", {})
    destination = "/tmp/start-runner.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/start-runner.sh /var/lib/cloud/scripts/per-boot/start-runner.sh",
      "sudo chmod +x /var/lib/cloud/scripts/per-boot/start-runner.sh",
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    expect_disconnect = true
    inline = [
      # force a reboot so the docker group is effective with the runner user.
      "sudo reboot"
    ]
  }

  provisioner "shell" {
    pause_before = "15s"
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = concat([
      "echo custom post install step"
    ], var.post_install_custom_shell_commands)
  }
}
