# S3 Access based Transition

#Steps
1. Clone the repository

2. docker build -t s3accesstrans .
3. docker run -v ~/repos/s3accesstrans/deploy/:/mnt/s3accesstrans/deploy/ -it s3accesstrans:latest /bin/bash (Optional to mount the deploy directory)

4. aws configure
5. terraform init
6. terraform plan
7. terraform apply