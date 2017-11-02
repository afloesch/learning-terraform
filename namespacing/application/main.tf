variable "region" {
	default = "us-west-1"
}
variable "ssh_key" {}
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_ami" {
	default = "ami-02eada62"
}

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region = "${var.region}"
}

data "aws_vpc" "main" {
    tags { Name = "Main" }
}

data "aws_subnet_ids" "public" {
    vpc_id = "${data.aws_vpc.main.id}"
}

# import the cert into amazon for accessing the boxes
resource "aws_key_pair" "dev" {
  key_name   = "aws.test"
  public_key = "${file(var.ssh_key)}"
}

# create a security group to expose web traffic ports to public
resource "aws_security_group" "web" {
  name        = "Web Traffic"
  description = "Allow all inbound traffic from http (80)"
  vpc_id = "${data.aws_vpc.main.id}"

  tags {
    Name = "Web Traffic"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

# create application load balancer
resource "aws_elb" "default" {
    name = "Nginx-LB"
    subnets = ["${data.aws_subnet_ids.public.ids}"]
    security_groups = ["${aws_security_group.web.id}"]

    listener {
        instance_port = 80
        instance_protocol = "http"
        lb_port = 80
        lb_protocol = "http"
    }

    health_check {
        healthy_threshold = 2
        unhealthy_threshold = 5
        timeout = 3
        target = "HTTP:80/"
        interval = 30
    }

    cross_zone_load_balancing = true
    idle_timeout = 60
    connection_draining = true
    connection_draining_timeout = 1200
}

# create base boxes to serve application
resource "aws_instance" "node" {
    count = 2
    ami = "${var.aws_ami}"
    instance_type = "t2.small"
    key_name = "${aws_key_pair.dev.key_name}"
    vpc_security_group_ids = ["${aws_security_group.web.id}"]
    subnet_id = "${element(data.aws_subnet_ids.public.ids, count.index)}"

    tags {
        Name = "Nginx Example"
    }

    user_data = <<HEREDOC
    #!/bin/bash
    sudo su
    yum update -y
    yum install -y docker
    service docker start
    docker run -p 80:80 -d nginx
    HEREDOC
}

# attach instances to the load balancer
resource "aws_elb_attachment" "default" {
    count = 2
    elb = "${aws_elb.default.id}"
    instance = "${element(aws_instance.node.*.id, count.index)}"
}