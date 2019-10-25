#!/usr/bin/env bash
bundle install --path vendor/bundle
zip -r s3transitionexecutor.zip * vendor
