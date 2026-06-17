terraform {
  required_version = ">= 1.5.0"
  
  backend "s3" {
    bucket         = "salah-training-period"
    key            = "dev/terraform.tfstate"
    region         = "ap-south-1"
    use_lockfile   = true
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.0.1"  
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0"
    }
    
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
    null  = {
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }
    grafana = {
      source  = "grafana/grafana"
      #version = "~> 3.0" 
    }
  }
}
