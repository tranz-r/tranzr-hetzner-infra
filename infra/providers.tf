
terraform {
  backend "azurerm" {}
  required_providers {

    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.56.0"
    }

    template = { 
      source  = "hashicorp/template"
      version = "~> 2.2"
    }

    random   = { 
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "tranzr-move-rg"
    storage_account_name = "tranzrmovessa"
    container_name       = "tranzr-infra-tfstate"
    key                  = "infra.tfstate"
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "azurerm" {
  resource_provider_registrations = "all"
  features {}
}