# --------------------------------------------------
# GENERAL
# --------------------------------------------------
environment = "dev"
aws_region = "ap-south-1"
project_name = "mlops"

# VPC
vpc_cidr            = "10.0.0.0/16"
azs                 = ["ap-south-1a", "ap-south-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

# EKS Authentication Admin and developer users
admin_user_arns = [ "arn:aws:iam::929861724743:user/Salah_Abbasi" ]
developer_user_arns = [ "arn:aws:iam::929861724743:user/developer" ] 