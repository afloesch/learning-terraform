# Learning [Terraform](https://www.terraform.io/)

If you aren't very familiar yet with Terraform and what it can do for you, we recommend starting with the series of articles, created by Yevgeniy Brikman on the Gruntwork team, on [why they chose to use Terraform](https://blog.gruntwork.io/why-we-use-terraform-and-not-chef-puppet-ansible-saltstack-or-cloudformation-7989dad2865c), and the advantages in using it. It's an excellent series on the pros and cons of using terraform, and does a great job of explaing the advantages of immutable infrastructure and declarative code. The series also has some nice getting started tips and patterns for organizing your projects.

Terraform is an amazing orchestration tool, but personally we found the practical examples and patterns, both in the documentation, and in various blog articles, to be a little sparse. We simply couldn't find anything that put it all together for us, so there was a fair amount of time spent figuring out how best to stitch everything together in real-world cloud infrastructure with many different applications. This guide attempts to aggregate both our, and the webs', findings on how best to implement your IAC (infrastructure as code) with Terraform.

The examples go from most basic to "most complex" in the order below. The final example within blue-green aggregates everything demonstrated together, so you should start with wherever you are comfortable and familiar with the concepts.

1) Single Machine
2) Single machine inside a VPC
3) VPC with public and private subnets
4) Autoscaling cluster
5) Managing multiple environments
6) Blue/green deployment with Canary support