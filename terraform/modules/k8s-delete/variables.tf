variable "backend_image" {
  default = "backend/application-backend:latest"
}

variable "frontend_image" {
  default = "frontend/application-frontend:latest"
}

variable "env" {
  type = string
}

variable "namespace" {
  default = "app"
}