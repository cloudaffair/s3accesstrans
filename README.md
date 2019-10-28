# S3 Access based Transition

## Schematic System View
![alt text](https://github.com/cloudaffair/s3accesstrans/blob/master/misc/s3accesstrans_schematic_view.png)


##Steps
1. Clone the repository
2. docker build -t s3accesstrans .
3. Make configuration changes in file deploy/s3access.auto.tfvars

4. docker run -v ~/repos/s3accesstrans/deploy/:/mnt/s3accesstrans/deploy/ -it s3accesstrans:latest /bin/bash (Optional to mount the deploy directory)

5. aws configure
6. terraform init
7. terraform plan
8. terraform apply