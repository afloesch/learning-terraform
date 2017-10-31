# Managing multiple environments with Terraform

All examples thus far have been simplified deployments with only one environment, but in the real world we will need to create multiple environments for testing purposes. The number of environments your project needs is not a topic we will discuss here (this "simple" decision has many choices and spawns much debate), so let's just assume you need the ability to manage multiple environments.

There are three different possible approaches to manage multiple environments with Terraform, and which one you choose will depend largely on the size of your project. We will demo the directory option in this example, and describe the basics of the other two.

## Options

1) [Directories](#directories)
2) [Repos](#repos)
3) [Terraform workspaces](#workspaces)

## Directories

Using directories to manage multiple environments is great as long as the project is not too large, and should work best out of the three options for most teams or businesses. What do we mean by work best? It is the easiest option to understand and start working with, and also minimizes the risk of destroying vital infrastucture due to a mistake.

Let's explore this option by building on the previous modules example. We will use the network module we just created, but implement it twice, once for a stage environment, and once for a production environment. To manage the different environments all we will do is create a directory per environment, in this case one directory for stage and one directory for prod.

In the stage and production directories all we have done is copy the terraform.tfvars file and the example.tf file from the modules example, with a couple small changes. Let's look at stage:

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
    source = "../module/network"

    name = "Stage"
    vpc_block = "10.0.0.0/16"
    subnet_blocks = ["10.0.0.0/24" , "10.0.1.0/24"]
    azs = ["us-west-1a", "us-west-1b"]
}
```

We reference the module source in a new location now that we have a directory for stage, so we update the `source` path, and also explicitly set the `name` to Stage. This way when looking at our VPCs in the AWS console we can easily tell what each VPC is for.

Now when we want to create or make changes to particular environment infrastructure, all we need to do is change to that directory and execute the terraform changes within that directory. The required changes will only be applied to that environment, making it safer and easier to test changes through the stack.

```
cd stage
terraform init
terraform get
terraform apply
```

The most important point on this pattern is it's very easy for other team members to understand. Every single piece of IAC is kept in one place - checked into one repo. All modules, all resources, all variables; all in one place. The only thing a team member really needs to know is how Terraform works, and then the entire infrastructure is fairly easily grasped from the Terraform scripts (scripts is a bad word choice for this we know but sounds better than "declarations").

Every change gets checked into source control, and thus source control acts as something of a log of infrastructure changes. A side benefit of this is source control makes it very easy to roll-back changes and apply them with Terraform.

This approach will scale fairly well when combined with the namespacing technique we will show in the next example, but if you are managing enterprise level infrastructure with Terraform you might find the project gets a little messy managing it all in one repo. A typical enterprise environment is simply going to have far too much infrastructure, and in various places, to ideally manage it all with one Terraform repo. You certainly could manage it all with this pattern, but the size of the project will start getting prohibitively difficult to work with. A slightly better approach for very large enterprise infrastructure is to use multiple repos, probably in combination with this pattern.

## Repos

To facilitate splitting our Terraform project into multiple repos we need to move any modules into separate repos, so that various IAC repos can pull them in as needed. Then we can identify logical demarcations between our infrastructure to live in separate repos. 

For example, let's say we have an enterprise business with two completely different application stacks for different products. One stack uses Java and MySQL, while another stack uses Node.js and MongoDB. It would be trivial, and quite a bit more pleasant to read through, to define each stack in two different repos, completely segregated from one another. This way changes to one stack have no possibility of effecting the other stack.

This approach becomes slightly more difficult if there are assets which are shared between the two stacks, but we will show a technique for addressing this problem in the namespacing different applications example.

## [Workspaces](https://www.terraform.io/docs/state/workspaces.html)

*Disclaimer: We would not recommend using Terraform workspaces. We are covering it here for your edification and to present the reasons for avoiding it.*

Terraform describes a workspace as simply "a named container for Terraform state. With multiple workspaces, a single directory of Terraform configuration can be used to manage multiple distinct sets of infrastructure resources." Cool, sounds exactly like what we want to do here, so let's try a practical example.

To list all of the current workspaces:

```
terraform workspace list
```

As you can see we have one workspace defined called default. Let's create a new workspace:

```
terraform workspace new stage
```

When creating a new workspace Terraform tells us "you're now on a new, empty workspace. Workspaces isolate their state,
so if you run `terraform plan` Terraform will not see any existing state
for this configuration." This means that any inrastructure created with the default workspace will not be seen by the stage workspace, so if we apply the changes on the stage workspace we will get a completely separate VPC in AWS. 

While it is ideal that we have completely segragated infrastructure using this model, going with a workspace to do the segragation creates a pretty major issue. We have no capability to support differences between separate environments, and keep those differences clearly kept in source control. All of the workspace state is kept in the terraform.state file, which you have probably noticed when creating any infrastructure with terraform, and while you could potentially check the state file into source control, this is not a best practice because any changes to infrastructure would then need to be checked in after the push, and also because there is no support for state locking through source control. Terraform only supports state locking when hosting with Consul or S3 (we will talk more about remote state in the blue/green deployment example). 

For example, let's say we wanted to create stage with smaller instances than production. If we used a Terraform workspace to accomplish this we would probably start with production first, apply that, then create a stage workspace, make the desired instance size changes, and then apply those changes. Now our Terraform scripts are left with the stage instance settings checked in, and the production settings only live in the state file. Either way we go we are left with one environment where the actual settings are only set in the terraform.state file, and nowhere in the explicitly defined scripts.

Having the state for ALL environments explicitly checked in is a much safer approach.