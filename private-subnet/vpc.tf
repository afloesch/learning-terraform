# create VPC for public facing services
resource "aws_vpc" "default" {
	cidr_block = "10.0.0.0/16"
}

# add internet gateway to VPC
resource "aws_internet_gateway" "default" {
	vpc_id = "${aws_vpc.default.id}"
}

# create public ip address for NAT gateway
resource "aws_eip" "nat" {
    vpc = true
}

# add NAT gateway so private subnets can connect to internet
resource "aws_nat_gateway" "default" {
  allocation_id = "${aws_eip.nat.id}"
  subnet_id = "${aws_subnet.us-west-1a-public.id}"
  depends_on = ["aws_internet_gateway.default", "aws_eip.nat"]
}

# create public subnet in availability zone us-west-1a
resource "aws_subnet" "us-west-1a-public" {
	vpc_id = "${aws_vpc.default.id}"
	cidr_block = "10.0.0.0/24"
	availability_zone = "us-west-1a"
	map_public_ip_on_launch = true
	tags = {
  	Name =  "Public Subnet"
  }
}

# create private subnet in availability zone us-west-1a
resource "aws_subnet" "us-west-1a-private" {
	vpc_id = "${aws_vpc.default.id}"
	cidr_block = "10.0.1.0/24"
	availability_zone = "us-west-1a"
	tags = {
  	Name =  "Private Subnet"
  }
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

# Routing table for private subnets
resource "aws_route_table" "us-west-1-private" {
	vpc_id = "${aws_vpc.default.id}"

	route {
		cidr_block = "0.0.0.0/0"
		nat_gateway_id = "${aws_nat_gateway.default.id}"
	}

  tags {
    Name = "Private Subnet"
  }
}

# Routing entry for public subnet us-west-1a-public
resource "aws_route_table_association" "us-west-1a-public" {
	subnet_id = "${aws_subnet.us-west-1a-public.id}"
	route_table_id = "${aws_route_table.us-west-1-public.id}"
}

# Routing entry for private subnet us-west-1-private
resource "aws_route_table_association" "us-west-1a-private" {
	subnet_id = "${aws_subnet.us-west-1a-private.id}"
	route_table_id = "${aws_route_table.us-west-1-private.id}"
}