# Create single instance

To get started with Terraform, let's take a very basic example and provision a single machine and security group on AWS, serving up Nginx for testing.

## Topics Covered

- [Creating AWS creds and keys](#Creating-AWS-creds-and-keys)
- [Terraform providers](#Terraform-providers)
- Terraform variables
- Terraform resources
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

To add an [AWS provider](https://www.terraform.io/docs/providers/aws/index.html) to your terraform file add the following snippet as defined by the terraform docs to your tf file:

```
provider "aws" {
  access_key = "youraccesskeyvalue"
  secret_key = "yoursecretkeyvalue"
  region = "us-west-1"
}
```

Okay - so that's pretty simple and straightforward, but obviously we don't want to keep our AWS credentials hard-coded and checked into source control. Enter terraform variables.

## [Terraform variables](https://www.terraform.io/docs/configuration/variables.html)