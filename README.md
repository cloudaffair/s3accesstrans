# S3 Access based Transition

## Overview
This application orchestrates the AWS cloud to manage S3 objects lifecycle transition based on every Object access, 
breaking AWS traditional way of managing the objects transitions based on the age of an object

This application guarantees optimal cost benefit by managing S3 objects transition based on configurable access pattern transition policies and 
eliminates all the lacuna mentioned in the below articles.

https://www.linkedin.com/pulse/aws-s3-intelligent-tiering-right-you-maheshwaran-g

## Schematic System View
![alt text](https://github.com/cloudaffair/s3accesstrans/blob/master/misc/s3accesstrans_schematic_view.png)

## Prerequisite 

* AWS Cloud account
* Provision IAM for access (Lambda, Cloudtrail, S3, Elastic Search)
* Docker 
* Git

## Understanding the Configuration

### Monitoring Bucket Configuration
##### Bucket Name that requires Monitoring
monitoring_bucket = "<<Bucket Name>>"
##### AWS Region of the Bucket configured Above
aws_region = "<<AWS Region>>"

##### Cloudtrail Bucket Name for cloudtrail logs
access_trail_bucket = ""
##### Cloudtrail Bucket prefix for cloud trail logs
access_trail_prefix = ""
##### Cloudtrail log retention period; Make it short as it would have cost impact.
cloudwatch_log_retention_in_days = 14

##### Lambda timeout period; just in case
lambda_timeout = 60

##### Access Based Transition Policy
##### Move all the object not access more than 30 days to STANDARD_IA
transition_rule = "{\"STANDARD_IA\":30}"
##### How frequently Transitions qualification to be performed.
scheduler_expression = "rate(30 minutes)"

## Steps
1. Create a Directory "app" and move to the created directory
```ruby
$ mkdir ~/app
$ cd ~/app
```
2. Clone the repository
```ruby
$ git clone https://github.com/cloudaffair/s3accesstrans.git
$ cd s3accesstrans
```
3. Build Docker Image for `s3accesstrans`  
```ruby
$ docker build -t s3accesstrans .

Once the build is complete; check image created
$ docker images
```
4. Make configuration changes in file deploy/s3access.auto.tfvars 
(use understanding configuration information to configure)

5. Run Docker using the image created #3. 
```ruby
$ docker run -v ~/app/s3accesstrans/deploy/:/mnt/s3accesstrans/deploy/ -it s3accesstrans:latest /bin/bash 

# Configure AWS Key , AWS Secret and AWS region
$ aws configure

# Terraform initialisation
$ terraform init

# Below prompting appears
Initializing the backend...
bucket
  The name of the S3 bucket

  Enter a value: <<Bucket Name>>

key
  The path to the state file inside the bucket

  Enter a value: <<Prefix>>

region
  The region of the S3 bucket.

  Enter a value: <<Region>>

$ terraform plan

$ terraform apply
```
