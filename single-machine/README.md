# Create single instance

To get started with Terraform, let's take a very basic example and provision a single machine and security group on AWS, serving up Nginx for testing.

## Topics Covered

- [Creating AWS creds and keys](#creating-AWS-creds-and-keys)
- [Terraform providers](#terraform-providers)
- [Terraform variables](#terraform-variables)
- [Terraform resources](#terraform-resources)
    - [AWS Keypair](#aws-keypair)
    - [AWS Security Group](#aws-security-group)
    - [AWS EC2 Instance](#aws-ec2-instance)
- [Terraform commands](#terraform-commands)

## Creating AWS creds and keys

Assuming you have an AWS account, the first thing you will want to get is a valid access-key and secret-key for accessing AWS resources. Best practices are to setup IAM roles and enable privileges on those roles, but for simplicity we are going to use the access key and secret access key values directly.

We also need to generate a keypair for SSH access to the instance we are going to create.

```shell
ssh-keygen -b 2048 -t rsa -C "aws.test" -f ~/.ssh/aws.test
```

Hit enter to skip the passphrase prompt.

Now with our creds and keypair created we can create our terraform scripts and spin up some infrastructure.

## [Terraform providers](https://www.terraform.io/docs/providers/index.html)

Terraform providers represent the various supported cloud providers, and collect the necessary parameters for terraform to be able to call that specific cloud provider. If you view the [terraform docs on providers](https://www.terraform.io/docs/providers/index.html) you will see that there are numberous cloud platforms supported, including AWS, Google Cloud, Heroku, and Open Stack. For these examples we will be using AWS strictly, but the concepts are easily implemented with other providers as well.

Start by creating a file to add your terraform scripts to. You can name it whatever you want to describe your assets, and give it the .tf file extension. Terraform will pickup any files in the working directory with a .tf extension.

To add an [AWS provider](https://www.terraform.io/docs/providers/aws/index.html) to your terraform file add the following snippet to your tf file:

```
provider "aws" {
  access_key = "youraccesskeyvalue"
  secret_key = "yoursecretkeyvalue"
  region = "us-west-1"
}
```

Okay - so that's pretty simple and straightforward, but obviously we don't want to keep our AWS credentials hard-coded and checked into source control. Enter terraform variables.

## [Terraform variables](https://www.terraform.io/docs/configuration/variables.html)

Terraform supports a number of different variable types to allow you to better abstract away your infrastructure settings, like string, map, and list. To learn more about the different variable types checkout the [terraform variables](https://www.terraform.io/docs/configuration/variables.html) documentation.

### Define a variable

At the top of our terraform script file, let's add the following variable declarations:

```
variable "region" {
  type = "string"
  default = "us-west-1"
}
variable "aws_access_key" {}
variable "aws_secret_key" {}
```

### Access a variable

And now we can implement those variables in our aws provider. Let's replace the hard-coded values with the variable values:

```
provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_access_key}"
  region = "${var.region}"
}
```

### Set a variable

With our variables declared and implemented, we now need to set the variable values for when we run terraform. There are a couple ways we can set a variable value with terraform.

#### By file

To set our variable values in a file create a [terraform.tfvars](terraform.tfvars) file and set the variable values with each entry as a new line in the file. Terraform will automatically pull the values from this file. We can also create separate variable files, and when named with the *.auto.tfvars file extension they will be automatically picked up by terraform as well.

#### By environment variable

It is also possible to set terraform variable values using an environment variable by simply prepending TF_VAR_ to the variable name. For example, we have defined a "region" variable in the above example, so to set this value using an environment variable we can do the following:

```shell
export TF_VAR_region=us-west-1
```

This is a nice way to set highly sensitive variable values you don't want checked into source control. It is important to note that setting the same variable value in a .tfvars file as well will take precedent over the environment variable value.

## [Terraform resources](https://www.terraform.io/docs/configuration/resources.html)

The meat of terraform is in the resources. A resource represents a discrete piece of infrastructure that we want to manage with terraform. Virtually any feature you can use on AWS through the command line or through the web UI is available as a terraform resource.

All resource declarations in terraform follow the basic pattern of `resource "resource_type" "resource_name" {}` where "resouce_type" is the cloud resource supported by terraform which we want to create, and "resource_name" is the custom name we will give that resource to be referenced by other resources.

### AWS Keypair

The first resource that needs to be declared is the ssh key, so that we can ssh into the box we are going to create with terraform.

```
resource "aws_key_pair" "dev" {
  key_name   = "aws.test"
  public_key = "${file(var.ssh_key)}"
}
```

Notice that for this resource we are using a [terraform built-in function](https://www.terraform.io/docs/configuration/interpolation.html#built-in-functions) to read the certificate content in as a string. We will cover the built-in functions in more detail in a later example.

### AWS Security Group

Now we will need to create a security group to expose a couple ports on the instance we are going to create. It is of course possible to create an instance without any security groups, but not very useful. 

Let's create a simple security group which exposes ports 80 for HTTP traffic and 22 for SSH to all clients.

```
resource "aws_security_group" "web" {
  name        = "Web Traffic"
  description = "Allow all inbound traffic from http (80) and SSH traffic"

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
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### [AWS EC2 Instance](https://www.terraform.io/docs/providers/aws/r/instance.html)

With our key and security group declared, let's look at creating a simple [EC2 instance](https://www.terraform.io/docs/providers/aws/r/instance.html) which is going to run Nginx from a docker container.

```
resource "aws_instance" "node" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "m1.small"
    key_name = "${aws_key_pair.dev.key_name}"
    security_groups = ["${aws_security_group.web.name}"]
    associate_public_ip_address = true

    tags {
        Name = "Nginx Example"
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
```

As you can see we need to create a new variable for the AMI id of the image we want to use. In this example we are going to use the Amazon Linux PV AMI version 2017.09.0.20170930, since HVM is only supported within a VPC.

Let's review some of the parameters defined in this instance.

- **instance_type** - This is pretty self-explanatory, but we want to callout that t2 level instances are only available inside a VPC, so for a standalone box example we are going with an m1.small
- **key_name** - The value we provide here is the name of the aws keypair which we created in the earlier keypair declaration. Notice how the value of the previous resource is referenced inside the instance.
- **security_groups** - This parameter expects a list of values, hence the [] to declare the value as a list. This example has only one value, but additional values to a list can be added and separated by a comma. Notice again how we reference the value of our previously declared security group.
- **associate_public_ip_address** - This expects a boolean value and we have added it as the simplest way to give a public ip address to the box we are creating. An alternative and ultimately better method to do this would be to create an [elastic ip](https://www.terraform.io/docs/providers/aws/r/eip.html) and then associate that elastic ip address with the box. The advantage of that route is the box could potentially be recreated and then given the same public address, whereas in this example destroying and recreating the box would result in a new public ip.
- **user_data** - This is the data we will pass to the instance to run on instance creation, commonly used to provision dependencies on the box. Since we are going to use docker to run our services in combination with Amazon Linux, all we are going to do here is install docker and then run the Nginx image on port 80. Another option here would be to use an AMI that has support for docker natively, like CoreOS, and then we can skip the docker install and start steps.

## [Terraform commands](https://www.terraform.io/docs/commands/index.html)

With all of the resources declared it's now possible to use terraform to create the example infrastructure. To initialize the project we need to first run `terraform init`. This will initialize the current directory as a terraform project.

Next let's have terraform analyze what it is going to do when we apply the configuration. This command will print to stdout all the changes which terraform will make on our behalf.

```
terraform plan
```

Because everything we have declared is new and does not already exist on AWS, `terraform plan` will tell us it is going to create 3 new assets. This is very useful to run whenever we make changes to the code so we can preview what changes will occur before they are applied.

To actually create the resources run:

```
terraform apply
```

Pretty amazing right! If you look in the EC2 dashboard for the region you are working you will find the keypair, security group, and EC2 instance has been created for us. To fully verify the stack grab the public IP address of the created instance and load it into your browser. You should get the default Nginx page.

When you are ready to tear-down these items run:

```
terraform destroy
```