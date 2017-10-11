provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "us-west-1"
}

# import the cert into amazon for accessing the boxes
resource "aws_key_pair" "dev" {
  key_name   = "aws.test"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCqTct2kzoI8GR008xizhsPfg+lbnZLWlxxSBP5nu7gm0KT3W3e+wdNzoQU21f6B/PW1YAVShJZP7I/OIXLQ82bW0PnFWxzXi+f9bz+ETmiIgKzaPOEP6W2IHyygHHc6Wy5OD6aLP5yjRJcvoKJXLp2C1wvviJjsvY8+c9g7Nk1F40/MSR4QqBE+mX4QgF1saTBKwLgOrLlqgYgrDnlmi+x4837f4W1BfPT/ruFGkqhRXG2IgonSEbNtL3XZ1tuzod7CCyjyKQ83vy8sXn/U/j3t3kId4lh5JlCPO+Q67aAK1c0oAvDos6JVtmofWT14Ud+2oOcD5x4Xi9i0Z5SzwXh andrew.loesch@C02Q9FEKG8WN-L"
}

# create a security group to expose web traffic ports to public
resource "aws_security_group" "all" {
  name        = "All Traffic"
  description = "Allow all inbound and outbound traffic"
  vpc_id = "${aws_vpc.default.id}"

  tags {
    Name = "All Traffic"
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

# create a security group to expose web traffic ports to public
resource "aws_security_group" "bastion" {
  name        = "SSH Traffic"
  description = "Allow only ssh traffic and all outbound traffic"
  vpc_id = "${aws_vpc.default.id}"

  tags {
    Name = "SSH"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

# create bastion host to access application boxes
resource "aws_instance" "bastion" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "t2.micro"
    key_name = "${var.aws_key_name}"
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

# create base box to serve application
resource "aws_instance" "node" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "t2.micro"
    key_name = "${var.aws_key_name}"
    vpc_security_group_ids = ["${aws_security_group.all.id}"]
    subnet_id = "${aws_subnet.us-west-1a-private.id}"
    depends_on = ["aws_nat_gateway.default"]
    tags {
        Name = "Node"
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