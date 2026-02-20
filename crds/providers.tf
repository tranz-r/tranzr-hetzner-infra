
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.33.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.19.0"
    }

    external = {
      source  = "hashicorp/external"
      version = "2.3.4"
    }

    http = {
      source  = "hashicorp/http"
      version = "3.4.5"
    }
  }

  backend "azurerm" {
    resource_group_name  = "tranzr-move-rg"
    storage_account_name = "tranzrmovessa"
    container_name       = "tranzr-infra-tfstate"
    key                  = "crds.tfstate"
  }
}

provider "azurerm" {
  resource_provider_registrations = "all"
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

provider "kubectl" {
  config_path = var.kubeconfig_path
}

provider "external" {}

provider "http" {}
