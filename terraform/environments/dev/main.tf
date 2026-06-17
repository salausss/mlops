
module "vpc" {
  source                = "../../modules/networking"
  project_name          = var.project_name
  env                   = var.environment
  vpc_cidr              = "10.1.0.0/16"
  azs                   = ["ap-south-1a", "ap-south-1b"]
  public_subnet_cidrs   = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs  = ["10.1.11.0/24", "10.1.12.0/24"]
  cluster_name          = var.project_name
}
 
module "s3_bucket" {
  source      = "../../modules/s3"
  bucket_name = "mlops-dev-uploads"

  versioning_enabled   = true
  enable_encryption    = true
  block_public_access  = true

  tags = {
    Project     = "TaskFlow"
    Environment = "dev"
  }
}

module "chat_session_history" {
  source = "../../modules/dynamodb"

  table_name    = "chat_session_history"
  hash_key      = "session_id"
  hash_key_type = "S"
  range_key     = "timestamp"
  range_key_type = "N"

  ttl_attribute_name = "expires_at"

  extra_attributes = [
    { name = "user_id", type = "S" }
  ]

  global_secondary_indexes = [
    {
      name            = "user_id-index"
      hash_key        = "user_id"
      range_key       = "timestamp"
      projection_type = "ALL"
    }
  ]
}

module "order_lookup" {
  source = "../../modules/dynamodb"

  table_name    = "order_lookup"
  hash_key      = "order_id"
  hash_key_type = "S"

  extra_attributes = [
    { name = "customer_id", type = "S" },
    { name = "order_date", type = "N" }
  ]

  global_secondary_indexes = [
    {
      name            = "customer_id-index"
      hash_key        = "customer_id"
      range_key       = "order_date"
      projection_type = "ALL"
    }
  ]
}

module "ecr" {
  source = "../../modules/ecr"
  repository_names = ["frontend","backend"]
  environment = var.environment
}

module "kms" {
  source                = "../../modules/kms"
  name                  = var.project_name
  alias                 = "kms_alias"
  environment           = var.environment
  description           = "kms_description"
}

module "eks" {
  source                  = "../../modules/eks"
  cluster_name            = var.project_name
  cluster_version         = 1.35
  subnet_ids              = module.vpc.private_subnet_ids
  kms_key_arn             = module.kms.key_arn
  cluster_node_name       = "cluster_node_demo"
  application_node_name   = "application"
  database_node_name      = "database"
}

module "eks-addons" {
  source = "../../modules/eks-addons"
  region = var.aws_region
  cluster_name = var.project_name 
}

module "eks_rbac" {
  source = "../../modules/eks_auth"
  cluster_name         = module.eks.cluster_name
  env                  = var.environment
  admin_group_name     = "eks:admin-group"
  developer_group_name = "eks:developer-group"
  developer_namespaces = ["app", "db"]
  node_group_role      = module.eks.node_group_role
  admin_user_arns      = var.admin_user_arns
  developer_user_arns  = var.developer_user_arns
}

module "alb_controller" {
  source = "../../modules/eks_controllers"
  cluster_name     = module.eks.cluster_name
  aws_region       = var.aws_region
  vpc_id           = module.vpc.vpc_id
}

module "storage" {
  source = "../../modules/volume"
  cluster_name           = module.eks.cluster_name
  environment            = var.environment
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  node_security_group_id = module.eks.cluster_security_group_id
  kms_key_arn = module.kms.key_arn
}

#module "application_deploy" {
#  source = "../../modules/app_deploy"
#}



module "SecretsManager" {
  source = "../../modules/secrets-manager"
  cluster_name = module.eks.cluster_name
  env = var.environment
  kms_key_arn       = module.kms.key_arn         
  app_namespace       = "app"
  db_namespace        = "db"
  app_service_account = "taskflow-app-sa"
  db_service_account  = "taskflow-db-sa"
  rotation_days       = 30
  region              = var.aws_region
}

module "observability-2" {
  source = "../../modules/observability"
  cluster_name = module.eks.cluster_name
  environment = var.environment
}

module "guardduty" {
  source = "../../modules/guardduty"
  project     = var.project_name
  environment = var.environment       
  alert_email = "salauss00@gmail.com"  
}