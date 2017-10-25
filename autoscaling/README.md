# Create autoscaling cluster

In this example we are going to pair-back the network resources a little bit and only create a public subnet for our hosts, but we will create two public subnets in different availability zones and load balance across the AZs for high availability. For the application we will use Nginx again.

## Topics Covered

- [Terraform resources](#terraform-resources)
    - [AWS launch configuration](#aws-launch-configuration)
    - AWS autoscaling group
    - AWS autoscaling policy
    - AWS cloudwatch metric alarm

## Terraform resources

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

The second major change is to the machine provisioning in `user_data`. We have added a whole block of bash scripts to setup Cloudwatch monitoring on the cluster hosts. Out-of-the-box the only metrics which Cloudwatch can access are around network requests and CPU usage. If we want to get disk or memory usage stats on the individual hosts then its necessary to run a cron job which reports those metrics up to Cloudwatch. This chunk of scripts is a little ugly for sure, so we will show another approach using docker in the blue/green example.