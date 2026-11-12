terraform {
  backend "local" {
    workspace_dir = "/var/lib/semaphore/tfstate"
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.121.0"
    }
  }
}

# ---------- Variables ----------
variable "pve_api_token" {
  type      = string
  sensitive = true
}

variable "vm_name" {
  type = string
}

variable "vm_size" {
  type    = string
  default = "medium"
  validation {
    condition     = contains(["small", "medium", "large"], var.vm_size)
    error_message = "vm_size doit valoir small, medium ou large."
  }
}

variable "vm_ip" {
  type = string
}

variable "gateway" {
  type    = string
  default = "172.16.117.1"
}

variable "dns" {
  type    = string
  default = "8.8.8.8"
}

# ---------- Tailles : template source, vCPU, RAM ----------
locals {
  sizes = {
    small  = { template = 9001, cores = 1, memory = 2048 }
    medium = { template = 9002, cores = 2, memory = 4096 }
    large  = { template = 9003, cores = 4, memory = 8192 }
  }
  size    = local.sizes[var.vm_size]
  ssh_key = trimspace(var.ssh_public_key)
}

# ---------- Connexion à Proxmox ----------
provider "proxmox" {
  endpoint  = "https://172.16.117.160:8006/"
  api_token = var.pve_api_token
  insecure  = true
}

# ---------- La VM ----------
resource "proxmox_virtual_environment_vm" "vm" {
  name      = var.vm_name
  node_name = "node2"

  clone {
    vm_id = local.size.template
    full  = true
  }

  cpu {
    cores = local.size.cores
  }

  memory {
    dedicated = local.size.memory
  }

  agent {
    enabled = true
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "${var.vm_ip}/24"
        gateway = var.gateway
      }
    }

    dns {
      servers = [var.dns]
    }

    user_account {
      username = "debian"
      keys     = [local.ssh_key]
    }
  }
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.vm.vm_id
}

output "vm_ip" {
  value = var.vm_ip
}

variable "ssh_public_key" {
  type = string
}
