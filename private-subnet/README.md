# Creating public and private subnets, with bastion host, Nginx, and MySQL

For this next example we are going to setup a VPC with both a public and a private subnet. The public subnet will be exposed directly to the internet with an internet gateway, like in our previous example, and there will also be a private subnet with a NAT gateway to give the private instances access to the internet. This is a common and useful infrastructure pattern for hosting a web server and a database server without exposing the database to external requests.

 We will expand the examples given by Amazon in [VPC scenario 2](http://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/VPC_Scenario2.html) with a few actual boxes in each subnet, as well as a bastion host for SSH access to each box. For the web server we will use nginx again, and for the database we will install MySQL on Amazon Linux.

 While this example does not cover many new terraform topics, it does cover the Amazon VPC scenario in detail, which is a useful pattern for just about any stack, so demonstrating with terraform may provide some value.

 ## Topics Covered

- [Terraform resources](#terraform-resources)
    - [AWS elastic IP](#aws-elastic-ip)
    - [AWS NAT gateway](#aws-nat-gateway)
    - [Resource dependencies](#resource-dependencies)
- Optimizing for production

## Terraform resources

Expanding on the single machine inside a VPC example, let's keep everything we have defined for our public subnet the same, but add another subnet which is private and cannot be reached directly from the internet. It will probably be desireable to give the boxes inside the private subnet access to the internet, so for that we will use an AWS NAT gateway to route web requests from the private subnet back to the box.

### [AWS elasic IP](https://www.terraform.io/docs/providers/aws/r/eip.html)

In order to route to the NAT gateway we need to give it an IP address, so let's create an elastic IP which we will attach to the gateway. The only param we need to set is `vpc`, which specifies whether this IP will be used inside a VPC.

```
resource "aws_eip" "nat" {
    vpc = true
}
```

### [AWS NAT gateway](https://www.terraform.io/docs/providers/aws/r/nat_gateway.html)

With an elastic IP allocated we can create the NAT gateway.

```
resource "aws_nat_gateway" "default" {
  subnet_id = "${aws_subnet.us-west-1a-public.id}"
  allocation_id = "${aws_eip.nat.id}"

  depends_on = ["aws_internet_gateway.default"]
}
```

The only two params required for a NAT gateway are the `subnet_id` to launch the NAT gateway in, and the `allocation_id` for the elastic IP we want to assign to the gateway.

We should create the NAT gateway inside the public subnet, since the public subnet has access to the internet through the internet gateway, and then create a new routing table entry to route traffic from the NAT gateway into our private subnet.

With the `allocation_id` we pass in the elastic IP previously created to assign to our NAT gateway.

### [Resource dependencies](https://www.terraform.io/intro/getting-started/dependencies.html)

The last parameter used in the AWS NAT gateway example is one which is common to *all* terraform resources, `depends_on`. We have not needed this in any of the previous examples, because every resource declared that was dependent on another was referencing the necessary dependency directly in its configuration, so terraform properly sorted out the order for creating our resources. 

In the case of our NAT gateway however, we have something of a dependency on the internet gateway being available, but in the AWS world a NAT gateway has absolutely no dependency on an internet gateway. Without the internet gateway the private subnet clients will not be able to access the internet, so we need to wait for that resource before creating our NAT gateway, which we can tell terraform to do using the `depends_on` variable.