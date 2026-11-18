# Reseau d'un client AWS : un VPC par client, cree a sa premiere commande puis reutilise.
# Etat Terraform separe de celui des VM (workspace vpc-u<id>) : supprimer une VM ne detruit pas le reseau.

terraform {
  backend "local" {
    workspace_dir = "/var/lib/semaphore/tfstate-aws-vpc"
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

variable "client_id" {
  type = number
  validation {
    condition     = var.client_id == floor(var.client_id) && var.client_id >= 1 && var.client_id <= 255 && !contains([42, 43], var.client_id)
    error_message = "client_id doit etre un entier de 1 a 255, sauf 42 et 43 (reserves a K3s : 10.42.0.0/16 et 10.43.0.0/16)."
  }
}

locals {
  nom  = "bits-u${var.client_id}"
  cidr = "10.${var.client_id}.0.0/16"
  tags = {
    Projet = "bits-cloud"
    Client = "u${var.client_id}"
  }
}

# ---------- Fournisseur ----------
provider "aws" {
  region = var.region
}

data "aws_availability_zones" "dispo" {
  state = "available"
}

# ---------- Reseau ----------
resource "aws_vpc" "client" {
  cidr_block           = local.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = local.nom })
}

resource "aws_internet_gateway" "client" {
  vpc_id = aws_vpc.client.id

  tags = merge(local.tags, { Name = local.nom })
}

# Un seul sous-reseau public : 10.<id>.1.0/24
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.client.id
  cidr_block              = cidrsubnet(local.cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.dispo.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${local.nom}-public" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.client.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.client.id
  }

  tags = merge(local.tags, { Name = "${local.nom}-public" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Trafic interne : les VM du client qui portent ce groupe se parlent entre elles.
# La regle SSH reste dans le groupe de chaque VM (adresse d'administration recalculee a chaque creation).
resource "aws_security_group" "interne" {
  name        = "${local.nom}-interne"
  description = "Trafic interne au VPC du client"
  vpc_id      = aws_vpc.client.id

  ingress {
    description = "Entre les VM du client"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Vers le VPC du client"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.cidr]
  }

  tags = merge(local.tags, { Name = "${local.nom}-interne" })
}

# ---------- Sorties ----------
output "vpc_id" {
  value = aws_vpc.client.id
}

output "vpc_cidr" {
  value = aws_vpc.client.cidr_block
}

output "subnet_id" {
  value = aws_subnet.public.id
}
