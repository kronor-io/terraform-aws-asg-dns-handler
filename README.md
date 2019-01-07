# ASG DNS handler

(original version: https://github.com/meltwater/terraform-dns/tree/0.0.1/autoscale)

## Purpose
This module sets up everything necessary for dynamically setting hostnames following a certain pattern on instances spawned by Auto Scaling Groups

## Usage
Create an ASG and set the `mw:hostname_pattern` tag for example like this:

```
mesos-slave-#instanceid.main.dev.infra.internal@Z3QP9GZSRL8IVA
```

Could be interpolated in Terraform like this:

```hcl
tag {
  key = "mw:hostname_pattern"
  value = "${var.hostname_prefix}-#instanceid.${var.vpc_name}.${var.subaccount}.${var.rootaccount}.internal@${var.internal_zone_id}"
  propagate_at_launch = true
}
```
	
Once you have your ASG set up, you can just invoke this module and point it to it:
```hcl
module "clever_name_autoscale_dns" {
  source = "../../dns/autoscale"

  autoscale_update_name = "clever_name"
  autoscale_group_names = "${aws_autoscaling_group.my_asg.name}"
  autoscale_route53zone_arn = "${var.zone_to_manage_records_in}"
}
```

## How does it work?
The module sets up the following

- A SNS topic
- A Lambda function
- A topic subscription sending SNS events to the Lambda function

The Lambda function then does the following:

- Fetch the `mw:hostname_pattern` tag value from the ASG, and parse out the hostname and Route53 zone ID from it.
- If it's a instance being created
	- Fetch internal IP from EC2 API
	- Create a Route53 record pointing the hostname to the IP
	- Set the Name tag of the instance to the initial part of the generated hostname
- If it's an instance being deleted
	- Fetch the internal IP from the existing record from the Route53 API
	- Delete the record

## Setup

Use `aws_autoscaling_notification` resource to hook up your ASG with this module, like so:

```hcl
resource "aws_autoscaling_group" "my_asg" {
  name = "myASG"

  vpc_zone_identifier = [
    "${var.aws_subnets}"
  ]

  min_size = "${var.asg_min_count}"
  max_size = "${var.asg_max_count}"
  desired_capacity = "${var.asg_desired_count}"
  health_check_type = "EC2"
  health_check_grace_period = 300
  force_delete = false

  launch_configuration = "${aws_launch_configuration.my_launch_config.name}"

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key = "mw:hostname_pattern"
    value = "${var.hostname_prefix}-#instanceid.${var.vpc_name}.${var.subaccount}.${var.rootaccount}.internal@${var.internal_zone_id}"
    propagate_at_launch = true
  }
}


resource "aws_autoscaling_notification" "autoscale_handling" {
  group_names = [
    "${aws_autoscaling_group.my_asg.name}"
  ]
  notifications  = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR"
  ]
  topic_arn = "${var.autoscale_handling_sns_topic}"
}


module "autoscale_dns" {
  source = "git::ssh://git@github.com/meltwater/terraform-modules-common.git?ref=<REPLACEME>//asg_dns_handler"

  autoscale_update_name = "my_asg_handler"

  autoscale_route53zone_arn = "${var.internal_zone_id}"

  vpc_name = "${var.vpc_name}"
}

```


## TODO

- Reverse lookup records?