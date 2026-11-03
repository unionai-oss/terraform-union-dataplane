terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    coreweave = {
      source  = "coreweave/coreweave"
      version = "~> 0.26"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
