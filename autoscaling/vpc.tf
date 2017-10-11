# create VPC for public facing services
resource "aws_vpc" "default" {
	cidr_block = "10.0.0.0/16"
}

# expose VPC with internet gateway
resource "aws_internet_gateway" "default" {
	vpc_id = "${aws_vpc.default.id}"
}

# create public subnet in availability zone us-west-1a
resource "aws_subnet" "us-west-1a-public" {
	vpc_id = "${aws_vpc.default.id}"
	cidr_block = "10.0.0.0/24"
	availability_zone = "us-west-1a"
	map_public_ip_on_launch = true
}

# create public subnet in availability zone us-west-1b
resource "aws_subnet" "us-west-1b-public" {
	vpc_id = "${aws_vpc.default.id}"
	cidr_block = "10.0.1.0/24"
	availability_zone = "us-west-1b"
	map_public_ip_on_launch = true
}

# Routing table for public subnets
resource "aws_route_table" "us-west-1-public" {
	vpc_id = "${aws_vpc.default.id}"

	route {
		cidr_block = "0.0.0.0/0"
		gateway_id = "${aws_internet_gateway.default.id}"
	}

  tags {
    Name = "Public Subnet"
  }
}

# Routing entry for public subnet us-west-1a-public
resource "aws_route_table_association" "us-west-1a-public" {
	subnet_id = "${aws_subnet.us-west-1a-public.id}"
	route_table_id = "${aws_route_table.us-west-1-public.id}"
}

# Routing entry for public subnet us-west-1b-public
resource "aws_route_table_association" "us-west-1b-public" {
	subnet_id = "${aws_subnet.us-west-1b-public.id}"
	route_table_id = "${aws_route_table.us-west-1-public.id}"
}