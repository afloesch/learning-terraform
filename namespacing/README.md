# Namespacing different applications

In the previous example we showed a good pattern for managing different environments with Terraform, and now let's build on that pattern with a way to isolate different applications from the core infrastructure.

We will use the scripts from the modules example as a starting point. Let's use the network module to create our VPC, and then we will show how to namespace a single application server away from the core defined network assets. This way changes to the application Terraform scripts do not effect the core network, but still leverage those existing pieces.

We have copied the example.tf, terraform.tfvars, and module folder from the modules example. Next we created a new directory for our application called "application," and a main.tf file inside that directory for the application specific Terraform scripts. By splitting the application from the rest of our Terraform assets we need to run Terraform multiple times to build everything. The application scripts are dependent on the core infrastructure being available, so create the VPC first. From this directory run:

```
terraform init
terraform get
terraform apply
```

With the core VPC created, let's take a look at the application/main.tf file and see how we can add an application to the already created VPC.