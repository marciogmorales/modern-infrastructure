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
    encrypted = true
    creation_token = "efs-kubernetes"
    
    tags = {
        Name = "efs_kubernetes"
    }
}

resource "aws_efs_access_point" "efs_kubernetes_access_point" {
    file_system_id = aws_efs_file_system.efs_kubernetes.id
}

resource "aws_efs_mount_target" "efs_kubernetes_mount_target_00" {
    file_system_id = aws_efs_file_system.efs_kubernetes.id
    subnet_id = data.aws_subnets.private_subnets.ids[0]
}

resource "aws_efs_mount_target" "efs_kubernetes_mount_target_02" {
    file_system_id = aws_efs_file_system.efs_kubernetes.id
    subnet_id = data.aws_subnets.private_subnets.ids[2]
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
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  cidr_blocks = [data.aws_vpc.vpc_id.cidr_block]
  security_group_id = aws_security_group.efs.id
}
   