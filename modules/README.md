# [Terraform modules](https://www.terraform.io/docs/modules/index.html)

In all of our previous examples we have defined all Terraform resources directly in individual Terraform files, but we can improve on this implementation through the use of modules. Terraform modules give us the means to abstract away our resource declarations and then re-use those modules in multiple places.

Let's take the VPC and public subnets used in our previous example, and refactor them into a custom module which we can use to create our VPC and subnets more flexibly.

## Topics covered

- [Creating modules](#creating-modules)
    - [Built-in functions](#built-in-functions)
    - [Meta-parameters](#meta-parameters)
- Using modules
    - Module sources

## [Creating modules](https://www.terraform.io/docs/modules/create.html)

We recommend starting with the Terraform documentation on [creating a module](https://www.terraform.io/docs/modules/create.html). It explains the features and some best practices for creating modules which can be quickly understood. We strongly encourage following the Terraform recommended pattern for creating a module with a main.tf, a variables.tf, and an outputs.tf file for consistency. This will make it much easier for other team members to understand the module and its requirements.

Following that pattern, let's create a module directory to keep our VPC module in, and a sub-directory in the module directory called network. This is where we will define our VPC. Inside the network folder we need a main.tf file, a variables.tf file, and an outputs.tf file.

- main.tf is where we will define the aws resources.
- variables.tf is where will define all the module variables needed.
- outputs.tf is where we will define the variables exported from the module.

Let's start with the content in main.tf and define the resources we need.

```
resource "aws_vpc" "default" {
	cidr_block = "${var.vpc_block}"

	lifecycle { prevent_destroy = true }

	tags {
		Name = "${var.name}"
	}
}

resource "aws_internet_gateway" "default" {
	vpc_id = "${aws_vpc.default.id}"
}

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

resource "aws_route_table_association" "subnet" {
    count = "${length(var.azs)}"
	subnet_id = "${element(aws_subnet.subnet.*.id, count.index)}"
	route_table_id = "${aws_route_table.public.id}"
}
```

The VPC, internet gateway, and route table look very much like the previous examples for creating a VPC. Really the only difference is the addition of the `name` variable so that we can assign a sensible name to the VPC we are creating in AWS, and a `vpc_block` variable for the VPC cidr block so that we can reuse the module to define multiple VPCs.

The subnet and route table association defined above make use of some new Terraform built-in functions to accomplish something like a loop. Since Terraform is declarative, not a procedural langauge, simple programming tasks like a for loop cannot be created using a typical procedural approach, but that's okay because the Terraform built-in functions allow us to accomplish the same task in another way.

### [Built-in functions](https://www.terraform.io/docs/configuration/interpolation.html#built-in-functions)

In every example so far we have used the Terraform [`file(path)`](https://www.terraform.io/docs/configuration/interpolation.html#file-path-) built-in function to pull a local certficate and use it for SSH access to the instances created, but there are many other supported functions available to us. Read through the Terraform docs on [built-in functions](https://www.terraform.io/docs/configuration/interpolation.html#built-in-functions) and you will find many useful functions for various tasks, but in the above example we are using `length(list)` and `element(list, index)`.

- **length(list)** - Return the length of the given list.
- **element(list, index)** - Return the list item at the given index position.

### [Meta-parameters](https://www.terraform.io/docs/configuration/resources.html#meta-parameters)

These two functions alone won't get the job done for us, and in fact, the only reason they are useful is due to another Terraform meta-parameter, which are available to all Terraform resources, `count`.

We have used some of these meta-parameters already. `lifecycle` and `depends_on` for example, are two more meta-parameters which were used in some of the previous examples.

- **count** - The number of resources to create.