# create VPC for public facing services
resource "aws_vpc" "default" {
	cidr_block = "${var.vpc_block}"
	#lifecycle { prevent_destroy = true }
	tags {
		Name = "${var.name}"
	}
}

# expose VPC with internet gateway
resource "aws_internet_gateway" "default" {
	vpc_id = "${aws_vpc.default.id}"
}

# Routing table for public subnets
resource "aws_route_table" "public" {
	vpc_id = "${aws_vpc.default.id}"

	route {
		cidr_block = "0.0.0.0/0"
		gateway_id = "${aws_internet_gateway.default.id}"
	}

	tags {
		Name = "Public Subnet"
	}
}

# create public subnet in specified azs
resource "aws_subnet" "subnet" {
    count = "${length(var.azs)}"
	vpc_id = "${aws_vpc.default.id}"
	cidr_block = "${element(var.subnet_blocks, count.index)}"
	availability_zone = "${element(var.azs, count.index)}"
	map_public_ip_on_launch = true
    tags {
        Name = "public-subnet"
    }
}

# Routing entry for public subnets
resource "aws_route_table_association" "subnet" {
    count = "${length(var.azs)}"
	subnet_id = "${element(aws_subnet.subnet.*.id, count.index)}"
	route_table_id = "${aws_route_table.public.id}"
}