variable "region" {}
variable "aws_ami" {}
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_key_name" {}

terraform {
    backend "s3" {
        bucket = "tmp-idp"
        key = "terraform-test/network/terraform.tfstate"
        region = "us-west-1"
    }
}

# this is a dumb way of adding a key to amazon, but I'm doing it this way cause it's easy and this is a demo
module "aws" { 
    source = "../module/aws"

    region = "${var.region}"
    aws_access_key = "${var.aws_access_key}"
    aws_secret_key = "${var.aws_secret_key}"
    aws_key_path = "~/.ssh/"
    aws_key_name = "${var.aws_key_name}"
}

module "network" {
    source = "../module/network"

    name = "Main"
    vpc_block = "10.0.0.0/16"
    subnet_blocks = ["10.0.0.0/24" , "10.0.1.0/24"]
    azs = ["us-west-1a", "us-west-1b"]
}

module "security" {
    source = "../module/security"

    vpc_id = "${module.network.vpc_id}"
}

resource "aws_s3_bucket" "env_vars" {
  bucket = "test-ll-env-vars"
  region = "${var.region}"
  acl = "private"
  force_destroy = true

  versioning {
    enabled = true
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.env_vars.arn}/*"
    ]

    principals {
      type = "*"
      identifiers = ["*"]
    }
  }
}

data "aws_iam_policy_document" "instance" {
  statement {
    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.env_vars.arn}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "my_bucket_policy" {
  	bucket = "${aws_s3_bucket.env_vars.id}"
  	policy = "${data.aws_iam_policy_document.bucket.json}"
}

resource "aws_iam_role" "role" {
  name = "test_s3_role"
  path = "/"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "policy" {
    name        = "test-policy"
    description = "A test policy"
    policy = "${data.aws_iam_policy_document.instance.json}"
}

resource "aws_iam_role_policy_attachment" "role" {
    role = "${aws_iam_role.role.name}"
    policy_arn = "${aws_iam_policy.policy.arn}"
}

resource "aws_iam_instance_profile" "test_profile" {
  name  = "test-profile"
  role = "${aws_iam_role.role.name}"
}