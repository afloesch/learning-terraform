# Creating public and private subnets, with bastion host, MySQL Server, and phpMyAdmin

For this next example we are going to setup a VPC with both a public and a private subnet. The public subnet will be exposed directly to the internet with an internet gateway, like in our previous example, and there will also be a private subnet with a NAT gateway to give the private instances access to the internet. This is a common and useful infrastructure pattern for hosting a web server and a database server without exposing the database to external requests.

 We will expand the examples given by Amazon in [VPC scenario 2](http://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/VPC_Scenario2.html) with a few actual boxes in each subnet, as well as a bastion host for SSH access to each box. For the web server we will run phpMyAdmin to demonstrate connecting to a database, and for the database we will install MySQL on Amazon Linux.

 ## Topics Covered

- [Terraform resources](#terraform-resources)
    - [S3 bucket](#s3-bucket)
    - [S3 bucket object](#s3-bucket-object)
    - [AWS elastic IP](#aws-elastic-ip)
    - [AWS NAT gateway](#aws-nat-gateway)
    - [Resource dependencies](#resource-dependencies)
- [AWS security groups](#aws-security-groups)
- [Instances](#instances)
    - [Bastion host](#bastion-host)
    - [MySQL database](#mysql-database)
    - [phpMyAdmin](#phpmyadmin)
- [Test it](#test-it)
- [Optimizing for production](#optimizing-for-production)

## Terraform resources

### [S3 bucket](https://www.terraform.io/docs/providers/aws/r/s3_bucket.html)

The first resource we should add is an S3 bucket to the example.tf file. We will use this bucket to upload a MySQL configuration file, and then use that file when bootstrapping the database host. We will explain this more with the [MySQL database](#mysql-database).

```
resource "aws_s3_bucket" "b" {
  bucket = "${var.bucket_name}"
  acl = "public-read"
}
```

For this bucket we need to create a new variable for the `bucket_name`, which we can add to the top of the example.tf file, and then define the value in our [terraform.tfvars](terraform.tfvars) file. Pick any unique name for the bucket you would like. 

The `acl` value can be set to any [canned bucket policies](https://docs.aws.amazon.com/AmazonS3/latest/dev/acl-overview.html#canned-acl) which exist in AWS. Since our MySQL config doesn't contain any sensitive data we have given the bucket public-read options. It is also possible to fully customize the bucket policy security using the `policy` parameter.

### [S3 bucket object](https://www.terraform.io/docs/providers/aws/r/s3_bucket_object.html)

With the bucket created we need to upload our MySQL configuration to the bucket. An AWS S3 bucket object represents a discrete asset which you want to upload to S3.

```
resource "aws_s3_bucket_object" "config" {
  bucket = "${aws_s3_bucket.b.bucket}"
  key = "my.cnf"
  source = "config/my.cnf"
  content_type = "plain/text"
  etag = "${md5(file("config/my.cnf"))}"
}
```

Expanding on the single machine inside a VPC example, let's keep everything we have defined for our public subnet the same, but add another subnet which is private and cannot be reached directly from the internet. It will probably be desireable to give the boxes inside the private subnet access to the internet, so for that we will use an AWS NAT gateway to route web requests from the private subnet back to the box.

### [AWS elasic IP](https://www.terraform.io/docs/providers/aws/r/eip.html)

In order to route to the NAT gateway we need to give it an IP address, so let's create an elastic IP which we will attach to the gateway. The only param we need to set is `vpc`, which specifies whether this IP will be used inside a VPC.

```
resource "aws_eip" "nat" {
    vpc = true
}
```

### [AWS NAT gateway](https://www.terraform.io/docs/providers/aws/r/nat_gateway.html)

With an elastic IP allocated we can create the NAT gateway. There are a number of older terraform examples on the web where the NAT gateway is built from a custom linux image optimized for the workload, running on an EC2 instance, but this introduces a single point of failure into your infrastructure. These examples which provision a single box for a NAT gateway were probably created before Amazon had the NAT gateway feature, so a much better approach now would be to use Amazon's NAT gateway which will scale much like a load balancer.

```
resource "aws_nat_gateway" "default" {
  subnet_id = "${aws_subnet.us-west-1a-public.id}"
  allocation_id = "${aws_eip.nat.id}"

  depends_on = ["aws_internet_gateway.default"]
}
```

The only two params required for a NAT gateway are the `subnet_id` to launch the NAT gateway in, and the `allocation_id` for the elastic IP we want to assign to the gateway.

We should create the NAT gateway inside the public subnet, since the public subnet has access to the internet through the internet gateway, and then create a new routing table entry to route traffic from the NAT gateway into our private subnet.

With the `allocation_id` we pass in the elastic IP previously created to assign to our NAT gateway.

### [Resource dependencies](https://www.terraform.io/intro/getting-started/dependencies.html)

The last parameter used in the AWS NAT gateway example is one which is common to *all* terraform resources, `depends_on`. We have not needed this in any of the previous examples, because every resource declared that was dependent on another was referencing the necessary dependency directly in its configuration, so terraform properly sorted out the order for creating our resources. 

In the case of our NAT gateway however, we have something of a dependency on the internet gateway being available, but in the AWS world a NAT gateway has absolutely no dependency on an internet gateway. Without the internet gateway the private subnet clients will not be able to access the internet, so we need to wait for that resource before creating our NAT gateway, which we can tell terraform to do using the `depends_on` variable.

## AWS security groups

Since we are going to be adding a couple more instances in this example, and as a result we will need some more security groups, our example.tf file will end up a little long, so let's create a security.tf file and define all of our security groups there.

The first security group we need to define is for the private subnet hosts, so that they can communicate with the public subnet hosts.

```
resource "aws_security_group" "public" {
  name        = "Public subnet hosts"
  description = "Allow all inbound traffic from the public subnet hosts"
  vpc_id = "${aws_vpc.default.id}"

  tags {
    Name = "Public Subnet Traffic"
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["${aws_subnet.us-west-1a-public.cidr_block}"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}
```

We create an ingress rule which allows all traffic from only the public subnet hosts, from any port or protocol. This gives a lot of flexibility in terms of what ports we want to communicate over, but in a production environment you might modify this to open only the ports you know the private subnet hosts will need to allow communication from the public subnet hosts.

Probably an even more common approach will be to place a load balancer in front of any private subnet clusters, and expose only http and/or https from the LB.

It's also necessary to create an egress rule to allow the private subnet hosts to talk out over any ports or protocols.

Next we need to modify our old "web" security group for the public subnet hosts to accept SSH traffic only from the bastion host, and we will keep 80 open to the world for serving our web site.

```
resource "aws_security_group" "web" {
  name        = "Web Traffic"
  description = "Allow all inbound traffic from http (80) and SSH from the bastion host"
  vpc_id = "${aws_vpc.default.id}"

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
    cidr_blocks = ["${aws_subnet.us-west-1a-public.cidr_block}"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}
```

Lastly, we need to create a security group for our bastion host to accept SSH connections only from our local network.

```
resource "aws_security_group" "bastion" {
  name        = "SSH Traffic"
  description = "Allow only ssh traffic from local network and all outbound traffic"
  vpc_id = "${aws_vpc.default.id}"

  tags {
    Name = "SSH Traffic"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["${var.public_ip}/32"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}
```

Notice how the ingress rule is defined with a variable for `public_ip` address and subnet mask. For this value we use the public IP address of our network, which locks down SSH requests to our bastion host to be allowed only from the local network. Any machines outside of the network will not be able to SSH into the bastion host, which is a good security measure.

The /32 subnet mask is for a subnet with only one host.

To quickly set the public ip address for your current network use the following shell command:

```shell
export TF_VAR_public_ip="$(curl ipecho.net/plain ; echo)"
```

## Instances

### [Bastion host](https://en.wikipedia.org/wiki/Bastion_host)

In a production environment best practices are to limit SSH access to your application boxes from a secure machine hardened against attacks.

Our bastion host example is going to be a basic Amazon Linux AMI which we can SSH to, and then access our private/public subnet hosts from the bastion host.

```
resource "aws_instance" "bastion" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "t2.micro"
    key_name = "${aws_key_pair.dev.key_name}"
    vpc_security_group_ids = ["${aws_security_group.bastion.id}"]
    subnet_id = "${aws_subnet.us-west-1a-public.id}"
    tags {
        Name = "Bastion"
    }
}
```

### MySQL database

The database example is greatly simplified from what would be a true production implementation. Since we are only creating one box it would not scale very well. You could create a very large instance and scale the db that way, but would eventually run into a limit. For a production setup it is optimal to install MySQL cluster and create a cluster of machines which can shard data and scale horizontally with an autoscaling policy. But let's assume our application isn't going to get much traffic, so won't need more than one database server.

```
resource "aws_instance" "db" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "t2.micro"
    key_name = "${aws_key_pair.dev.key_name}"
    vpc_security_group_ids = ["${aws_security_group.public.id}"]
    subnet_id = "${aws_subnet.us-west-1a-private.id}"
    depends_on = ["aws_nat_gateway.default", "aws_s3_bucket_object.config"]

    tags {
      Name = "MySQL"
    }

    ebs_block_device {
      device_name = "/dev/sdh"
      volume_type = "standard"
      iops = "150"
      volume_size = "50"
      delete_on_termination = false
    }

    ebs_block_device {
      device_name = "/dev/sdj"
      volume_type = "standard"
      iops = "150"
      volume_size = "50"
      delete_on_termination = false
    }

    user_data =  <<HEREDOC
    #!/bin/bash
    sudo su

    mdadm --create --verbose /dev/md0 --level=0 --name=MY_RAID --raid-devices=2 /dev/sdh /dev/sdj
    mkfs -t ext4 -L bigdisk /dev/md0
    mkdir -p /mysql
    mount /dev/md0 /mysql

    yum update -y
    yum install -y mysql57-server
    export AWS_ACCESS_KEY_ID=${var.aws_access_key}
    export AWS_SECRET_ACCESS_KEY=${var.aws_secret_key}
    aws s3 cp --region ${var.region} s3://${aws_s3_bucket.b.bucket}/${aws_s3_bucket_object.config.key} /etc/my.cnf
    service mysqld start
    mysql -e "USE mysql; CREATE USER 'admin'@'%' IDENTIFIED BY 'password'; GRANT ALL PRIVILEGES ON * . * TO 'admin'@'%';"
    HEREDOC
}
```

Notice that the `depends_on` variable is used again here to declare the database host dependency on the NAT gateway, and on the MySQL config file. Without the NAT gateway any attempts by the private hosts to reach something over the internet will fail.

We are also creating two AWS EBS volumes to setup a RAID 0 array, effectively doubling our read/write throughput to disk, which is obviously good for a database on disk. There are two parts to this, the first is to provision the volumes using the `ebs_block_device` declaration, and the second part is to actually mount the drives in RAID 0. You can see how the volumes are mounted in the `user_data` value, effectively copying the [AWS instructions](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/raid-config.html) for a RAID array. The volumes we create are simple standard AWS volumes, but for a production instance you would want to evaluate what kind of data you will be storing and choose an optimal [volume type](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSVolumeTypes.html) based on your workloads.

The RAID array is also why we created a custom MySQL config and uploaded it to an S3 bucket. That config is telling MySQL to store the database data in the RAID array we created.

### [phpMyAdmin](#https://www.phpmyadmin.net/)

Instead of using Nginx like in the previous examples, let's run phpMyAdmin in order to demonstrate the public host access to the private host database. PhpMyAdmin provides a web GUI for administering a MySQL server. Since we are using docker all we need to do for our Nginx configuration is change the docker image like in below to use a [phpMyAdmin image](https://hub.docker.com/r/phpmyadmin/phpmyadmin/).

```
resource "aws_instance" "node" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "t2.micro"
    key_name = "${aws_key_pair.dev.key_name}"
    vpc_security_group_ids = ["${aws_security_group.web.id}"]
    subnet_id = "${aws_subnet.us-west-1a-public.id}"

    tags {
        Name = "SQL Admin"
    }

    user_data = <<HEREDOC
    #!/bin/bash
    sudo su
    yum update -y
    yum install -y docker
    service docker start
    docker run --name myadmin -d -e PMA_HOST=${aws_instance.db.private_ip} -p 80:80 phpmyadmin/phpmyadmin
    HEREDOC
}
```

The only setting we need is for the MySQL server host using the PMA_HOST environment variable.

## Test it

With all of our resources defined go and create the infrastructure.

```
terraform apply
```

If you have not defined the `bucket_name` variable value in the .tfvars file, and have not set it in an environment variable, then terraform will prompt you for the value at the command line. Try to pick a unqiue name or terraform will not be able to create the S3 bucket.

If you login to the AWS console you will see this created three new instances for us. Grab the public ip address of the bastion host and SSH into it.

```
ssh-add ~/.ssh/aws.test
ssh -A ec2-user@{bastion_ip}
```

Now from the bastion host you should be able to SSH into any of the other hosts. Get the private ip address of the MySQL server and SSH into it.

```
ssh ec2-user@{mysql_ip}
```

From here you can sudo to root and start running `mysql` commands.

Another way to test the database is through the phpMyAdmin interface we also spun up. Get the public ip address of the SQL Admin box and load it into your browser. If you look at the `user_data` for the MySQL server you will see we created an "admin" user with the password "password". Use these creds to login and start playing with the database.

## Optimizing for production

While this example is fairly complete, there are still a few things we would want to do to really optimize this setup for a production deployment.

Most important would be to setup some IAM users and roles, provision the boxes with an IAM user, and also setup perms on the S3 bucket to only accept requests from that specific IAM user. This will give finer grained access controls and much more flexibility then the AWS access and secret key creds. For example, you could integrate your AD or LDAP user accounts with IAM and control employee access with the company credentials. As part of this it would also be good to remove the default ec2-user from the boxes.

Next we would want to create additional subnets in both the public and private subnets on a new availability zone for high availability. Then we can create duplicate boxes in the new subnets, and create load balancers to route traffic to each individual cluster. This will protect the stack against one AZ in AWS going down. Even better would be to create a federated model and run multiple clusters in multiple AWS regions, and then leverage DNS to route based on the client location.

It would also be good to modify the security groups for the private subnet hosts so that they only open the ports needed from the public hosts, not all ports. 

Lastly it is important to pick an optimal EBS volume type and size for the database, and setup some cloudwatch alarms on the EBS volume disk usage to alert us if the drives are filling up.