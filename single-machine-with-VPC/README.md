## Create single instance inside a VPC

In this example we will be creating the same instance and security groups we created in the [single instance example](https://github.com/afloesch/terraform-examples/tree/master/single-machine), but now we are going to create a custom VPC and add the box to that custom VPC.

Our [example.tf](example.tf) file is pretty much the same from the previous example, except for a few modifications to support adding our security group and instance to the VPC, which we will cover after the VPC setup.

## Topics Covered

- [Working with multiple Terraform files](#working-with-multiple-terraform-files)
- [Terraform resources](#terraform-resources)
    - [AWS VPC](#aws-vpc)
    - [AWS subnet](#aws-subnet)
    - [AWS internet gateway](#aws-internet-gateway)
    - [AWS route table](#aws-route-table)
    - [AWS route table association](#aws-route-table-association)
- [Example.tf changes](#example.tf-changes)

## Working with multiple Terraform files

In the single instance example we declared all of our variables and resources in one file, and because we had very little defined this was not a problem. As our infrastructure grows however, keeping all scripts in one file will become very hard to manage, so for ops and developer sanity Terraform supports breaking up your scripts into multiple files, making it very easy to logically separate different areas of your infrastructure.

To separate our VPC resources from the application, let's create a new file called [vpc.tf](vpc.tf) to store our VPC declarations, and keep using [example.tf](example.tf) for the variables, key, security group, and instance.

## Terraform resources

### [AWS VPC](https://www.terraform.io/docs/providers/aws/r/vpc.html)

To create a VPC resource on Amazon the only required parameter is the IP block and subnet mask we want to launch with in CIDR notation. For some basic information on subnetting checkout [this digital ocean blog article](https://www.digitalocean.com/community/tutorials/understanding-ip-addresses-subnets-and-cidr-notation-for-networking).

```
resource "aws_vpc" "default" {
    cidr_block = "10.0.0.0/16"
}
```

This is the same as the default settings AWS would use if you create a VPC through the web GUI without specifying a CIDR value. It basically strikes a balance between how many individual subnets we can support within the VPC, and how many individual hosts we can have on each subnet.

### [AWS subnet](https://www.terraform.io/docs/providers/aws/r/subnet.html)

With the VPC defined we can now add a subnet for our application server to live in. 

```
resource "aws_subnet" "us-west-1a-public" {
    vpc_id = "${aws_vpc.default.id}"
    cidr_block = "10.0.0.0/24"
    availability_zone = "us-west-1a"
    map_public_ip_on_launch = true

    tags = {
        Name = "Public Subnet"
    }
}
```

- **vpc_id** - The id of the VPC to associate this subnet with.
- **cidr_block** - The ip block and subnet mask of the subnet.
- **availability_zone** - The AWS availability zone of the region we are working in.
- **map_public_ip_on_launch** - Boolean setting on whether to issue public ip addresses to instances created in this subnet. This will replace the associate_public_ip_address parameter we use on our instance since they perform duplicate functions.

### AWS internet gateway

With our VPC and subnet created all we will have is an internal network which we can't reach, so let's expose the subnet we just created with an internet gateway.

```
resource "aws_internet_gateway" "default" {
    vpc_id = "${aws_vpc.default.id}"
}
```

### [AWS route table](https://www.terraform.io/docs/providers/aws/r/route_table.html)

With the internet gateway created and attached to our VPC, we need to create a [route table](http://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/VPC_Route_Tables.html) so the traffic routes properly inside the VPC.

```
resource "aws_route_table" "us-west-1-public" {
    vpc_id = "${aws_vpc.default.id}"

    route {
        cidr_block = "10.0.0.0/24"
        gateway_id = "${aws_internet_gateway.default.id}"
    }

    tags {
        Name = "Public Subnet"
    }
}
```

- **vpc_id** - The id of the VPC to associate the route table with.
- **route** - This is a shortform route declaration as part of the route table itself. It is also possible to create a route using an [aws_route](https://www.terraform.io/docs/providers/aws/r/route.html) resource in terraform as a separate declaration. The route will send all traffic from the internet gateway to the public subnet we previously defined.

### [AWS route table association](https://www.terraform.io/docs/providers/aws/r/route_table_association.html)

Lastly we need to associate our route table with the public subnet so that the routing can execute properly.

```
resource "aws_route_table_association" "us-west-1a-public" {
    subnet_id = "${aws_subnet.us-west-1a-public.id}"
    route_table_id = "${aws_route_table.us-west-1-public.id}"
}
```

### [Example.tf](example.tf) changes

With the VPC infrastructure defined, we need to make a few modifications to our example.tf file to properly create the instance inside the VPC.

The first change to make is to the `aws_security_group`. To create the security group inside the VPC add the `vpc_id` parameter to the aws_security_group:

```
resource "aws_security_group" "web" {
    name        = "Web Traffic"
    description = "Allow all inbound traffic from http (80)"
    vpc_id = "${aws_vpc.default.id}"
    ...
}
```

The second change we need to make is to the `aws_instance`. Instead of using the `security_groups` param and the resource name of our security group, we are going to use the `vpc_security_group_ids` param and specify the id of the security group. 

We also need to specify the `subnet_id` for the subnet we want to launch the instance in. In this case we want to launch the instance in the public subnet we are creating.

Lastly, we are going to drop the `associate_public_ip_address` param since this is now defined on the public subnet.

For example, change from this:

```
resource "aws_instance" "node" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "m1.small"
    key_name = "${aws_key_pair.dev.key_name}"
    security_groups = ["${aws_security_group.web.name}"]
    associate_public_ip_address = true
    ...
}
```

to this:

```
resource "aws_instance" "node" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "t2.small"
    key_name = "${aws_key_pair.dev.key_name}"
    vpc_security_group_ids = ["${aws_security_group.web.id}"]
    subnet_id = "${aws_subnet.us-west-1a-public.id}"
    ...
}
```

With all the necesssary changes made let's see what changes terraform will make for us.

```
terraform plan
```

As you can see terrafrom is going to create 8 new cloud assets for us, so go ahead and apply the changes.

```
terraform apply
```