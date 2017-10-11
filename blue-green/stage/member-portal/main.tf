variable "region" {}
variable "aws_ami" {}
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_key_name" {}

variable "instance_type" {}
variable "sumo_access_id" {}
variable "sumo_access_key" {}

variable "bank1_version" {}
variable "bank1_docker_image" {}
variable "bank1_docker_port" {}
variable "bank1_variables_filename" {}
variable "bank1_weight" {}

variable "bank2_version" {}
variable "bank2_docker_image" {}
variable "bank2_docker_port" {}
variable "bank2_variables_filename" {}
variable "bank2_weight" {}

terraform {
    backend "s3" {
        bucket = "tmp-idp"
        key = "terraform-test/frontend/terraform.tfstate"
        region = "us-west-1"
    }
}

data "aws_vpc" "main" {
    tags { Name = "Main" }
}

data "aws_security_group" "web" {
    tags { Name = "web-traffic" }
}

data "aws_security_group" "ssh" {
    tags { Name = "ssh-traffic" }
}

data "aws_subnet_ids" "public" {
  vpc_id = "${data.aws_vpc.main.id}"
}

data "aws_iam_instance_profile" "test" {
  name = "test-profile"
}

data "aws_route53_zone" "domain" {
  name = "andrewloesch.com."
  private_zone = false
}

module "lb_bank1" {
    source = "../../module/apploadbalancer"

    app_name = "member-portal-bank1"
    vpc_id = "${data.aws_vpc.main.id}"
    security_groups = ["${data.aws_security_group.web.id}"]
    subnet_ids = ["${data.aws_subnet_ids.public.ids}"]
}


resource "aws_route53_record" "bank1" {
  zone_id = "${data.aws_route53_zone.domain.zone_id}"
  name = "www"
  type = "A"
  set_identifier = "bank1"

  weighted_routing_policy {
    weight = "${var.bank1_weight}"
  }

  alias {
    name = "${module.lb_bank1.dns_name}"
    zone_id = "${module.lb_bank1.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "bank1_cname" {
  zone_id = "${data.aws_route53_zone.domain.zone_id}"
  name    = "bank1.www"
  type    = "CNAME"
  ttl     = "60"
  records        = ["${module.lb_bank1.dns_name}"]
}

module "bank1" {
    source = "../../module/node-autoscale"

    app_name = "member-portal-bank1"
    app_version = "${var.bank1_version}"
    app_env_var_filename = "${var.bank1_variables_filename}"
    app_env_var_bucket = "test-ll-env-vars"

    region = "${var.region}"
    aws_ami = "${var.aws_ami}"
    aws_key_name = "${var.aws_key_name}"
    aws_access_key = "${var.aws_access_key}"
    aws_secret_key = "${var.aws_secret_key}"
    instance_type = "${var.instance_type}"

    sumo_access_id = "${var.sumo_access_id}"
    sumo_access_key = "${var.sumo_access_key}"
    sumo_collector_name = "member-portal"

    iam_instance_profile = "${data.aws_iam_instance_profile.test.arn}"
    loadbalancer_id = "${module.lb_bank1.id}"
    subnet_group_ids = ["${data.aws_subnet_ids.public.ids}"]
    security_group_ids = ["${data.aws_security_group.web.id}", "${data.aws_security_group.ssh.id}"]

    docker_image = "${var.bank1_docker_image}"
    docker_port = "${var.bank1_docker_port}"

    min = "2"
    max = "20"
}

module "lb_bank2" {
    source = "../../module/apploadbalancer"

    app_name = "member-portal-bank2"
    vpc_id = "${data.aws_vpc.main.id}"
    security_groups = ["${data.aws_security_group.web.id}"]
    subnet_ids = ["${data.aws_subnet_ids.public.ids}"]
}


resource "aws_route53_record" "bank2" {
  zone_id = "${data.aws_route53_zone.domain.zone_id}"
  name = "www"
  type = "A"
  set_identifier = "bank2"

  weighted_routing_policy {
    weight = "${var.bank2_weight}"
  }

  alias {
    name = "${module.lb_bank2.dns_name}"
    zone_id = "${module.lb_bank2.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "bank2_cname" {
  zone_id = "${data.aws_route53_zone.domain.zone_id}"
  name    = "bank2.www"
  type    = "CNAME"
  ttl     = "60"
  records        = ["${module.lb_bank2.dns_name}"]
}


module "bank2" {
    source = "../../module/node-autoscale"

    app_name = "member-portal-bank2"
    app_version = "${var.bank2_version}"
    app_env_var_filename = "${var.bank2_variables_filename}"
    app_env_var_bucket = "test-ll-env-vars"

    region = "${var.region}"
    aws_ami = "${var.aws_ami}"
    aws_key_name = "${var.aws_key_name}"
    aws_access_key = "${var.aws_access_key}"
    aws_secret_key = "${var.aws_secret_key}"
    instance_type = "${var.instance_type}"

    sumo_access_id = "${var.sumo_access_id}"
    sumo_access_key = "${var.sumo_access_key}"
    sumo_collector_name = "member-portal"

    iam_instance_profile = "${data.aws_iam_instance_profile.test.arn}"
    loadbalancer_id = "${module.lb_bank2.id}"
    subnet_group_ids = ["${data.aws_subnet_ids.public.ids}"]
    security_group_ids = ["${data.aws_security_group.web.id}", "${data.aws_security_group.ssh.id}"]

    docker_image = "${var.bank2_docker_image}"
    docker_port = "${var.bank2_docker_port}"

    min = "2"
    max = "20"
}

