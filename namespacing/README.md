# Namespacing different applications

In the previous example we showed a good pattern for managing different environments with Terraform, so let's build on that pattern with a way to isolate different applications from the core infrastructure. Like in many of the previous examples we will create one Nginx instance for the application, and use the scripts from the modules example as a starting point. Let's use the network module to create our VPC, and then we will show how to namespace the application server away from the core defined network assets. This way changes to the application Terraform scripts do not effect the core network, but still leverage those existing pieces.

We have copied the example.tf, terraform.tfvars, and module folder from the modules example. Next we created a new directory for our application called "application," added a main.tf file inside that directory for the application specific Terraform scripts, and copied in the terraform.tfvars file from the parent directory. By splitting the application from the rest of our Terraform assets we need to run Terraform multiple times to build everything. The application scripts are dependent on the core infrastructure being available, so create the VPC first. From this directory run:

```
terraform init
terraform get
terraform apply
```

With the core VPC created, let's take a look at the application/main.tf file and see how we can add an application to the already created VPC.

We start by declaring our needed variables. We have to declare duplicate variables again since our new directory is effectively a whole new Terraform project.

```
variable "region" {
    default = "us-west-1"
}
variable "ssh_key" {}
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_ami" {
    default = "ami-02eada62"
}
```

Now that the variables are declared, we can leverage Terraform data sources to get info on our existing VPC and subnets, and then use that info to add instances to them. Every Terraform resource can also be a data source. Really the only difference is whether you want to use Terraform to create a resource, or retrieve a resource. All of the decalarations we have used thus far have been to create or modify a resource, but in the case of a data source we are retrieving. Let's start with fetching the VPC data:

```
data "aws_vpc" "main" {
    tags { Name = "Main" }
}
```

Notice that a data source begins with `data` and from there the pattern is the same as a `resource`; there is the resource type ("aws_vpc"), followed by a variable name for the resource ("main"). The other difference for a data source is with the variables inside the defined data source. In the case of a `resource` the variables serve as values for the resource to be created. In the case of a `data` source the variables act as filters for querying that resource type. For the above example we are using the name of our VPC as a filter to get the VPC, retrieving the VPC in AWS with the name "Main," which is what we have defined in the example.tf file for the VPC.

We will also need the subnet ids for the subnets that exist in our VPC, which we can grab with another data source. The below filter will lookup our subnet ids based on the VPC id we previously retrieved.

```
data "aws_subnet_ids" "public" {
    vpc_id = "${data.aws_vpc.main.id}"
}
```

As you can see we are using a specially defined Terraform resource type to fetch our list of subnets. If we were only fetching one subnet, then we could use the same `aws_subnet` resource used to define the subnet, but because we want to retrieve a list of subnets we use the [`aws_subnet_ids`](https://www.terraform.io/docs/providers/aws/d/subnet_ids.html) to return a list.

With these two data sources defined we now have access to our VPC parameters, and the subnet ids to be used in our implementation, so let's define the key, security group, and instances. Since we have two subnets in different AZs we will create two Nginx boxes, one in each subnet, and a load balancer to route the traffic.

```
resource "aws_key_pair" "dev" {
  key_name   = "aws.test"
  public_key = "${file(var.ssh_key)}"
}

resource "aws_security_group" "web" {
  name        = "Web Traffic"
  description = "Allow all inbound traffic from http (80)"
  vpc_id = "${data.aws_vpc.main.id}"

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

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}
```

The above key and security group are not very different from any of the previous examples, the only change is to the `vpc_id` variable of the security group, which now uses our data source to get the VPC id value.

```
resource "aws_elb" "default" {
    name = "Nginx-LB"
    subnets = ["${data.aws_subnet_ids.public.ids}"]
    security_groups = ["${aws_security_group.web.id}"]

    listener {
        instance_port = 80
        instance_protocol = "http"
        lb_port = 80
        lb_protocol = "http"
    }

    health_check {
        healthy_threshold = 2
        unhealthy_threshold = 5
        timeout = 3
        target = "HTTP:80/"
        interval = 30
    }

    cross_zone_load_balancing = true
    idle_timeout = 60
    connection_draining = true
    connection_draining_timeout = 1200
}
```

The load balancer is an AWS classic load balancer, like in the autoscale example, and keeps pretty much the same settings except now the `subnets` parameter gets the list value from the `data.aws_subnet_ids.public` source.

```
resource "aws_instance" "node" {
    count = 2
    ami = "${var.aws_ami}"
    instance_type = "t2.small"
    key_name = "${aws_key_pair.dev.key_name}"
    vpc_security_group_ids = ["${aws_security_group.web.id}"]
    subnet_id = "${element(data.aws_subnet_ids.public, count.index)}"

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

For the instances we are using `count` to create two different instances, and for the subnet_id we use the built-in function `element(list, index)` to retrieve different subnets for the two instances.

```
resource "aws_elb_attachment" "default" {
    count = 2
    elb = "${aws_elb.default.id}"
    instance = "${element(aws_instance.node.*.id, count.index)}"
}
```

The last thing we need to do is attach our instances to the load balancer, which we do with the `aws_elb_attachment` resource. With everything defined we can create our application assets.

```
cd application
terraform init
terraform apply
```

By separating the application assets into a new directory and Terraform project, we can prevent accidental changes to the core infrastructure due to changes in the application Terraform scripts. It's also easy to combine this with multiple directories for managing multiple environments.

Another approach to namespacing our application, which would look very similar to the above example, would be to separate applications into different repos. Then we can leverage source control for finer grained access control to various parts of the infrastructure, which is a very nice benefit when working in larger teams. 