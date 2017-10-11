# Create single instance

To get started with Terraform, let's take a very basic example and provision a single machine and security group on AWS, serving up Nginx for testing.

## Topics Covered

- [Creating AWS creds and keys](#Creating-AWS-creds-and-keys)
- Terraform provisioners
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

Just hit enter to skip the passphrase prompt.