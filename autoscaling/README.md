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

Since we are going to create an autoscaling cluster the first item we will need is a load balancer to route the traffic to the cluster hosts. For this example we will setup a classic AWS load balancer to proxy the requests to.

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
  idle_timeout = 60
  connection_draining = true
  connection_draining_timeout = 1200
}
```

- **lifecycle** - This variable, like `depends_on`, is available to all terraform resources. We use the `prevent_destroy` option on the load balancer because this is going to be the main entry point into our application, and for any future terraform changes we want to be absolutely certain not to destroy the load balancer to avoid longer down times in the event of a deployment mistake. Worst case scenario if the load balancer never goes down is there are no healthy hosts to route traffic to, so if we simply add some hosts into the ELB everything will be back to normal. If, on the other hand, we destroy the ELB, then we will also have to change DNS settings to point our domain to the new ELB, and DNS caching will create an issue on some client machines if setup with a traditional A or CNAME record. This potential problem can also be mitigated, if using AWS route53 as the DNS provider, by creating an ALIAS record which is resolved internally to AWS. With an ALIAS record you alleviate any DNS caching issues, but still need to update the DNS record to point to the new ELB.
- **listener** - Define the port mappings for the load balancer to the application servers. In this case we will setup only one listner for http traffic on port 80, and then route that traffic back to the application servers also over 80 and using http. In a production environment you would also probably want to setup a listener for https and attach a valid certificate to the load balancer.
- **health_check** - The health check we want the ELB to perform to determine if a node in the cluster is in/out of service. The ELB will not route any traffic to unhealthy hosts.
- **cross_zone_load_balancing** - Boolean parameter to specify whether the hosts will be across multiple availability zones.
- **idle_timeout** - The amount of time in seconds which the ELB will allow an idle connection to stay open between the load balancer and the host before closing the connection. Default value is 60 seconds.
- **connection_draining** - Boolean parameter to specify if active connections from a user to a host in the cluster should gracefully drain before destroying the host.
- **connection_draining_timeout** - The maximum amount of time to wait in seconds for a client connection to a host to be disconnected. The right value here will depend a lot on your application stack and how it functions. If stickiness is important to maintain a user session then setting this value longer or equal to the session length is probably desirable. Without setting this value carefully we might create a scenario where a user's browser can't find the server in the middle of their usage due to an infrastructure change. By carefully setting this value we can ensure that active users aren't simply cutoff in the middle of their session due to ops changes. The default value is 300 seconds. 

### [AWS load balancer stickiness policy](https://www.terraform.io/docs/providers/aws/r/lb_cookie_stickiness_policy.html)

This piece is definitely optional, and might not be desirable depending on the application architecture, but it might be necessary to keep a user pinned to a single server in the cluster in the event their session data is not available on all the hosts. If you are using a cookie to manage all of your session info it doesn't matter, but let's say you went with a docker model with a redis container and an application container on every host, where the application container uses the local redis container to store some session info. In this case it will be important to pin the user to the same server for at least the length of the session, which we can do with a stickiness policy.

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

### [AWS autoscaling group](https://www.terraform.io/docs/providers/aws/r/autoscaling_group.html)

With the launch configuration defined, we can now create an autoscaling group which will utilize the launch configuration for adding nodes to the cluster.

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

 - **max_size** - The maximum number of hosts the autoscaling group will create. When setting this value you need to be conscious of the subnet/(s) which will be used, and their subnet mask. The subnet needs to be able to support the maximum number of hosts the autoscaling group will allow. The public subnets in this example have a 255.255.255.0 subnet mask, which gives enough addresses for a maximum of 256 hosts in each subnet, and with two subnets a total of 512. More than enough for a max of 50.
 - **min_size** - The minimum number of hosts allowed in the cluster.
 - **min_elb_capacity** - The minimum number of healthy hosts which need to exist behind the load balancer at any time. This is a useful variable to set for making infrastructure changes that will result in nodes being added/removed.
 - **launch_configuration** - The launch configuration to use when creating new machines.
 - **health_check_type** - Either EC2 or ELB.
 - **load_balancers** - A list of laod balancer ids to attach the created instances to.
 - **vpc_zone_identifier** - A list of subnet ids to create new instances in.
 - **termination_policies** - The strategy you want terraform to use when destroying nodes in the autoscaling group. Supported values are OldestInstance, NewestInstance, OldestLaunchConfiguration, ClosestToNextInstanceHour, and Default.

 We have used the `lifecycle` variable again to ensure that changes force new items first, before destroying older assets.

 ### [AWS autoscaling policy](https://www.terraform.io/docs/providers/aws/r/autoscaling_policy.html)

 With the ELB, launch config, and autoscaling group defined we can create a working cluster, but without an autoscaling policy and alarm the autoscaling will not execute. Let's define a couple rules which will allow us to scale up the number of cluster nodes by one, and scale them down by one as well.

 ```
resource "aws_autoscaling_policy" "scale-up" {
    name = "${var.app_name}-${var.app_version}-scale-up"
    scaling_adjustment = 1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = "${aws_autoscaling_group.default.name}"
}

resource "aws_autoscaling_policy" "scale-down" {
    name = "${var.app_name}-${var.app_version}-scale-down"
    scaling_adjustment = -1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = "${aws_autoscaling_group.default.name}"
}
 ```

 Above we have defined the "scale-up" and "scale-down" policies, and you can see the very simple +1/-1 set in the scaling adjustment.

- **scaling_adjustment** - The number of instances to create or destroy when the policy is executed. This number will be interpreted differently depending on the `adjustment_type` setting. In this example "scale-up" will add one node, and "scale-down" will remove one node.
- **adjustment_type** - Supported values are ChangeInCapacity, ExactCapacity, and PercentChangeInCapacity.
- **cooldown** - The amount of time in seconds to wait before this autoscaling policy can be triggered and executed again by any alarm. This is really helpful to prevent your autoscaling alarms from creating more machines than needed as the alarm keeps going off, but the boxes are not yet in service behind the ELB. Setting this to slightly longer than the known initialization time for your instances and application will prevent that problem.
- **autoscaling_group_name** - The name of the autoscaling group to use.

### [AWS cloudwatch metric alarm](https://www.terraform.io/docs/providers/aws/r/cloudwatch_metric_alarm.html)

Now we can create the rules which will trigger our "scale-up" and "scale-down" policies. There are many strategies for scaling your cluster nodes. To do it really effectively we need to run the application under true production loads for a while and profile the application. How many requests is it serving? How many open connections? How much CPU does it use? How much memory? If it's a database how fast does the disk space grow? Once you know the profile of the application you can actually plan for when to scale the cluster nodes up and down. Profiling the application is also helpful for choosing the optimal EC2 instance type. But to start you have to make some best guesses, and leave the settings very loose, effectively costing more in the short-run, until the application profile is really understood and scaling can be fully optimized without hindering application performance.

A basic scaling rule that just about any cluster will need is on CPU usage, so let's define a couple rules to scale the cluster based on high and low CPU usage across the nodes.

```
resource "aws_cloudwatch_metric_alarm" "cpu-high" {
    alarm_name = "${var.app_name}-${var.app_version}-cpu-util-high"
    namespace = "AWS/EC2"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods = "1"
    metric_name = "CPUUtilization"
    period = "60"
    statistic = "Average"
    threshold = "10"
    alarm_description = "This metric monitors CPU for high utilization on agent hosts"
    alarm_actions = [
        "${aws_autoscaling_policy.scale-up.arn}"
    ]
    dimensions {
        AutoScalingGroupName = "${aws_autoscaling_group.default.name}"
    }
}

resource "aws_cloudwatch_metric_alarm" "cpu-low" {
    alarm_name = "${var.app_name}-${var.app_version}-cpu-util-low"
    namespace = "AWS/EC2"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods = "15"
    metric_name = "CPUUtilization"
    period = "60"
    statistic = "Average"
    threshold = "2"
    alarm_description = "This metric monitors CPU for low utilization on agent hosts"
    alarm_actions = [
        "${aws_autoscaling_policy.scale-down.arn}"
    ]
    dimensions {
        AutoScalingGroupName = "${aws_autoscaling_group.default.name}"
    }
}
```