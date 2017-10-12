# Create single instance

To get started with Terraform, let's take a very basic example and provision a single machine and security group on AWS, serving up Nginx for testing.

## Topics Covered

- [Creating AWS creds and keys](#creating-AWS-creds-and-keys)
- [Terraform providers](#terraform-providers)
- [Terraform variables](#terraform-variables)
- [Terraform resources](#terraform-resources)
    - AWS Security Group
    - AWS EC2 Instance

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

And now we can implement those variables in our aws provider:

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

To set our variable values in a file create a [terraform.tfvars](terraform.tfvars) file and set the variable values with each entry as a new line in the file. Terraform will automatically pull the values from this file. It is also possible to create separate variable files, and when named with the *.auto.tfvars file extension they will be automatically picked up by terraform as well.

#### By environment variable

It is also possible to set terraform variable values using an environment variable by simply prepending TF_VAR_ to the variable name. For example, we have defined a "region" variable in the above example, so to set this value using an environment variable we can do the following:

```shell
export TF_VAR_region=us-west-1
```

This is a nice way to set highly sensitive variable values you don't want checked into source control. It is important to note that setting the same variable value in a .tfvars file as well will take precedent over the environment variable value.

## [Terraform resources](https://www.terraform.io/docs/configuration/resources.html)

The meat of terraform is in the resources. A resource represents a discrete piece of infrastructure that we want to manage with terraform. Virtually any feature you can use on AWS through the command line or through the web UI is available as a terraform resource.

The first resource that needs to be declared is the ssh key, so that we can ssh into the box we are going to create with terraform.

```
resource "aws_key_pair" "dev" {
  key_name   = "aws.test"
  public_key = "${file(var.ssh_key)}"
}
```