variable "region" {
	default = "us-west-1"
}
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "ssh_key" {}
variable "aws_ami" {
	default = "ami-3a674d5a"
}
variable "app_name" {
	type = "string"
	default = "application"
}
variable "app_version" {
	type = "string"
}
variable "docker_image" {
	type = "string"
}

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "us-west-1"
}

# import the cert into amazon for accessing the boxes
resource "aws_key_pair" "dev" {
  key_name   = "aws.test"
  public_key = "${file(var.ssh_key)}"
}

resource "aws_elb" "default" {
  name = "${var.app_name}"
  subnets = ["${var.subnet_ids}"]
  security_groups = ["${var.security_groups}"]

  lifecycle { 
    prevent_destroy = true 
  }

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

resource "aws_lb_cookie_stickiness_policy" "default" {
  name = "http-sticky-policy"
  load_balancer = "${aws_elb.default.id}"
  lb_port = 80
  cookie_expiration_period = 1200
}

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
    docker run -p 80:80 -d nginx:latest
    HEREDOC
}

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