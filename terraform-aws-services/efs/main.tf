terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

## Data

data "aws_vpc" "vpc_id" {
  filter {
    name   = "tag:Name"
    values = ["eks-cluster-with-new-vpc"]
  }
  lifecycle {
    postcondition {
      condition     = self.enable_dns_support == true
      error_message = "The selected VPC must have DNS support enabled."
    }
  }
}

data "aws_subnets" "private_subnets" {
  filter {
    name   = "tag:kubernetes.io/role/internal-elb"
    values = ["1"]
  }
}

## EFS File System

resource "aws_efs_file_system" "efs_kubernetes" {
  performance_mode = "generalPurpose"
  encrypted        = true
  creation_token   = "efs-kubernetes"

  tags = {
    Name = "efs_kubernetes"
  }
}

resource "aws_efs_access_point" "efs_kubernetes_access_point" {
  file_system_id = aws_efs_file_system.efs_kubernetes.id
  root_directory {
    path = "/jenkins"
    
    creation_info {
      owner_gid = 1000
      owner_uid = 1000
      permissions = 777 
    }
  }
  posix_user {
    gid = 10000
    uid = 10000
  }
}

resource "aws_efs_mount_target" "efs_kubernetes_mount_target_00" {
  file_system_id  = aws_efs_file_system.efs_kubernetes.id
  subnet_id       = data.aws_subnets.private_subnets.ids[0]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "efs_kubernetes_mount_target_02" {
  file_system_id = aws_efs_file_system.efs_kubernetes.id
  subnet_id      = data.aws_subnets.private_subnets.ids[2]
  security_groups = [aws_security_group.efs.id]
}

## Security group

resource "aws_security_group" "efs" {
  name        = "efs_sg"
  description = "Allow NFS inbound traffic"
  vpc_id      = data.aws_vpc.vpc_id.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "ingress_nfs" {
  type              = "ingress"
  from_port         = 2049
  to_port           = 2049
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.vpc_id.cidr_block]
  security_group_id = aws_security_group.efs.id
}

# Security Policy

resource "aws_efs_file_system_policy" "policy" {
  file_system_id = aws_efs_file_system.efs_kubernetes.id
  # The EFS System Policy allows clients to mount, read and perform 
  # write operations on File system 
  # The communication of client and EFS is set using aws:secureTransport Option
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "Policy01",
    "Statement": [
        {
            "Sid": "Statement",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Resource": "${aws_efs_file_system.efs_kubernetes.arn}",
            "Action": [
                "elasticfilesystem:ClientMount",
                "elasticfilesystem:ClientRootAccess",
                "elasticfilesystem:ClientWrite"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
POLICY
}