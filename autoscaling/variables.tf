variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_key_path" {}
variable "aws_key_name" {}
variable "aws_ami" {
	type = "string"
	default = "ami-3a674d5a"
}
variable "app_name" {
	type = "string"
	default = "application"
}
variable "app_version" {
	type = "string"
}
variable "instance_type" {
	type = "string"
	default = "m1.medium"
}
variable "docker_image" {
	type = "string"
}