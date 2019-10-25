FROM mbalasubramanian/ubuntu-ruby-terraform-base:latest

ENV APP_PATH /mnt/s3accesstrans
RUN mkdir -p $APP_PATH

COPY . $APP_PATH

RUN cd $APP_PATH/S3AccessMonitor && pwd && ./build.sh
RUN cd $APP_PATH/S3Transitioner && pwd && ./build.sh
RUN cd $APP_PATH/S3TransitionExecutor && pwd && ./build.sh

WORKDIR $APP_PATH/deploy
