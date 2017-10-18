variable "region" {
	default = "us-west-1"
}
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "ssh_key" {}
variable "aws_ami" {
	default = "ami-02eada62"
}

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.region}"
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
  vpc_id = "${aws_vpc.default.id}"

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


# create base boxes to serve application
resource "aws_instance" "node" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "t2.small"
    key_name = "${aws_key_pair.dev.key_name}"
    vpc_security_group_ids = ["${aws_security_group.web.id}"]
    subnet_id = "${aws_subnet.us-west-1a-public.id}"

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