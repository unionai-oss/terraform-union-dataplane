terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    crusoe = {
      source  = "crusoecloud/crusoe"
      version = "~> 1.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
