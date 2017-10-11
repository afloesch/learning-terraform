variable "region" {}
variable "aws_ami" {}
variable "aws_key_name" {}
variable "aws_access_key" {}
variable "aws_secret_key" {}

variable "iam_instance_profile" {}
variable "loadbalancer_id" {}
variable "subnet_group_ids" {
    type = "list"
}
variable "security_group_ids" {
    type = "list"
}
variable "instance_type" {
    default = "m1.medium"
}

variable "app_name" {}
variable "app_version" {}
variable "app_env_var_filename" {}
variable "app_env_var_bucket" {}

variable "docker_image" {}
variable "docker_port" {
    default = "80"
}
variable "max" {
    default = "10"
}
variable "min" {
    default = "2"
}

variable "sumo_access_id" {}
variable "sumo_access_key" {}
variable "sumo_collector_name" {}
