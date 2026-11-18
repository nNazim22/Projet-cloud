terraform {
  backend "local" {
    workspace_dir = "/var/lib/semaphore/tfstate-aws"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73.0"
    }
  }
}

# ---------- Variables ----------
variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "vm_name" {
  type    = string
  default = "aws-test"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
  validation {
    condition     = contains(["t3.micro", "t3.small"], var.instance_type)
    error_message = "instance_type doit valoir t3.micro ou t3.small."
  }
}

variable "ssh_public_key" {
  type = string
}

variable "admin_cidr" {
  type = string
}

# Identifiant du client (nom de VM u<id>-nom) : designe son VPC, cree au prealable par aws-vpc/
variable "client_id" {
  type = number
  validation {
    condition     = var.client_id == floor(var.client_id) && var.client_id >= 1 && var.client_id <= 255 && !contains([42, 43], var.client_id)
    error_message = "client_id doit etre un entier de 1 a 255, sauf 42 et 43."
  }
}

# ---------- Fournisseur ----------
provider "aws" {
  region = var.region
}

# ---------- Lectures : identité, réseau du client, image Debian ----------
data "aws_caller_identity" "moi" {}

# Pas de repli sur le VPC par defaut : si le VPC du client n'existe pas, Terraform s'arrete.
data "aws_vpc" "client" {
  filter {
    name   = "tag:Name"
    values = ["bits-u${var.client_id}"]
  }

  filter {
    name   = "tag:Projet"
    values = ["bits-cloud"]
  }
}

data "aws_subnet" "public" {
  vpc_id = data.aws_vpc.client.id

  filter {
    name   = "tag:Name"
    values = ["bits-u${var.client_id}-public"]
  }
}

data "aws_security_group" "interne" {
  vpc_id = data.aws_vpc.client.id
  name   = "bits-u${var.client_id}-interne"
}

data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"]

  filter {
    name   = "name"
    values = ["debian-13-amd64-2*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ---------- Ressources ----------
resource "aws_key_pair" "lab" {
  key_name   = "bits-${var.vm_name}"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "ssh" {
  name        = "bits-${var.vm_name}-ssh"
  description = "SSH depuis le laboratoire uniquement"
  vpc_id      = data.aws_vpc.client.id

  ingress {
    description = "SSH labo"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "vm" {
  ami                         = data.aws_ami.debian.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.ssh.id, data.aws_security_group.interne.id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name   = var.vm_name
    Projet = "bits-cloud"
    Client = "u${var.client_id}"
  }
}

# ---------- Sorties ----------
output "image_debian" {
  value = data.aws_ami.debian.name
}

output "utilisateur" {
  value = data.aws_caller_identity.moi.arn
}

output "vm_id" {
  value = aws_instance.vm.id
}

output "vm_ip_publique" {
  value = aws_instance.vm.public_ip
}

output "vm_ip_privee" {
  value = aws_instance.vm.private_ip
}
