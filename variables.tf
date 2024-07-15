variable "vpc_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "node_pool_instance_type" {
  type    = string
  default = "m6g.medium"
}

variable "tags" {
  default = {}
}