# [Terraform modules](https://www.terraform.io/docs/modules/index.html)

In all of our previous examples we have defined all Terraform resources directly in individual Terraform files, but we can improve on this implementation through the use of modules. Terraform modules give us the means to abstract away our resource declarations and then re-use those modules in multiple places.

Let's take the VPC and public subnets used in our previous example, and refactor them into a custom module which we can use to create our VPC and subnets more flexibly.

## Topics covered

- [Creating modules](#creating-modules)
    - [Built-in functions](#built-in-functions)
    - [Meta-parameters](#meta-parameters)
    - [Outputs](#outputs)
- [Using modules](#using-modules)
    - [Module sources](#module-sources)

## [Creating modules](https://www.terraform.io/docs/modules/create.html)

We recommend starting with the Terraform documentation on [creating a module](https://www.terraform.io/docs/modules/create.html). It explains the features and some best practices for creating modules which can be quickly understood. We strongly encourage following the Terraform recommended pattern for creating a module with a [main.tf](main.tf), a [variables.tf](variables.tf), and an [outputs.tf](outputs.tf) file for consistency. This will make it much easier for other team members to understand the module and its requirements.

Following that pattern, let's create a module directory to keep our VPC module in, and a sub-directory in the module directory called network. This is where we will define our VPC. Inside the network folder we need a main.tf file, a variables.tf file, and an outputs.tf file.

- main.tf is where we will define the aws resources.
- variables.tf is where will define all the module variables needed.
- outputs.tf is where we will define the variables exported from the module.

Let's start with the content in [main.tf](main.tf) and define the resources we need.

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

The VPC, internet gateway, and route table look very much like the previous examples for creating a VPC. Really the only difference is the addition of the `name` variable so that we can assign a sensible name to the VPC we are creating in AWS, and a `vpc_block` variable for the VPC cidr block so that we can reuse the module to define multiple VPCs. The `vpc_block` parameter is just a string, but we will use that value and pass it into the VPC resource. Here's where we run into some problems with declarative versus procedural code. Becuase Terraform is declarative there is no way for us to do any kind of validation or custom error handling, so if the `vpc_block` variable gets a value which is not valid CIDR notation then creation of the VPC will fail. Terraform throws an error of course, but we have no ability to check for this condition or present a custom error message which might help the developer. We haven't found this to be a very big problem in practice however, since the error that comes back from AWS is displayed.

The subnet and route table association defined above make use of some new Terraform built-in functions to accomplish something like a loop. Since Terraform is declarative, not a procedural langauge, simple programming tasks like a for loop cannot be created using a typical procedural approach, but that's okay because the Terraform built-in functions allow us to accomplish the same task in another way.

### [Built-in functions](https://www.terraform.io/docs/configuration/interpolation.html#built-in-functions)

In every example so far we have used the Terraform [`file(path)`](https://www.terraform.io/docs/configuration/interpolation.html#file-path-) built-in function to pull a local certficate and use it for SSH access to the instances created, but there are many other supported functions available to us. Read through the Terraform docs on [built-in functions](https://www.terraform.io/docs/configuration/interpolation.html#built-in-functions) and you will find many useful functions for various tasks, and when used together can create some fairly dynamic declarations, but in the above example we are using `length(list)` and `element(list, index)`.

- **length(list)** - Return the length of the given list.
- **element(list, index)** - Return the list item at the given index position.

### [Meta-parameters](https://www.terraform.io/docs/configuration/resources.html#meta-parameters)

These two functions alone won't get the job done for us, and in fact, the only reason they are useful is due to another Terraform meta-parameter - which are available to all Terraform resources - `count`.

We have used some of these meta-parameters already. `lifecycle` and `depends_on` for example, are two more meta-parameters which were used in some of the previous examples.

For this module we only want to expose the ability to create one VPC when the module is invoked, so our `vpc_block` variable is a single value string type. But, we also want to support multiple availability zones, and subnets inside the VPC, and ideally we should dynamically support as many as are specified in the module variables. Since our goals are one VPC with dynamic AZs and subnets, let's create two new list variables to collect these values; `azs` and `subnet_blocks`.

With these new variables created, let's look at how the subnets are defined:

```
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
```

- **count** - The number of resources to create. *Note: Not supported for creating multiple modules*

The `count` value we have specified is for the total number of availability zones defined in the `azs` variable. This way Terraform will create one subnet for every availability zone specified in the variable list. 

The `cidr_block` and `availability_zone` variables are where we are going to use the `element(list, index)` function to finish our "loop". As Terraform creates the number of resources for the specified count, it makes a `count.index` value available, which we will use along with the `element` function to reference each item in our variable lists. We pass the full list variable in as the list parameter, and the count.index value as the index parameter, which will cause Terraform to create one subnet for each of our set availability zones, and use that same index position to get the subnet CIDR. 

This means our `azs` list needs the same number of items as the `subnet_blocks` list, and because we are using one indexing variable with two lists we have created a potential problem again, that could be addressed in procedural code, but not with Terraform's declarative style. This implementation requires the number of subnets defined to equal the number of availability zones, but we aren't and can't do any specific check for this case. It's not perfect for sure, but it's also not hard to sort-out, and arguably nicer to look at than many Ruby implementations you will see.

We will use a very similar pattern to define the route table associations, but in this case we don't have a potential bug with mismatching list lengths:

```
resource "aws_route_table_association" "subnet" {
    count = "${length(var.azs)}"
	subnet_id = "${element(aws_subnet.subnet.*.id, count.index)}"
	route_table_id = "${aws_route_table.public.id}"
}
```

We now have everything for our VPC defined in our main.tf file of the network module, so to follow the prescribed Terraform pattern let's create a variables.tf file and declare all the module specific variables there. There aren't many to define, but by putting them all into a separate file it makes it very quick and easy for other team members to understand how to implement the module.

### Outputs

The last useful piece to implement when defining a module is to export certain variables, so that those variables can be used by other Terraform resources or modules to build out the rest of the infrastructure.

Create an [outputs.tf](outputs.tf) file and add the following declarations:

```
output "vpc_id" {
    value = "${aws_vpc.default.id}"
}

output "public_subnet_ids" {
  value = ["${aws_subnet.subnet.*.id}"]
}
```

So what is this doing? Let's start with the `vpc_id`. The module is returning a variable called `vpc_id`, and the value of that variable will be set to the id of the VPC created by the module. This will allow us to easily reference that value in other resources. For example, if we want to create new security groups within the VPC, we can reference the `vpc_id` module value which is exported:

```
module "network" {
    source = "./module/network"

    name = "Main"
    vpc_block = "10.0.0.0/16"
    subnet_blocks = ["10.0.0.0/24" , "10.0.1.0/24"]
    azs = ["us-west-1a", "us-west-1b"]
}

resource "aws_security_group" {
    name = "Example"
    vpc_id = "${module.network.vpc_id}"
    ...
}
```

As you can see it's very easy to access the exported variables we set in other resources.

So what's with the * in `public_subnet_ids`? Because we are using the count meta-parameter to create our subnets, we are going to get one or more of them, which means we may have multiple subnet ids, one for each subnet. To handle this we put [] around the exported value to declare it as a list, and the * syntax tells Terraform to iterate over the available values and add them to the list. If we are using two AZs and creating two subnets, this statement will evaluate to `["aws_subnet.subnet.0.id", "aws_subnet.subnet.1.id"]`.

Now our network module returns the id of the VPC, and a list of all subnet ids so that we can use them in other resources.

## [Using modules](https://www.terraform.io/docs/modules/usage.html)

Having a defined module is great, but now we need to implement the module to actually create something with Terraform. Move up from the module directory and create an [example.tf](example.tf) file in the base modules folder. Inside example.tf put the following content:

```
variable "region" {
	default = "us-west-1"
}
variable "aws_access_key" {}
variable "aws_secret_key" {}

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.region}"
}

module "network" {
    source = "./module/network"

    name = "Main"
    vpc_block = "10.0.0.0/16"
    subnet_blocks = ["10.0.0.0/24" , "10.0.1.0/24"]
    azs = ["us-west-1a", "us-west-1b"]
}
```

To implement our module we use the same variables and provider from the previous examples, but for the actual VPC now we reference the network module and let it define our VPC. 

### [Module sources](https://www.terraform.io/docs/modules/sources.html)

The `source` variable allows us to specify modules from various locations. In this example we are simply referencing the module through the local file system, but Terraform supports many other sources for a module, like the Terraform registry or GitHub. The value of source tells Terraform where to find the module, and to fetch the latest version of the module it is necessary to run the command:

```
terraform get
```

It is safe to run `terraform get` multiple times, like `terraform init`, and it is necessary to run get anytime a module is changed, or a new module is implemented.

Now we can view the Terraform plan

```
terraform init
terraform plan
```

and build the infrastructure.

```
terraform apply
```