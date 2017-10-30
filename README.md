# Learning [Terraform](https://www.terraform.io/)

If you aren't very familiar yet with Terraform and what it can do for you, we recommend starting with the series of articles, created by Yevgeniy Brikman on the Gruntwork team, on [why they chose to use Terraform](https://blog.gruntwork.io/why-we-use-terraform-and-not-chef-puppet-ansible-saltstack-or-cloudformation-7989dad2865c), and the advantages in using it. It's an excellent series on the pros and cons of using terraform, and does a great job of explaing the advantages of immutable infrastructure and declarative code. The series also has some nice getting started tips and patterns for organizing your projects.

Terraform is an amazing orchestration tool, but personally we found the practical examples and patterns, both in the documentation and in various blog articles, to be a little sparse. We simply couldn't find anything that put it all together for us, so there was a fair amount of time spent figuring out how best to stitch everything together in real-world cloud infrastructure with many different applications. This guide attempts to aggregate both our, and the webs', findings on how best to implement your IAC (infrastructure as code) with Terraform.

The examples generally progress from most basic to "most complex" in the order below. The final example within blue-green aggregates everything demonstrated together, so you should start wherever you are comfortable and familiar with the concepts.

1) [Single machine](single-machine/)
2) [Single machine inside a VPC](single-machine-with-VPC/)
3) [VPC with public and private subnets](private-subnet/)
4) [Autoscaling cluster](autoscaling/)
5) [Modules](modules/)
6) [Managing multiple environments](multiple-environments/)
7) Namespacing different applications
8) Blue/green deployment with Canary support

We have avoided using a separate configuration tool like [Chef](https://www.chef.io/chef/), [Ansible](https://www.ansible.com/), or [Puppet](https://docs.puppet.com/puppet/) to provision the machines, and have instead substituted [Docker](https://www.docker.com/) to accomplish most of the machine provisioning tasks. We made this choice both to keep the examples simple, and because eliminating those pieces from the stack removes any dependency on those tools. It would be fairly trivial to layer any of these tools on-top of Terraform for the provisioning work if your stack requires it, but the simplicity of Terraform and Docker alone is very compelling, and lends itself well to an immutable infrastructure pattern.