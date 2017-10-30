variable "region" {
	default = "us-west-1"
}
variable "aws_access_key" {}
variable "aws_secret_key" {}

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.region}"
}

module "network" {
    source = "../module/network"

    name = "Stage"
    vpc_block = "10.0.0.0/16"
    subnet_blocks = ["10.0.0.0/24" , "10.0.1.0/24"]
    azs = ["us-west-1a", "us-west-1b"]
}