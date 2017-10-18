variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "ssh_key" {}
variable "aws_ami" {
	default = "ami-3a674d5a"
}

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "us-west-1"
}

# import the cert into amazon for accessing the boxes
resource "aws_key_pair" "dev" {
  key_name   = "aws.test"
  public_key = "${file(var.ssh_key)}"
}

# create bastion host to access application boxes
resource "aws_instance" "bastion" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "t2.micro"
    key_name = "${aws_key_pair.dev.key_name}"
    vpc_security_group_ids = ["${aws_security_group.bastion.id}"]
    subnet_id = "${aws_subnet.us-west-1a-public.id}"
    tags {
        Name = "Bastion"
    }
}

# create public ip address for bastion host so that if we recreate the bastion host the ip doesn't change
resource "aws_eip" "bastion" {
    instance = "${aws_instance.bastion.id}"
    vpc = true
}

# create nginx application
resource "aws_instance" "node" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "t2.micro"
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

resource "aws_instance" "db" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "t2.micro"
    key_name = "${aws_key_pair.dev.key_name}"
    vpc_security_group_ids = ["${aws_security_group.public.id}"]
    subnet_id = "${aws_subnet.us-west-1a-private.id}"
    depends_on = ["aws_nat_gateway.default"]

    tags {
        Name = "MySQL"
    }

    user_data = <<HEREDOC
    #!/bin/bash
    sudo su
    yum update -y
    yum install -y mysql57-server
    service mysqld start
    HEREDOC
}