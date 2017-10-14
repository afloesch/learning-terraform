## Create single instance inside a VPC

In this example we will be creating the same instance and security groups we created in the [single instance example](https://github.com/afloesch/terraform-examples/tree/master/single-machine), but now we are going to create a custom VPC and add the box to that custom VPC.

Our [example.tf](example.tf) file is pretty much the same from the previous example, except for a few modifications to support adding our security group and instance to the VPC, which we will cover after the VPC setup.

## Topics Covered

- Working with multiple Terraform files
- Terraform resources
    - AWS VPC
    - AWS subnet
    - AWS internet gateway
    - AWS routing

## Working with multiple Terraform files

In the single instance example we declared all of our variables and resources in one file, and because we had very little defined this was not a problem. As our infrastructure grows however, keeping all scripts in one file will become very hard to manage, so for ops and developer sanity Terraform supports breaking up your scripts into multiple files, making it very easy to logically separate different areas of your infrastructure.

To separate our VPC resources from the application let's create a new file called [vpc.tf](vpc.tf) to store our VPC declarations, and keep using [example.tf](example.tf) for the variables, key, security group, and instance.

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