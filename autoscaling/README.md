# Create autoscaling cluster

In this example we are going to pair-back the network resources a little bit and only create a public subnet for our hosts, but we will create two public subnets in different availability zones and load balance across the AZs for high availability. For the application we will use Nginx again.

## Topics Covered

- [Terraform resources](#terraform-resources)
    - [AWS ELB](#aws-elb)
    - [AWS load balancer stickiness policy](#aws-load-balancer-stickiness-policy)
    - [AWS launch configuration](#aws-launch-configuration)
    - AWS autoscaling group
    - AWS autoscaling policy
    - AWS cloudwatch metric alarm

## Terraform resources

Let's create a couple new variables to improve the resource names for the assets created on AWS. Add `app_name` and `app_version` to the top of the autoScale.tf file to descriptively name all of our AWS resources.

### [AWS ELB](https://www.terraform.io/docs/providers/aws/r/elb.html)

Since we are going to create an autoscaling cluster the first item we will need is a load balancer to route the traffic to the cluster hosts. For this example we will setup a classic AWS load balancer to proxy the requests.

```
resource "aws_elb" "default" {
  name = "${var.app_name}"
  subnets = ["${var.subnet_ids}"]
  security_groups = ["${var.security_groups}"]

  lifecycle { prevent_destroy = true }

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
  idle_timeout = 300
  connection_draining = true
  connection_draining_timeout = 1200
}
```

- **lifecycle** - This variable, like `depends_on`, is available to all terraform resources. We use the `prevent_destroy` option on the load balancer because this is going to be the main entry point into our application, and for any future terraform changes we want to be absolutely certain not to destroy the load balancer to avoid longer down times in the event of a deployment mistake. Worst case scenario if the load balancer never goes down is there are no healthy hosts to route traffic to, so if we simply add some hosts into the ELB everything will be back to normal. If, on the other hand, we destroy the ELB, then we will also have to change DNS settings to point our domain to the new ELB, and DNS caching will create an issue on some client machines if setup with a traditional A or CNAME record. This potential problem can also be mitigated, if using AWS route53 as the DNS provider, by creating an ALIAS record which is resolved internally to AWS. With an ALIAS record you alleviate any DNS caching issues, but still need to update the DNS record to point to the new ELB.
- **listener** - Define the port mappings for the load balancer to the application servers. In this case we will setup only one listner for http traffic on port 80, and then route that traffic back to the application servers also over 80 and using http. In a production environment you would also probably want to setup a listener for https and attach a valid certificate to the load balancer.
- **health_check** - The health check we want the ELB to perform to determine if a node in the cluster is in/out of service. The ELB will not route any traffic to unhealthy hosts.
- **cross_zone_load_balancing** - Boolean parameter to specify whether the hosts will be across multiple availability zones.
- **idle_timeout** - The amount of time in seconds which the ELB will allow an idle connection to stay open between the load balancer and the host. Default value is 60 seconds.
- **connection_draining** - Boolean parameter to specify if active connections from a user to a host in the cluster should gracefully drain before destroying the host.
- **connection_draining_timeout** - The maximum amount of time to wait in seconds for a client connection to a host to disconnect. A good approach here would be to set this value a little longer than the application session (assuming the application has a session), so that users active on a box in the cluster are able to finish their activity before the host gets removed from the ELB. The default value is 300 seconds. Without setting this value carefully we might create a scenario where a user's browser can't find the server in the middle of their usage due to an infrastructure change. By carefully setting this value we can ensure that active users aren't simply cutoff in the middle of their session due to ops changes.

### [AWS load balancer stickiness policy](https://www.terraform.io/docs/providers/aws/r/lb_cookie_stickiness_policy.html)

This piece is definitely optional, and might not be desirable depending on the application architecture, but it might be necessary to keep a user pinned to a single server in the cluster in the event their session data is not available on all the hosts. If you are using a cookie to manage all of your session info it doesn't matter, but let's say you went with a docker model with a redis container and an application container on every host, where the application container uses the local redis container to store some session info. In this case it will be important to pin the user to the same server, which we can do with a stickiness policy.

```
resource "aws_lb_cookie_stickiness_policy" "default" {
  name = "http-sticky-policy"
  load_balancer = "${aws_elb.default.id}"
  lb_port = 80
  cookie_expiration_period = 1200
}
```

### [AWS launch configuration](https://www.terraform.io/docs/providers/aws/r/launch_configuration.html)

The AWS launch configuration is a lot like an AWS instance. It's the configuration AWS will use for adding machines to the cluster, so we are defining many machines instead of just one.

```
resource "aws_launch_configuration" "default" {
    image_id = "${var.aws_ami}"
    instance_type = "t2.small"
    name = "${var.app_name}"
    key_name = "${var.aws_key_name}"
    security_groups = ["${aws_security_group.web.id}", "${aws_security_group.ssh.id}"]

    lifecycle {
      create_before_destroy = true
    }

    user_data = <<HEREDOC
    #!/bin/bash
    sudo su
    yum update -y

    yum install perl-Switch perl-DateTime perl-Sys-Syslog perl-LWP-Protocol-https -y
    curl http://aws-cloudwatch.s3.amazonaws.com/downloads/CloudWatchMonitoringScripts-1.2.1.zip -O
    unzip CloudWatchMonitoringScripts-1.2.1.zip
    rm CloudWatchMonitoringScripts-1.2.1.zip
    cd aws-scripts-mon
    echo 'AWSAccessKeyId="${var.aws_access_key}"' >> aws.conf
    echo 'AWSSecretKey="${var.aws_secret_key}"' >> aws.conf
    (crontab -l ; echo "*/1 * * * * ~/aws-scripts-mon/mon-put-instance-data.pl --mem-used-incl-cache-buff --mem-util --disk-space-util --disk-path=/ --from-cron")| crontab -

    yum install -y docker
    service docker start
    docker run -p 80:80 -d ${var.docker_image}
    HEREDOC
}
```

As you can see the `aws_launch_configuration` looks an awful lot like the `aws_instance` which we have used in previous examples, with a few small modifications. The first big change is the addition of the terraform [lifecycle](https://www.terraform.io/docs/configuration/resources.html#lifecycle) parameter which is available to all terraform resources. The lifecycle defined in the above example does little to help us here, since we aren't actually destroying and rebuilding any infrastructure, only building new, but in a production world, where you would want to bring up new instances and remove the old, this parameter becomes very important to tell terraform to create any new assets before destroying the old ones. This will prevent any down-time of the service when new boxes are being created by terraform changes.

The second major change is to the machine provisioning in `user_data`. We have added a whole block of bash scripts to [setup Cloudwatch monitoring](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/mon-scripts.html) on the cluster hosts. Out-of-the-box the only metrics which Cloudwatch can access are around requests and CPU usage. If we want to get disk or memory usage stats on the individual hosts then its necessary to run a cron job which reports those metrics up to Cloudwatch. This chunk of scripts is a little ugly for sure, so we will show another approach using docker in the blue/green example.

### AWS autoscaling group

With the launch configuration defined, we can now create an autoscaling group which will utilize 

```
resource "aws_autoscaling_group" "default" {
    name = "${var.app_name}-${var.app_version}"
    max_size = 50
    min_size = 2
    min_elb_capacity = 2
    launch_configuration = "${aws_launch_configuration.default.name}"
    health_check_type = "ELB"
    load_balancers = ["${aws_elb.default.id}"]
    vpc_zone_identifier = ["${aws_subnet.us-west-1a-public.id}", "${aws_subnet.us-west-1b-public.id}"]
    termination_policies = ["OldestInstance"]

    lifecycle {
      create_before_destroy = true
    }

    tag {
        key = "Name"
        value = "${var.app_name}-${var.app_version}"
        propagate_at_launch = true
    }
}
```