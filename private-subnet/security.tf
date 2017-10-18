# create a security group to expose web traffic ports to public
resource "aws_security_group" "public" {
  name        = "Public subnet hosts"
  description = "Allow all inbound traffic from the public subnet hosts"
  vpc_id = "${aws_vpc.default.id}"

  tags {
    Name = "All Traffic"
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["${aws_subnet.us-west-1a-public.cidr_block}"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web" {
  name        = "Web Traffic"
  description = "Allow all inbound traffic from http (80) and SSH from the bastion host"
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
    cidr_blocks = ["${aws_subnet.us-west-1a-public.cidr_block}"]
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