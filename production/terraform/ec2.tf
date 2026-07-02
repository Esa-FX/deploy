data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}

locals {
  linux_user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    dnf update -y
    dnf install -y docker git
    systemctl enable --now docker
    usermod -aG docker ec2-user
    mkdir -p /opt/esafx /opt/esafx/secrets
    curl -fsSL "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem" -o /opt/esafx/global-bundle.pem
    chmod 644 /opt/esafx/global-bundle.pem
    echo "esafx production app host ready"
  EOF
}

resource "aws_instance" "core" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.linux_instance_type
  subnet_id              = values(aws_subnet.private)[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.core.name
  key_name               = var.ssh_key_name
  user_data              = local.linux_user_data

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-core"
    Tier = "core-platform"
  })
}

resource "aws_instance" "crm" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.linux_instance_type
  subnet_id              = values(aws_subnet.private)[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.crm.name
  key_name               = var.ssh_key_name
  user_data              = local.linux_user_data

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-crm"
    Tier = "crm-workload"
  })
}

resource "aws_instance" "voip" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.linux_instance_type
  # Public subnet + Elastic IP so outbound AMI/SIP source IP is stable for vendor whitelisting.
  subnet_id              = values(aws_subnet.public)[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.voip.name
  key_name               = var.ssh_key_name
  user_data              = local.linux_user_data

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-voip"
    Tier = "voip"
  })
}

resource "aws_eip" "voip" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-voip-eip"
  })
}

resource "aws_eip_association" "voip" {
  instance_id   = aws_instance.voip.id
  allocation_id = aws_eip.voip.id
}

resource "aws_instance" "mt" {
  ami                    = data.aws_ami.windows_2022.id
  instance_type          = var.windows_instance_type
  subnet_id              = values(aws_subnet.private)[0].id
  vpc_security_group_ids = [aws_security_group.mt.id]
  iam_instance_profile   = aws_iam_instance_profile.mt.name
  key_name               = var.ssh_key_name

  root_block_device {
    volume_size = 60
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mt"
    Tier = "mt-bridge"
  })
}
