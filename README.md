# S3 Access based Transition

## Overview
This application orchestrates the AWS cloud to manage the S3 objects lifecycle transition based on every Object access, 
breaking AWS traditional way of managing the objects transitions based on the age of an object

This application guarantees optimal cost benefit by managing S3 objects transition based on configurable access pattern transition policies and 
eliminates all the lacuna mentioned in the below articles.

https://www.linkedin.com/pulse/aws-s3-intelligent-tiering-right-you-maheshwaran-g

## Schematic System View
![alt text](https://github.com/cloudaffair/s3accesstrans/blob/master/misc/s3accesstrans_schematic_view.png)

## Prerequisite 

* AWS Cloud account
* Provision IAM for access
* Docker 

## Understanding the Configuration


## Steps
1. Clone the repository
2. docker build -t s3accesstrans .
3. Make configuration changes in file deploy/s3access.auto.tfvars

4. docker run -v ~/repos/s3accesstrans/deploy/:/mnt/s3accesstrans/deploy/ -it s3accesstrans:latest /bin/bash (Optional to mount the deploy directory)

5. aws configure
6. terraform init
7. terraform plan
8. terraform apply